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
end
