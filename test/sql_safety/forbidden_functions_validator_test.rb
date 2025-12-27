# frozen_string_literal: true

require "test_helper"

class ForbiddenFunctionsValidatorTest < Minitest::Test
  def validate!(sql, **opts)
    LogicaRb::SqlSafety::ForbiddenFunctionsValidator.validate!(sql, **opts)
  end

  def test_rejects_admin_and_dos_functions_psql
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!("SELECT pg_cancel_backend(123)", engine: "psql")
      end

    assert_equal :forbidden_function, err.reason
    assert_match(/pg_cancel_backend/i, err.message)
  end

  def test_rejects_schema_qualified_calls_psql
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!("SELECT pg_catalog.pg_sleep_for('1 second')", engine: "psql")
      end

    assert_equal :forbidden_function, err.reason
    assert_match(/pg_sleep_for/i, err.message)
  end

  def test_rejects_quoted_function_name_psql
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(%(SELECT "pg_reload_conf"()), engine: "psql")
      end

    assert_equal :forbidden_function, err.reason
    assert_match(/pg_reload_conf/i, err.message)
  end

  def test_ignores_strings_and_comments
    validate!("SELECT 'pg_reload_conf()' AS msg", engine: "psql")
    validate!("SELECT 1 /* pg_cancel_backend(123) */", engine: "psql")
  end
end

