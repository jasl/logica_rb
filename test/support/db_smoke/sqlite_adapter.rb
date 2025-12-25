# frozen_string_literal: true

require "digest"
require "json"

module LogicaRb
  module DbSmoke
    class SqliteAdapter
      def self.build
        require "sqlite3"
        adapter = new(SQLite3::Database.new(":memory:"))
        adapter.register_functions!
        adapter
      rescue LoadError
        nil
      end

      def initialize(db)
        @db = db
      end

      def exec_script(sql)
        @db.execute_batch(sql.to_s)
      end

      def close
        @db.close
      end

      def register_functions!
        register_magical_entangle!
        register_in_list!
        register_join_strings!
        register_split!
        register_fingerprint!
        register_record_helpers!
      end

      private

      def register_magical_entangle!
        @db.create_function("MagicalEntangle", 2) do |func, a, b|
          func.result =
            if b.nil?
              nil
            elsif b.is_a?(Numeric) ? b.zero? : b.to_s == "0"
              a
            else
              nil
            end
        end
      end

      def register_in_list!
        @db.create_function("IN_LIST", 2) do |func, element, list_json|
          if element.nil? || list_json.nil?
            func.result = nil
            next
          end

          list =
            begin
              JSON.parse(list_json.to_s)
            rescue JSON::ParserError
              []
            end
          list = [] unless list.is_a?(Array)

          func.result = list.include?(element) ? 1 : 0
        end
      end

      def register_join_strings!
        @db.create_function("JOIN_STRINGS", 2) do |func, list_json, delimiter|
          if list_json.nil?
            func.result = nil
            next
          end

          list =
            begin
              JSON.parse(list_json.to_s)
            rescue JSON::ParserError
              []
            end
          list = [list] unless list.is_a?(Array)

          func.result = list.map(&:to_s).join(delimiter.to_s)
        end
      end

      def register_split!
        @db.create_function("SPLIT", 2) do |func, text, delimiter|
          if text.nil?
            func.result = nil
            next
          end

          delim = delimiter.to_s
          parts = text.to_s.split(delim)
          func.result = JSON.generate(parts)
        end
      end

      def register_fingerprint!
        @db.create_function("Fingerprint", 1) do |func, value|
          bytes = Digest::SHA256.digest(value.to_s)
          func.result = bytes.byteslice(0, 8).unpack1("q>")
        end
      end

      def register_record_helpers!
        @db.create_function("AssembleRecord", 1) do |func, field_values_json|
          arr =
            begin
              JSON.parse(field_values_json.to_s)
            rescue JSON::ParserError
              []
            end
          arr = [] unless arr.is_a?(Array)

          record = {}
          arr.each do |entry|
            next unless entry.is_a?(Hash)
            key = entry["arg"]
            next unless key.is_a?(String)
            record[key] = entry["value"]
          end

          func.result = JSON.generate(record)
        end

        @db.create_function("DisassembleRecord", 1) do |func, record_json|
          record =
            begin
              JSON.parse(record_json.to_s)
            rescue JSON::ParserError
              {}
            end
          record = {} unless record.is_a?(Hash)

          arr = record.map { |k, v| { "arg" => k.to_s, "value" => v } }
          func.result = JSON.generate(arr)
        end
      end
    end
  end
end
