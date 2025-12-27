# frozen_string_literal: true

require "set"

module LogicaRb
  module SqlSafety
    module FunctionAllowlistValidator
      NON_FUNCTION_PAREN_KEYWORDS = Set.new(
        %w[
          from join where group order having limit offset window fetch union except intersect
          select with as on
          in exists over filter within values
          any all
        ]
      ).freeze

      WORD_TOKEN = /\A[A-Za-z_][A-Za-z0-9_$]*\z/.freeze

      TOKEN_REGEX = /
        "(?:[^"]|"")*" |           # double-quoted identifier
        `(?:[^`]|``)*` |           # backtick-quoted identifier
        \[(?:[^\]]|\]\])*\] |      # bracket-quoted identifier
        [A-Za-z_][A-Za-z0-9_$]* |  # bare identifier
        [().]                      # punctuation
      /x.freeze

      def self.validate!(sql, engine: nil, allowed_functions: nil)
        sql = sql.to_s
        engine = engine.to_s
        engine = nil if engine.empty?

        allowed_functions ||= LogicaRb::AccessPolicy.default_allowed_functions(engine)
        allowlist = normalize_allowlist(allowed_functions)

        cleaned = LogicaRb::SqlSafety::QueryOnlyValidator.strip_comments_and_strings(sql)
        used = scan_functions_from_cleaned(cleaned)

        used.each do |func|
          next if allowlist.include?(func)

          raise LogicaRb::SqlSafety::Violation.new(
            :function_not_allowed,
            "SQL function is not allowed: #{func}",
            details: func
          )
        end

        used
      end

      def self.scan_functions(sql)
        cleaned = LogicaRb::SqlSafety::QueryOnlyValidator.strip_comments_and_strings(sql.to_s)
        scan_functions_from_cleaned(cleaned)
      end

      def self.scan_functions_from_cleaned(cleaned_sql)
        tokens = cleaned_sql.to_s.scan(TOKEN_REGEX)

        used = []
        seen = {}

        tokens.each_index do |idx|
          next unless tokens[idx + 1] == "("

          func = normalize_qualified_identifier(tokens, idx)
          next if func.nil?
          next if !func.include?(".") && NON_FUNCTION_PAREN_KEYWORDS.include?(func)
          next if seen[func]

          seen[func] = true
          used << func
        end

        used
      end
      private_class_method :scan_functions_from_cleaned

      def self.normalize_allowlist(value)
        Array(value)
          .compact
          .map { |v| normalize_qualified_identifier_string(v) }
          .compact
          .uniq
          .to_set
      end
      private_class_method :normalize_allowlist

      def self.normalize_qualified_identifier(tokens, idx)
        name = normalize_identifier_token(tokens[idx])
        return nil if name.nil?

        parts = [name]

        j = idx - 1
        while j >= 1 && tokens[j] == "."
          prefix = normalize_identifier_token(tokens[j - 1])
          break if prefix.nil?

          parts.unshift(prefix)
          j -= 2
        end

        parts.join(".")
      end
      private_class_method :normalize_qualified_identifier

      def self.normalize_qualified_identifier_string(value)
        s = value.to_s.strip
        return nil if s.empty?

        parts = s.split(".").map(&:strip)
        norm = parts.map { |part| normalize_identifier_text(part) }
        return nil if norm.any?(&:nil?)

        norm.join(".")
      end
      private_class_method :normalize_qualified_identifier_string

      def self.normalize_identifier_token(tok)
        return nil if tok.nil? || tok.empty?

        if tok.start_with?("\"") && tok.end_with?("\"") && tok.length >= 2
          raw = tok[1..-2].gsub("\"\"", "\"")
          return raw.strip.downcase
        end

        if tok.start_with?("`") && tok.end_with?("`") && tok.length >= 2
          raw = tok[1..-2].gsub("``", "`")
          return raw.strip.downcase
        end

        if tok.start_with?("[") && tok.end_with?("]") && tok.length >= 2
          raw = tok[1..-2].gsub("]]", "]")
          return raw.strip.downcase
        end

        return nil unless WORD_TOKEN.match?(tok)

        tok.downcase
      end
      private_class_method :normalize_identifier_token

      def self.normalize_identifier_text(text)
        tok = text.to_s.strip
        return nil if tok.empty?

        normalize_identifier_token(tok)
      end
      private_class_method :normalize_identifier_text
    end
  end
end
