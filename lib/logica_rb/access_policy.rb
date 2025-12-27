# frozen_string_literal: true

require "set"

module LogicaRb
  AccessPolicy = Data.define(
    :engine,
    :trust,
    :capabilities,
    :allowed_relations,
    :allowed_functions,
    :allowed_schemas,
    :denied_schemas,
    :tenant,
    :timeouts
  ) do
    def initialize(
      engine: nil,
      trust: nil,
      capabilities: nil,
      allowed_relations: nil,
      allowed_functions: nil,
      allowed_schemas: nil,
      denied_schemas: nil,
      tenant: nil,
      timeouts: nil
    )
      engine = normalize_optional_string(engine)
      trust = normalize_optional_symbol(trust)

      normalized_capabilities =
        if capabilities.nil?
          nil
        else
          self.class.normalize_capabilities(capabilities)
        end

      allowed_relations = normalize_identifier_list(allowed_relations)
      allowed_functions = normalize_allowed_functions(allowed_functions)
      allowed_schemas = normalize_identifier_list(allowed_schemas)
      denied_schemas = normalize_identifier_list(denied_schemas)

      super(
        engine: engine,
        trust: trust,
        capabilities: normalized_capabilities,
        allowed_relations: allowed_relations,
        allowed_functions: allowed_functions,
        allowed_schemas: allowed_schemas,
        denied_schemas: denied_schemas,
        tenant: tenant,
        timeouts: timeouts
      )
    end

    def trusted?
      trust == :trusted
    end

    def untrusted?
      trust == :untrusted
    end

    def cache_key_data(engine: nil)
      resolved_engine = (engine.nil? ? self.engine : normalize_optional_string(engine)).to_s

      {
        engine: resolved_engine,
        trust: trust&.to_s,
        capabilities: effective_capabilities.map(&:to_s).sort,
        allowed_relations: Array(allowed_relations).map(&:to_s).sort,
        allowed_functions: effective_allowed_functions(engine: resolved_engine).map(&:to_s).sort,
        allowed_schemas: Array(allowed_schemas).map(&:to_s).sort,
        denied_schemas: effective_denied_schemas(engine: resolved_engine).map(&:to_s).sort,
      }
    end

    def self.trusted(engine: nil, **kwargs)
      new(**kwargs.merge(engine: engine, trust: :trusted))
    end

    def self.untrusted(engine: nil, **kwargs)
      base = { engine: engine, trust: :untrusted }
      new(**base.merge(kwargs))
    end

    def effective_denied_schemas(engine: nil)
      return denied_schemas if !denied_schemas.nil?

      self.class.default_denied_schemas(engine || self.engine)
    end

    def effective_allowed_functions(engine: nil)
      resolved_engine = normalize_optional_string(engine) || self.engine

      return self.class.default_allowed_functions(resolved_engine) if allowed_functions.nil?

      resolved_engine = resolved_engine.to_s.strip.downcase

      if allowed_functions.key?(resolved_engine)
        return allowed_functions.fetch(resolved_engine)
      end

      if allowed_functions.key?("*")
        return allowed_functions.fetch("*")
      end

      if allowed_functions.key?("all")
        return allowed_functions.fetch("all")
      end

      return allowed_functions.values.first if allowed_functions.length == 1

      self.class.default_allowed_functions(resolved_engine)
    end

    def effective_capabilities
      return capabilities if !capabilities.nil?

      []
    end

    def self.default_denied_schemas(engine)
      case engine.to_s
      when "psql"
        %w[pg_catalog information_schema]
      when "sqlite"
        %w[sqlite_master sqlite_temp_master]
      else
        %w[pg_catalog information_schema sqlite_master sqlite_temp_master]
      end
    end

    SQLITE_DEFAULT_ALLOWED_FUNCTIONS = Set.new(
      %w[
        argmin argmax fingerprint assemblerecord disassemblerecord
        char
        distinctlistagg sortlist in_list join_strings magicalentangle printf
        json_extract json_group_array json_array_length json_each json_tree json_array
        date julianday
        cast coalesce
        count sum min max avg group_concat
      ]
    ).freeze

    PSQL_DEFAULT_ALLOWED_FUNCTIONS = Set.new(
      %w[
        unnest
        md5 substr row_to_json chr
        generate_series array_agg array_length string_to_array
        ln
        least greatest
        cast coalesce
        count sum min max avg
      ]
    ).freeze

    def self.default_allowed_functions(engine)
      case engine.to_s
      when "sqlite"
        SQLITE_DEFAULT_ALLOWED_FUNCTIONS.to_a.sort
      when "psql"
        PSQL_DEFAULT_ALLOWED_FUNCTIONS.to_a.sort
      else
        (SQLITE_DEFAULT_ALLOWED_FUNCTIONS | PSQL_DEFAULT_ALLOWED_FUNCTIONS).to_a.sort
      end
    end

    def self.normalize_capabilities(value)
      Array(value)
        .compact
        .map { |c| c.is_a?(Symbol) ? c : c.to_s }
        .map(&:to_s)
        .map(&:strip)
        .reject(&:empty?)
        .map(&:to_sym)
        .uniq
    end

    private

    def normalize_optional_string(value)
      return nil if value.nil?

      str =
        if value.respond_to?(:to_path)
          value.to_path
        else
          value.to_s
        end

      str = str.strip
      return nil if str.empty?

      str
    end

    def normalize_optional_symbol(value)
      return nil if value.nil?

      sym =
        if value.is_a?(String)
          v = value.strip
          return nil if v.empty?

          v.to_sym
        else
          value.to_sym
        end

      sym
    end

    def normalize_identifier_list(value)
      return nil if value.nil?

      list =
        Array(value)
          .compact
          .map(&:to_s)
          .map(&:strip)
          .reject(&:empty?)
          .map(&:downcase)
          .uniq

      list
    end

    def normalize_allowed_functions(value)
      return nil if value.nil?

      if value.is_a?(Hash)
        value.each_with_object({}) do |(k, v), h|
          key = normalize_optional_string(k) || "*"
          key = key.strip.downcase

          list = normalize_identifier_list(v) || []
          h[key] = list
        end
      else
        { "*" => (normalize_identifier_list(value) || []) }
      end
    end
  end
end
