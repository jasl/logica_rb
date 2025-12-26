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
        cache = @cache || CompilerCache.new
        cache.fetch(@definition, connection: @connection)
      end

      def sql(format: :query)
        format = (format || :query).to_sym
        enforce_source_policy!(format: format)
        compile.sql(format)
      end

      def plan_json(pretty: true)
        enforce_source_policy!(format: :plan)
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

      def cte(name = nil, model: nil, **kwargs)
        name = kwargs.fetch(:name, name)
        raise ArgumentError, "cte name must be provided" if name.nil? || name.to_s.empty?

        cte_name = name.to_sym
        cte_value =
          if model
            relation(model: model, as: cte_name)
          else
            Arel.sql(sql(format: :query))
          end

        { cte_name => cte_value }
      end

      private

      def default_alias_name
        "logica_#{@definition.predicate.to_s.downcase}"
      end

      def enforce_source_policy!(format:)
        return nil unless @definition.source
        return nil if @definition.trusted
        return nil if format.to_sym == :query

        raise ArgumentError, "source queries require format: :query unless trusted: true"
      end
    end
  end
end
