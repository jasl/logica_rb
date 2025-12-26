# frozen_string_literal: true

module LogicaRb
  module SqlSafety
    class Violation < LogicaRb::Error
      attr_reader :reason

      def initialize(reason, message = nil)
        @reason = reason
        super(message || reason.to_s)
      end
    end
  end
end
