# frozen_string_literal: true

module LogicaRb
  module Util
    module_function

    def deep_copy(obj)
      case obj
      when Hash
        obj.each_with_object({}) { |(k, v), h| h[deep_copy(k)] = deep_copy(v) }
      when Array
        obj.map { |v| deep_copy(v) }
      else
        begin
          obj.dup
        rescue TypeError
          obj
        end
      end
    end

    def sort_keys_recursive(obj)
      case obj
      when Hash
        obj.keys.sort_by(&:to_s).each_with_object({}) do |key, h|
          h[key] = sort_keys_recursive(obj[key])
        end
      when Array
        obj.map { |v| sort_keys_recursive(v) }
      else
        obj
      end
    end
  end
end
