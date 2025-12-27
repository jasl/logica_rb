# frozen_string_literal: true

require "test_helper"

class RailsQuerySourceSafetyTest < Minitest::Test
  def test_untrusted_source_query_raises_violation_for_dangerous_sql
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil(x:) :-
        `((select 1 as x; select 2 as x))`(x:);
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    assert_raises(LogicaRb::SqlSafety::Violation) { query.result }
  end

  def test_untrusted_source_query_rejects_sqlexpr
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil() = SqlExpr("1", {x: 1});
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    assert_raises(LogicaRb::SourceSafety::Violation) { query.sql }
  end

  def test_untrusted_source_query_rejects_file_io_builtins
    begin
      require "active_record"
    rescue LoadError
      skip "activerecord not installed"
    end

    require "logica_rb/rails"

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    source = <<~LOGICA
      @Engine("sqlite");

      Evil() = ReadFile("/tmp/x");
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    assert_raises(LogicaRb::SourceSafety::Violation) { query.sql }

    source = <<~LOGICA
      @Engine("sqlite");

      Evil() :- WriteFile("/tmp/x", content: "[1,2,3]") == "OK";
    LOGICA

    query = LogicaRb::Rails.query(source: source, predicate: "Evil", trusted: false)

    assert_raises(LogicaRb::SourceSafety::Violation) { query.sql }
  end
end
