# frozen_string_literal: true

require "securerandom"

module LogicaRb
  module DbSmoke
    class PsqlAdapter
      def self.build(database_url:)
        require "pg"

        conn = PG.connect(database_url)
        schema = "logica_smoke_#{SecureRandom.hex(8)}"
        adapter = new(conn, schema)
        adapter.setup!
        adapter
      rescue LoadError
        nil
      end

      def initialize(conn, schema)
        @conn = conn
        @schema = schema
      end

      attr_reader :conn

      def setup!
        @conn.exec("CREATE SCHEMA #{@schema};")
        @conn.exec("SET search_path TO #{@schema}, public;")
      end

      def exec_script(sql)
        @conn.exec(rewrite_schema(sql.to_s))
      end

      def select_all(sql)
        sql = sql.to_s.strip.sub(/;\s*\z/, "")
        res = @conn.exec(rewrite_schema(sql))

        {
          "columns" => res.fields,
          "rows" => res.values.map do |row|
            row.map { |v| v.nil? || v == "NULL" ? nil : v.to_s }
          end,
        }
      end

      def close
        @conn.exec("DROP SCHEMA IF EXISTS #{@schema} CASCADE;")
      ensure
        @conn.close if @conn
      end

      private

      def rewrite_schema(sql)
        sql.gsub(/\blogica_home\b/, @schema)
      end
    end
  end
end
