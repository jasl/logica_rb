# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "type_inference" => "TypeInference",
  "cli" => "CLI"
)
loader.setup

module LogicaRb
  class Error < StandardError; end
  class UnsupportedEngineError < Error; end
end
