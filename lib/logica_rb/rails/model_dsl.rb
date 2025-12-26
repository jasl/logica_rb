# frozen_string_literal: true

module LogicaRb
  module Rails
    module ModelDSL
      def logica_query(name, file:, predicate:, engine: nil, format: :query, flags: {})
        logica_queries[name.to_sym] = {
          file: file,
          predicate: predicate,
          engine: engine,
          format: format,
          flags: flags,
        }
      end

      def logica_sql(name, engine: nil, format: nil, flags: nil, user_flags: nil, import_root: nil)
        definition = logica_queries.fetch(name.to_sym) do
          raise ArgumentError, "Unknown logica query: #{name}"
        end

        compilation = compile_logica_definition(
          definition,
          engine: engine,
          format: format,
          flags: flags,
          user_flags: user_flags,
          import_root: import_root
        )

        compilation.sql(compilation_format(definition, format))
      end

      def logica_result(name, **override)
        sql = logica_sql(name, **override)
        ActiveRecordExecutor.new(connection: connection).select_all(sql)
      end

      private

      def logica_queries
        @logica_queries ||= {}
      end

      def compilation_format(definition, format)
        (format || definition.fetch(:format, LogicaRb::Rails.configuration.default_format || :query)).to_sym
      end

      def compile_logica_definition(definition, engine:, format:, flags:, user_flags:, import_root:)
        cfg = LogicaRb::Rails.configuration

        resolved_import_root = import_root || cfg.import_root
        resolved_import_root = resolved_import_root.to_path if resolved_import_root.respond_to?(:to_path)

        resolved_engine =
          (engine || definition[:engine] || cfg.default_engine)&.to_s ||
            EngineDetector.detect(connection)

        resolved_user_flags = {}
        resolved_user_flags.merge!(definition.fetch(:flags, {}))
        resolved_user_flags.merge!(flags || {})
        resolved_user_flags.merge!(user_flags || {})

        file = definition.fetch(:file).to_s
        file_path = resolve_logica_file_path(file, import_root: resolved_import_root)

        LogicaRb::Transpiler.compile_file(
          file_path,
          predicates: definition.fetch(:predicate),
          engine: resolved_engine,
          user_flags: resolved_user_flags,
          import_root: resolved_import_root
        )
      end

      def resolve_logica_file_path(file, import_root:)
        return file if file.start_with?("/")
        return file if import_root.nil?

        root_for_path =
          if import_root.is_a?(Array)
            import_root.first
          else
            import_root
          end
        return file if root_for_path.nil? || root_for_path.to_s.empty?

        File.join(root_for_path.to_s, file)
      end
    end
  end
end
