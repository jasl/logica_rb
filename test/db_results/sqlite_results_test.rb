# frozen_string_literal: true

require "test_helper"
require "json"
require "yaml"

require_relative "../support/db_smoke/reference_plan_executor"
require_relative "../support/db_smoke/sqlite_adapter"
require_relative "../support/result_table_parser"

class SqliteDbResultsTest < Minitest::Test
  MANIFEST_PATH = File.expand_path("../fixtures_manifest.yml", __dir__)
  FIXTURES_ROOT = File.expand_path("../fixtures", __dir__)

  SQLITE_CASES = %w[
    functor_arg_update_test
    import_root_test
    rec_small_cycle_test
    sqlite_assignment_test
    sqlite_combine_test
    sqlite_composite_test
    sqlite_functor_over_constant_test
    sqlite_functors_test
    sqlite_groupby_test
    sqlite_in_expr_test
    sqlite_math_test
    sqlite_records_test
    sqlite_subquery_test
    sqlite_unwrapping_test
    ultra_short_cycle_test
    unification_priority_test
  ].freeze

  def manifest
    @manifest ||= YAML.load_file(MANIFEST_PATH)
  end

  def compile_case(entry)
    src = File.join(FIXTURES_ROOT, entry.fetch("src"))
    predicate = entry["predicate"] || "Test"
    import_root = entry["import_root"] ? File.join(FIXTURES_ROOT, entry["import_root"]) : FIXTURES_ROOT

    LogicaRb::Transpiler.compile_file(
      src,
      predicates: predicate,
      engine: "sqlite",
      import_root: import_root
    )
  end

  def stable_sort_rows(rows)
    Array(rows).sort_by do |row|
      Array(row).map { |v| v.nil? ? [0, ""] : [1, v.to_s] }
    end
  end

  def test_sqlite_db_results
    skip "Set LOGICA_DB_RESULTS=1 to enable DB results tests" unless ENV["LOGICA_DB_RESULTS"] == "1"

    probe = LogicaRb::DbSmoke::SqliteAdapter.build
    skip "sqlite3 gem not installed (run bundle install)" unless probe
    probe.close

    entries_by_name =
      manifest
        .fetch("tests")
        .fetch("sqlite")
        .each_with_object({}) { |e, h| h[e.fetch("name")] = e }

    SQLITE_CASES.each do |name|
      entry = entries_by_name.fetch(name)
      compilation = compile_case(entry)
      plan_hash = JSON.parse(compilation.plan_json(pretty: true))

      golden_text = File.binread(File.join(FIXTURES_ROOT, entry.fetch("golden")))
      expected = ResultTableParser.parse(golden_text)

      adapter = LogicaRb::DbSmoke::SqliteAdapter.build
      begin
        LogicaRb::DbSmoke::ReferencePlanExecutor.execute!(adapter, plan_hash)

        plan_hash.fetch("outputs").each do |out|
          node_name = out.fetch("node")
          node = plan_hash.fetch("config").find { |n| n["name"] == node_name }
          raise "missing output node in config: #{node_name}" if node.nil?

          sql = node.dig("action", "sql")
          actual = adapter.select_all(sql)

          assert_equal expected.fetch("columns"), actual.fetch("columns"), "sqlite columns mismatch: #{name}"
          assert_equal stable_sort_rows(expected.fetch("rows")), stable_sort_rows(actual.fetch("rows")), "sqlite rows mismatch: #{name}"
        end
      rescue StandardError => e
        raise e.class, "sqlite results failed: #{name}: #{e.message}", e.backtrace
      ensure
        adapter&.close
      end
    end
  end
end
