# frozen_string_literal: true

require "set"

module LogicaRb
  AccessPolicy = Data.define(
    :engine,
    :trust,
    :capabilities,
    :allowed_relations,
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
      allowed_schemas = normalize_identifier_list(allowed_schemas)
      denied_schemas = normalize_identifier_list(denied_schemas)

      super(
        engine: engine,
        trust: trust,
        capabilities: normalized_capabilities,
        allowed_relations: allowed_relations,
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
  end
end
