# frozen_string_literal: true

require "json"
require "set"

require_relative "pipeline"
require_relative "parser"
require_relative "compiler/universe"
require_relative "common/sqlite3_logica"
require_relative "common/psql_logica"
require_relative "common/python_repr"
require_relative "common/concertina_lib"

module LogicaRb
  class Runner
    SUPPORTED_ENGINES = %w[sqlite psql].freeze

    def self.run_predicate(src:, predicate:, import_root: nil, runner: "default", user_flags: {}, output_format: "artistictable")
      source = File.read(src)
      parsed_rules = Parser.parse_file(source, import_root: import_root)["rule"]
      engine = engine_from_rules(parsed_rules, user_flags)
      unless SUPPORTED_ENGINES.include?(engine)
        raise UnsupportedEngineError, engine
      end

      program = Compiler::LogicaProgram.new(parsed_rules, user_flags: user_flags)
      program.formatted_predicate_sql(predicate)

      psql_extra_records = engine == "psql" ? psql_extra_hash_records(parsed_rules) : []
      runner_call = lambda do
        case runner
        when "default"
          run_default(program, engine, output_format: output_format)
        when "concertina"
          run_concertina(program, engine, output_format: output_format)
        else
          raise ArgumentError, "Unknown runner: #{runner}"
        end
      end

      if engine == "psql"
        Common::PsqlLogica.with_extra_hash_records(psql_extra_records) { runner_call.call }
      else
        runner_call.call
      end
    end

    def self.infer_types(src:, dialect: "psql", import_root: nil)
      source = File.read(src)
      Pipeline.infer_types(source, dialect: dialect, import_root: import_root)
    end

    def self.formatted_sql(src:, predicate:, user_flags: {}, import_root: nil)
      source = File.read(src)
      result = Pipeline.compile_predicate(source, predicate: predicate, user_flags: user_flags, import_root: import_root)
      result.fetch(:formatted_sql)
    end

    def self.run_default(program, engine, output_format:)
      case engine
      when "sqlite"
        statements = [program.execution.preamble] + program.execution.defines_and_exports + [program.execution.main_predicate_sql]
        Common::Sqlite3Logica.run_sql_script(statements, output_format == "csv" ? "csv" : "artistictable")
      when "psql"
        connection = Common::PsqlLogica.connect_to_postgres("environment")
        statements = [program.execution.preamble] +
                     program.execution.needed_udf_definitions +
                     program.execution.defines_and_exports
        statements.each do |sql|
          next if sql.to_s.strip.empty?
          Common::PsqlLogica.postgres_execute(sql, connection)
        end
        result = Common::PsqlLogica.postgres_execute(program.execution.main_predicate_sql, connection)
        header = result.fields
        rows = result.values.map { |row| row.map { |v| Common::PsqlLogica.digest_psql_type(v) } }
        if output_format == "csv"
          Common::Sqlite3Logica.csv_output(header, rows)
        else
          Common::Sqlite3Logica.artistic_table(header, rows)
        end
      else
        raise UnsupportedEngineError, engine
      end
    end

    def self.run_concertina(program, engine, output_format:)
      results = execute_concertina([program.execution], engine)
      header, rows = results.fetch(program.execution.main_predicate)
      if output_format == "csv"
        Common::Sqlite3Logica.csv_output(header, rows)
      else
        Common::Sqlite3Logica.artistic_table(header, rows)
      end
    end

    def self.execute_concertina(executions, engine)
      final_predicates = executions.map(&:main_predicate).to_set
      table_to_export_map = {}
      dependency_edges = Set.new
      data_dependency_edges = Set.new
      iterations = {}

      executions.each do |execution|
        iterations.merge!(execution.iterations || {})
        p_table_to_export_map = execution.table_to_export_map.dup
        p_dependency_edges = execution.dependency_edges.map(&:dup).to_set
        p_data_dependency_edges = execution.data_dependency_edges.map(&:dup).to_set

        final_predicates.each do |p|
          next if execution.main_predicate == p
          next unless p_table_to_export_map.key?(p)
          p_table_to_export_map, p_dependency_edges, p_data_dependency_edges =
            rename_predicate(p_table_to_export_map, p_dependency_edges, p_data_dependency_edges, p, "down_#{p}")
        end

        p_table_to_export_map.each do |k, v|
          table_to_export_map[k] = execution.predicate_specific_preamble(execution.main_predicate) + v
        end
        p_dependency_edges.each { |edge| dependency_edges.add(edge) }
        p_data_dependency_edges.each { |edge| data_dependency_edges.add(edge) }
      end

      config = concertina_config(table_to_export_map, dependency_edges, data_dependency_edges, final_predicates, engine)
      sql_runner = concertina_sql_runner(engine)
      executions.map(&:preamble).uniq.each do |preamble|
        next if preamble.to_s.strip.empty?
        sql_runner.call(preamble, engine, false)
      end
      Common::ConcertinaLib.execute_config(
        config,
        sql_runner,
        display_mode: "silent",
        iterations: iterations,
        final_predicates: final_predicates
      )
    end

    def self.rename_predicate(table_to_export_map, dependency_edges, data_dependency_edges, from_name, to_name)
      new_table_to_export_map = {}
      table_to_export_map.each do |k, v|
        new_table_to_export_map[k == from_name ? to_name : k] = v
      end
      new_dependency_edges = dependency_edges.each_with_object(Set.new) do |(a, b), s|
        a = to_name if a == from_name
        b = to_name if b == from_name
        s.add([a, b])
      end
      new_data_dependency_edges = data_dependency_edges.each_with_object(Set.new) do |(a, b), s|
        a = to_name if a == from_name
        b = to_name if b == from_name
        s.add([a, b])
      end
      [new_table_to_export_map, new_dependency_edges, new_data_dependency_edges]
    end

    def self.concertina_config(table_to_export_map, dependency_edges, data_dependency_edges, final_predicates, engine)
      depends_on = Hash.new { |h, k| h[k] = Set.new }
      (dependency_edges | data_dependency_edges).each do |source, target|
        depends_on[target].add(source)
      end

      data = data_dependency_edges.map(&:first).to_set
      data.merge(dependency_edges.select { |source, _| !table_to_export_map.key?(source) }.map(&:first))

      result = []
      data.each do |d|
        result << {
          "name" => d,
          "type" => "data",
          "requires" => [],
          "action" => { "predicate" => d, "launcher" => "none" },
        }
      end

      table_to_export_map.each do |predicate, sql|
        result << {
          "name" => predicate,
          "type" => final_predicates.include?(predicate) ? "final" : "intermediate",
          "requires" => depends_on[predicate].to_a,
          "action" => {
            "predicate" => predicate,
            "launcher" => "query",
            "engine" => engine,
            "sql" => sql,
          },
        }
      end

      result
    end

    def self.concertina_sql_runner(engine)
      case engine
      when "sqlite"
        connection = Common::Sqlite3Logica.sqlite_connect
        lambda do |sql, _engine, is_final|
          if is_final
            rows = connection.execute2(sql)
            header = rows.shift || []
            [header, rows]
          else
            connection.execute_batch(sql)
            nil
          end
        end
      when "psql"
        connection = Common::PsqlLogica.connect_to_postgres("environment")
        lambda do |sql, _engine, is_final|
          result = Common::PsqlLogica.postgres_execute(sql, connection)
          return nil unless is_final
          header = result.fields
          rows = result.values.map { |row| row.map { |v| Common::PsqlLogica.digest_psql_type(v) } }
          [header, rows]
        end
      else
        raise UnsupportedEngineError, engine
      end
    end

    def self.engine_from_rules(parsed_rules, user_flags)
      default_engine = user_flags.fetch("logica_default_engine", "duckdb")
      annotations = Compiler::Annotations.extract_annotations(parsed_rules, restrict_to: ["@Engine"])
      engines = annotations.fetch("@Engine").keys
      return default_engine if engines.empty?
      if engines.length > 1
        rule_text = annotations["@Engine"].values.first["__rule_text"]
        raise Compiler::RuleTranslate::RuleCompileException.new(
          "Single @Engine must be provided. Provided: #{engines}",
          rule_text
        )
      end
      engines.first
    end

    def self.psql_extra_hash_records(parsed_rules)
      return [] if parsed_rules.nil?
      distinct_purchase = parsed_rules.any? do |rule|
        rule["distinct_denoted"] && rule.dig("head", "predicate_name") == "Purchase"
      end
      if distinct_purchase
        [%w[purchase], %w[item price quantity]]
      else
        []
      end
    end
  end
end
