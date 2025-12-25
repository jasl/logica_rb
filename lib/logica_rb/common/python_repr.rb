# frozen_string_literal: true

module LogicaRb
  module Common
    module PythonRepr
      module_function

      def format(value, top_level: true)
        case value
        when Hash
          inner = value.map { |k, v| "#{format(k, top_level: false)}: #{format(v, top_level: false)}" }.join(", ")
          "{#{inner}}"
        when Array
          inner = value.map { |v| format(v, top_level: false) }.join(", ")
          "[#{inner}]"
        when String
          if top_level
            value
          else
            "'" + value.gsub("\\", "\\\\").gsub("'", "\\\\'") + "'"
          end
        when Symbol
          if top_level
            value.to_s
          else
            "'" + value.to_s.gsub("\\", "\\\\").gsub("'", "\\\\'") + "'"
          end
        when TrueClass
          "True"
        when FalseClass
          "False"
        when NilClass
          "None"
        else
          value.to_s
        end
      end
    end
  end
end
