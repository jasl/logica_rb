# frozen_string_literal: true

require "json"
require "pg"
require "bigdecimal"
require "set"

module LogicaRb
  module Common
    module PsqlLogica
      module_function

      @extra_hash_records = Set.new

      def with_extra_hash_records(records)
        previous = @extra_hash_records
        normalized = records.map { |keys| keys.map(&:to_s).sort }
        @extra_hash_records = Set.new(normalized)
        yield
      ensure
        @extra_hash_records = previous
      end

      class CompositeDecoder < PG::SimpleDecoder
        @registry = {}

        class << self
          attr_reader :registry
        end

        def name=(value)
          @name = value
          if @type_map && @field_names
            self.class.registry[@name] = { type_map: @type_map, field_names: @field_names }
          end
        end

        def name
          @name
        end

        def initialize(*args, type_map: nil, field_names: nil, **kwargs)
          super(*args, **kwargs)
          return if type_map.nil? && field_names.nil?
          @type_map = type_map
          @field_names = field_names
          @record_decoder = PG::TextDecoder::Record.new(type_map: type_map)
          @format = 0
          self.class.registry[@name] = { type_map: @type_map, field_names: @field_names } if @name
        end

        def initialize_copy(other)
          super
          @record_decoder = other.instance_variable_get(:@record_decoder)
          @type_map = other.instance_variable_get(:@type_map)
          @field_names = other.instance_variable_get(:@field_names)
          @format = other.instance_variable_get(:@format)
        end

        def format
          @format
        end

        def format=(value)
          @format = value
        end

        def decode(string, _tuple = nil, _field = nil)
          return nil if string.nil?
          decoder = @record_decoder
          field_names = @field_names
          if decoder.nil? && @type_map
            decoder = PG::TextDecoder::Record.new(type_map: @type_map)
          end
          if (decoder.nil? || field_names.nil?) && @name && self.class.registry.key?(@name)
            entry = self.class.registry[@name]
            field_names = entry[:field_names]
            decoder = PG::TextDecoder::Record.new(type_map: entry[:type_map]) if decoder.nil?
          end
          raise "Composite decoder not initialized for #{@name}" if decoder.nil? || field_names.nil?
          values = decoder.decode(string)
          result = {}
          field_names.each_with_index { |name, idx| result[name] = values[idx] }
          result
        end
      end

      def postgres_execute(sql, connection)
        result = connection.exec(sql)
        register_composite_types_from_sql(sql, connection)
        result = result.map_types!(connection.type_map_for_results) if result
        result
      rescue PG::UndefinedTable => e
        raise LogicaRb::TypeInference::Research::Infer::TypeErrorCaughtException.new(
          LogicaRb::TypeInference::Research::Infer::ContextualizedError.build_nice_message(
            "Running SQL.", "Undefined table used: #{e}"
          )
        )
      rescue PG::Error => e
        connection.reset
        raise e
      end

      def digest_psql_type(value)
        case value
        when Hash
          if keep_hash_record?(value)
            value.each_with_object({}) { |(k, v), h| h[k] = digest_psql_type(v) }
          else
            composite_record_literal(value)
          end
        when Array
          if value.all? { |v| v.is_a?(Hash) && !keep_hash_record?(v) }
            composite_array_literal(value)
          else
            value.map { |v| digest_psql_type(v) }
          end
        when BigDecimal
          if value.frac.zero?
            value.to_i
          else
            value.to_f
          end
        else
          value
        end
      end

      def scalar_record?(record)
        record.values.all? do |v|
          v.nil? || v.is_a?(Numeric) || v.is_a?(String) || v == true || v == false
        end
      end

      def keep_hash_record?(record)
        keys = record.keys.map(&:to_s).sort
        return true if keys == %w[arg value]
        return true if @extra_hash_records.include?(keys)
        false
      end

      def composite_array_literal(records)
        elements = records.map do |record|
          fields = record.values.map { |v| composite_field_literal(v) }
          tuple = "(#{fields.join(',')})"
          if tuple.match?(/[",\\{}\s]/) || tuple.include?(",")
            escaped = tuple.gsub("\\", "\\\\").gsub('"', '\\"')
            "\"#{escaped}\""
          else
            tuple
          end
        end
        "{#{elements.join(',')}}"
      end

      def composite_field_literal(value)
        return "" if value.nil?
        return "t" if value == true
        return "f" if value == false
        if value.is_a?(BigDecimal)
          value = value.frac.zero? ? value.to_i : value.to_f
        end
        return value.to_s if value.is_a?(Numeric)
        if value.is_a?(Hash)
          s = composite_record_literal(value)
        elsif value.is_a?(Array)
          s = array_literal(value)
        else
          s = value.to_s
        end
        return '""' if s.empty?
        if s.match?(/[",\\()\s]/) || s.include?(",")
          '"' + s.gsub("\\", "\\\\").gsub('"', '""') + '"'
        else
          s
        end
      end

      def composite_record_literal(record)
        fields = record.values.map { |v| composite_field_literal(v) }
        "(#{fields.join(',')})"
      end

      def array_literal(array)
        if array.all? { |v| v.is_a?(Hash) }
          composite_array_literal(array)
        else
          elements = array.map { |v| array_element_literal(v) }
          "{#{elements.join(',')}}"
        end
      end

      def array_element_literal(value)
        return "NULL" if value.nil?
        if value.is_a?(BigDecimal)
          value = value.frac.zero? ? value.to_i : value.to_f
        end
        return value.to_s if value.is_a?(Numeric)
        return "t" if value == true
        return "f" if value == false
        s = value.to_s
        return '""' if s.empty?
        if s.match?(/[",\\{}\s]/) || s.include?(",")
          '"' + s.gsub("\\", "\\\\").gsub('"', '""') + '"'
        else
          s
        end
      end

      def connect_to_postgres(mode)
        connection_str = nil
        if mode == "interactive"
          connection_str = ENV["LOGICA_PSQL_CONNECTION"]
        elsif mode == "environment"
          connection_str = ENV.fetch("LOGICA_PSQL_CONNECTION")
        else
          raise "Unknown mode: #{mode}"
        end

        connection = if connection_str.start_with?("postgres")
          PG.connect(connection_str)
        else
          PG.connect(JSON.parse(connection_str))
        end
        connection.type_map_for_results = PG::BasicTypeMapForResults.new(connection)
        connection
      end

      def register_composite_types_from_sql(sql, connection)
        type_names = sql.scan(/-- Logica type: (\w+)/).flatten
        return if type_names.empty?

        registry = connection.instance_variable_get(:@logica_type_registry)
        registry ||= PG::BasicTypeRegistry.new.register_default_types
        registered = connection.instance_variable_get(:@logica_registered_types) || {}

        type_names.each do |type_name|
          next if type_name == "logicarecord893574736"
          next if registered[type_name]

          field_names, field_oids = composite_field_info(connection, type_name)
          type_map = composite_field_type_map(connection, registry, type_name, field_oids)
          decoder = CompositeDecoder.new(type_map: type_map, field_names: field_names)
          decoder.name = type_name
          registry.register_coder(decoder)

          array_type_name = composite_array_type_name(connection, type_name)
          if array_type_name
            array_decoder = PG::TextDecoder::Array.new(name: array_type_name)
            array_decoder.elements_type = decoder
            registry.register_coder(array_decoder)
          end

          registered[type_name] = true
        end

        connection.instance_variable_set(:@logica_type_registry, registry)
        connection.instance_variable_set(:@logica_registered_types, registered)
        connection.type_map_for_results = PG::BasicTypeMapForResults.new(connection, registry: registry)
      end

      def composite_field_info(connection, type_name)
        sql = <<~SQL
          SELECT a.attname, a.atttypid
          FROM pg_attribute a
          JOIN pg_type t ON t.typrelid = a.attrelid
          WHERE t.typname = $1 AND a.attnum > 0 AND NOT a.attisdropped
          ORDER BY a.attnum
        SQL
        res = connection.exec_params(sql, [type_name])
        names = []
        oids = []
        res.each do |row|
          names << row["attname"]
          oids << row["atttypid"].to_i
        end
        [names, oids]
      end

      def composite_field_type_map(connection, registry, type_name, _field_oids)
        base_map = PG::BasicTypeMapForResults.new(connection, registry: registry)
        sample = connection.exec("SELECT (NULL::#{type_name}).*")
        base_map.build_column_map(sample)
      end

      def composite_array_type_name(connection, type_name)
        res = connection.exec_params("SELECT typarray FROM pg_type WHERE typname = $1", [type_name])
        return nil if res.ntuples.zero?
        array_oid = res.getvalue(0, 0).to_i
        return nil if array_oid.zero?
        res2 = connection.exec_params("SELECT typname FROM pg_type WHERE oid = $1", [array_oid])
        return nil if res2.ntuples.zero?
        res2.getvalue(0, 0)
      end
    end
  end
end
