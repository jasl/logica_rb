# frozen_string_literal: true

require "test_helper"

class FunctionAllowlistValidatorTest < Minitest::Test
  def validate!(sql, **opts)
    LogicaRb::SqlSafety::FunctionAllowlistValidator.validate!(sql, **opts)
  end

  def test_rejects_non_allowlisted_function
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!("SELECT my_evil(1)", engine: "sqlite", allowed_functions: ["coalesce"])
      end

    assert_equal :function_not_allowed, err.reason
    assert_equal "my_evil", err.details
  end

  def test_ignores_strings_and_comments
    sql = <<~SQL
      SELECT 'pg_read_file(' AS s, COALESCE(NULL, 1) AS x -- pg_read_file(1)
    SQL

    used = validate!(sql, engine: "psql", allowed_functions: ["coalesce"])
    assert_equal ["coalesce"], used
  end

  def test_handles_escaped_quotes_and_semicolons_inside_strings
    sql = "SELECT 'abc''; DROP TABLE users; --' AS s, COALESCE('a', 'b') AS x"

    used = validate!(sql, engine: "psql", allowed_functions: ["coalesce"])
    assert_equal ["coalesce"], used
  end

  def test_extracts_schema_qualified_function_name
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        sql = %q(SELECT "pg_catalog"."pg_read_file"('/etc/passwd'))
        validate!(sql, engine: "psql", allowed_functions: [])
      end

    assert_equal :function_not_allowed, err.reason
    assert_equal "pg_catalog.pg_read_file", err.details
  end

  def test_does_not_treat_in_as_a_function
    used = validate!("SELECT 1 WHERE 1 IN (SELECT 1)", engine: "psql", allowed_functions: [])
    assert_equal [], used
  end
end
