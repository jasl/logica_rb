# frozen_string_literal: true

require "test_helper"
require "yaml"

class ManifestTests < Minitest::Test
  MANIFEST_PATH = File.expand_path("fixtures_manifest.yml", __dir__)
  FIXTURES_ROOT = File.expand_path("fixtures", __dir__)

  def manifest
    @manifest ||= YAML.load_file(MANIFEST_PATH)
  end

  def run_case(entry, runner: entry["runner"], import_root: entry["import_root"])
    src = File.join(FIXTURES_ROOT, entry.fetch("src"))
    predicate = entry["predicate"] || "Test"
    import_root = import_root ? File.join(FIXTURES_ROOT, import_root) : FIXTURES_ROOT

    LogicaRb::Runner.run_predicate(
      src: src,
      predicate: predicate,
      import_root: import_root,
      runner: runner
    )
  end

  def read_golden(entry)
    File.binread(File.join(FIXTURES_ROOT, entry.fetch("golden")))
  end

  def test_sqlite_manifest
    manifest.fetch("tests").fetch("sqlite").each do |entry|
      output = run_case(entry)
      assert_equal read_golden(entry), output, "sqlite mismatch: #{entry.fetch("name")}"
    end
  end

  def test_psql_manifest
    if ENV["LOGICA_PSQL_CONNECTION"].to_s.empty?
      warn "[psql] Skipping psql manifest: set LOGICA_PSQL_CONNECTION to enable PostgreSQL tests."
      skip "LOGICA_PSQL_CONNECTION not set"
    end

    manifest.fetch("tests").fetch("psql").each do |entry|
      output = run_case(entry)
      assert_equal read_golden(entry), output, "psql mismatch: #{entry.fetch("name")}"
    end
  end

  def test_type_inference_manifest
    manifest.fetch("tests").fetch("type_inference_psql").each do |entry|
      src = File.join(FIXTURES_ROOT, entry.fetch("src"))
      output = LogicaRb::Runner.infer_types(src: src, dialect: "psql", import_root: FIXTURES_ROOT)
      assert_equal read_golden(entry), output, "typing mismatch: #{entry.fetch("name")}"
    end
  end

  def test_unsupported_smoke_manifest
    manifest.fetch("tests").fetch("unsupported_smoke").each do |entry|
      src = File.join(FIXTURES_ROOT, entry.fetch("src"))
      predicate = entry["predicate"] || "Test"
      assert_raises(LogicaRb::UnsupportedEngineError) do
        LogicaRb::Runner.run_predicate(
          src: src,
          predicate: predicate,
          import_root: FIXTURES_ROOT,
          runner: "default"
        )
      end
    end
  end
end
