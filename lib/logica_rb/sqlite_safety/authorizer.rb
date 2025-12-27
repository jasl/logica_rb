# frozen_string_literal: true

require "set"

module LogicaRb
  module SqliteSafety
    module Authorizer
      SQLITE_OK = 0
      SQLITE_DENY = 1

      ACTION_READ = 20
      ACTION_SELECT = 21
      ACTION_FUNCTION = 31

      SAFE_VIRTUAL_TABLES = Set.new(%w[json_each json_tree]).freeze
      FORBIDDEN_FUNCTIONS = Set.new(%w[load_extension readfile writefile]).freeze

      def self.with_untrusted_policy(db, access_policy)
        policy = access_policy
        return yield unless policy&.trust == :untrusted

        denied = policy.effective_denied_schemas(engine: "sqlite").map(&:downcase).to_set
        allowed = policy.allowed_relations
        allowed_set = allowed.nil? ? nil : Array(allowed).map(&:to_s).map(&:strip).reject(&:empty?).map(&:downcase).to_set

        begin
          db.enable_load_extension(false) if db.respond_to?(:enable_load_extension)
        rescue StandardError
          # ignore
        end

        prev = db.instance_variable_get(:@authorizer)

        db.authorizer = lambda do |action, arg1, arg2, dbname, _source|
          case action
          when ACTION_SELECT
            SQLITE_OK
          when ACTION_FUNCTION
            name = arg2.to_s.downcase
            FORBIDDEN_FUNCTIONS.include?(name) ? SQLITE_DENY : SQLITE_OK
          when ACTION_READ
            table = arg1.to_s.downcase
            schema = dbname.to_s.downcase

            return SQLITE_DENY if denied.include?(schema) || denied.include?(table)
            return SQLITE_OK if SAFE_VIRTUAL_TABLES.include?(table)
            return SQLITE_DENY if allowed_set.nil? || allowed_set.empty?

            qualified = "#{schema}.#{table}"
            (allowed_set.include?(table) || allowed_set.include?(qualified)) ? SQLITE_OK : SQLITE_DENY
          else
            SQLITE_DENY
          end
        end

        yield
      ensure
        begin
          db.authorizer = prev
        rescue StandardError
          # ignore
        end
      end
    end
  end
end
