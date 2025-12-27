# frozen_string_literal: true

require "test_helper"
require "json"
require "yaml"

require_relative "../support/db_smoke/reference_plan_executor"
require_relative "../support/db_smoke/psql_adapter"
require_relative "../support/result_table_parser"

class PsqlDbResultsTest < Minitest::Test
  MANIFEST_PATH = File.expand_path("../fixtures_manifest.yml", __dir__)
  FIXTURES_ROOT = File.expand_path("../fixtures", __dir__)

  PSQL_CASES = %w[
    psql_combine2_test
    psql_combine_test
    psql_explicit_typing_test
    psql_pair_test
    psql_plusplus_test
    psql_record_combine_test
    psql_simple_structs_test
    psql_structs_ground_test
    psql_test
    psqld_empty_list_type_test
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
      engine: "psql",
      import_root: import_root
    )
  end

  def stable_sort_rows(rows)
    Array(rows).sort_by do |row|
      Array(row).map { |v| v.nil? ? [0, ""] : [1, v.to_s] }
    end
  end

  def test_psql_db_results
    skip "Set LOGICA_DB_RESULTS=1 to enable DB results tests" unless ENV["LOGICA_DB_RESULTS"] == "1"

    database_url = ENV["DATABASE_URL"].to_s
    database_url = ENV["LOGICA_PSQL_URL"].to_s if database_url.empty?
    skip "Set DATABASE_URL (or LOGICA_PSQL_URL) to run Postgres results tests" if database_url.empty?

    probe = LogicaRb::DbSmoke::PsqlAdapter.build(database_url: database_url)
    skip "pg gem not installed (run bundle install)" unless probe
    probe.close

    entries_by_name =
      manifest
        .fetch("tests")
        .fetch("psql")
        .each_with_object({}) { |e, h| h[e.fetch("name")] = e }

    PSQL_CASES.each do |name|
      entry = entries_by_name.fetch(name)
      compilation = compile_case(entry)
      plan_hash = JSON.parse(compilation.plan_json(pretty: true))

      golden_text = File.binread(File.join(FIXTURES_ROOT, entry.fetch("golden")))
      expected = ResultTableParser.parse(golden_text)

      adapter = LogicaRb::DbSmoke::PsqlAdapter.build(database_url: database_url)
      begin
        LogicaRb::DbSmoke::ReferencePlanExecutor.execute!(adapter, plan_hash)

        plan_hash.fetch("outputs").each do |out|
          node_name = out.fetch("node")
          node = plan_hash.fetch("config").find { |n| n["name"] == node_name }
          raise "missing output node in config: #{node_name}" if node.nil?

          sql = node.dig("action", "sql")
          actual = adapter.select_all(sql)

          assert_equal expected.fetch("columns"), actual.fetch("columns"), "psql columns mismatch: #{name}"
          assert_equal stable_sort_rows(expected.fetch("rows")), stable_sort_rows(actual.fetch("rows")), "psql rows mismatch: #{name}"
        end
      rescue StandardError => e
        raise e.class, "psql results failed: #{name}: #{e.message}", e.backtrace
      ensure
        adapter&.close
      end
    end
  end
end
