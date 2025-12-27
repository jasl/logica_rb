# frozen_string_literal: true

require "set"

module LogicaRb
  module SourceSafety
    class Violation < LogicaRb::Error
      attr_reader :reason, :predicate_name

      def initialize(reason, message = nil, predicate_name: nil)
        @reason = reason
        @predicate_name = predicate_name
        super(message || reason.to_s)
      end
    end

    module Validator
      FORBIDDEN_CALLS = {
        "SqlExpr" => :sql_expr,
        "ReadFile" => :file_io,
        "ReadJson" => :file_io,
        "WriteFile" => :file_io,
        "PrintToConsole" => :console,
        "RunClingo" => :external_exec,
        "RunClingoFile" => :external_exec,
        "Intelligence" => :external_exec,
      }.freeze

      def self.validate!(parsed_rules, engine:, capabilities: [])
        capabilities_set = normalize_capabilities(capabilities)

        each_call_predicate_name(parsed_rules) do |predicate_name|
          required = FORBIDDEN_CALLS[predicate_name]
          next unless required
          next if capabilities_set.include?(required)

          raise Violation.new(
            :forbidden_call,
            "Forbidden call in untrusted source: #{predicate_name} (enable capability #{required.inspect} to allow)",
            predicate_name: predicate_name
          )
        end

        nil
      end

      def self.normalize_capabilities(value)
        Array(value)
          .compact
          .map { |c| c.is_a?(Symbol) ? c : c.to_s }
          .map(&:to_s)
          .map(&:strip)
          .reject(&:empty?)
          .map(&:to_sym)
          .to_set
      end
      private_class_method :normalize_capabilities

      def self.each_call_predicate_name(obj, &block)
        return enum_for(:each_call_predicate_name, obj) unless block_given?

        case obj
        when Array
          obj.each { |v| each_call_predicate_name(v, &block) }
        when Hash
          call = obj["call"]
          if call.is_a?(Hash)
            predicate_name = call["predicate_name"]
            yield predicate_name if predicate_name.is_a?(String) && !predicate_name.empty?
          end

          obj.each_value { |v| each_call_predicate_name(v, &block) }
        end
      end
      private_class_method :each_call_predicate_name
    end
  end
end

