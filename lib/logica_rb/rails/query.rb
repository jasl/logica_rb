# frozen_string_literal: true

require "pathname"

module LogicaRb
  module Rails
    class Query
      def initialize(definition, connection:, executor: nil, cache: nil)
        @definition = definition
        @connection = connection
        @executor = executor || Executor.new(connection: connection)
        @cache = cache
      end

      attr_reader :definition

      def compile
        if @cache
          return @cache.fetch(@definition, connection: @connection)
        end

        engine = resolve_engine
        import_root = resolve_import_root
        file_path = resolve_logica_file_path(@definition.file, import_root: import_root)

        LogicaRb::Transpiler.compile_file(
          File.realpath(file_path),
          predicates: @definition.predicate.to_s,
          engine: engine,
          user_flags: (@definition.flags || {}).transform_keys(&:to_s),
          import_root: import_root
        )
      end

      def sql(format: :query)
        compile.sql(format)
      end

      def plan_json(pretty: true)
        compile.plan_json(pretty: pretty)
      end

      def result
        @executor.select_all(sql(format: :query))
      end

      def records(model:)
        model.find_by_sql(sql(format: :query))
      end

      def relation(model:, as: nil)
        alias_name = (as || @definition.as || default_alias_name).to_s

        safe_alias = alias_name.gsub(/[^a-zA-Z0-9_]/, "_")
        subquery = "(#{sql(format: :query).strip})"

        rel = model.from(Arel.sql("#{subquery} AS #{safe_alias}"))
        rel.select("#{safe_alias}.*")
      end

      def cte(name:)
        [name, Arel.sql(sql(format: :query))]
      end

      private

      def default_alias_name
        "logica_#{@definition.predicate.to_s.downcase}"
      end

      def resolve_engine
        engine = @definition.engine
        engine = engine.to_s if engine.is_a?(Symbol)
        return engine.to_s if engine && !engine.empty? && engine != "auto"

        cfg = LogicaRb::Rails.configuration
        cfg.default_engine&.to_s || EngineDetector.detect(@connection)
      end

      def resolve_import_root
        import_root = @definition.import_root || LogicaRb::Rails.configuration.import_root
        import_root = import_root.to_path if import_root.respond_to?(:to_path)
        import_root
      end

      def resolve_logica_file_path(file, import_root:)
        file = file.to_s
        return File.expand_path(file) if Pathname.new(file).absolute?
        return File.expand_path(file) if import_root.nil?

        roots = import_root.is_a?(Array) ? import_root : [import_root]
        roots.each do |root|
          next if root.nil? || root.to_s.empty?
          candidate = File.join(root.to_s, file)
          return File.expand_path(candidate) if File.exist?(candidate)
        end

        File.expand_path(File.join(roots.first.to_s, file))
      end
    end
  end
end
