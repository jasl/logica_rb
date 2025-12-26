# frozen_string_literal: true

module LogicaRb
  module Rails
    module ModelDSL
      def self.extended(base)
        base.class_attribute :logica_queries, default: {}, instance_accessor: false
      end

      def logica_query(name, file:, predicate:, engine: :auto, format: :query, flags: {}, as: nil, import_root: nil)
        name = name.to_sym

        definition = QueryDefinition.new(
          name: name,
          file: file,
          predicate: predicate,
          engine: engine,
          format: format,
          flags: flags,
          as: as,
          import_root: import_root
        )

        self.logica_queries = logica_queries.merge(name => definition)
        definition
      end

      def logica(name, connection: nil, **overrides)
        name = name.to_sym
        base_definition = logica_queries.fetch(name) { raise ArgumentError, "Unknown logica query: #{name}" }

        connection ||= ActiveRecord::Base.connection
        cfg = LogicaRb::Rails.configuration

        resolved_import_root =
          if overrides.key?(:import_root)
            overrides[:import_root]
          else
            base_definition.import_root || cfg.import_root
          end

        resolved_engine = resolve_engine(
          overrides.key?(:engine) ? overrides[:engine] : base_definition.engine,
          connection: connection,
          cfg: cfg
        )

        resolved_flags = (base_definition.flags || {}).merge(overrides[:flags] || {})

        definition = base_definition.with(
          file: overrides.fetch(:file, base_definition.file),
          predicate: overrides.fetch(:predicate, base_definition.predicate),
          format: overrides.fetch(:format, base_definition.format || :query).to_sym,
          engine: resolved_engine,
          flags: resolved_flags,
          as: overrides.fetch(:as, base_definition.as),
          import_root: resolved_import_root
        )

        cache = cfg.cache ? LogicaRb::Rails.cache : nil

        Query.new(
          definition,
          connection: connection,
          executor: Executor.new(connection: connection),
          cache: cache
        )
      end

      def logica_sql(name, **opts)
        logica(name, **opts).sql
      end

      def logica_result(name, **opts)
        logica(name, **opts).result
      end

      def logica_relation(name, **opts)
        logica(name, **opts).relation(model: self)
      end

      def logica_records(name, **opts)
        logica(name, **opts).records(model: self)
      end

      private

      def resolve_engine(engine, connection:, cfg:)
        engine = engine.to_sym if engine.is_a?(String) && !engine.empty?

        resolved =
          case engine
          when nil, :auto
            cfg.default_engine&.to_s || EngineDetector.detect(connection)
          else
            engine.to_s
          end

        resolved
      end
    end
  end
end
