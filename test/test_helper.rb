# frozen_string_literal: true

unless ENV["NO_COVERAGE"] == "1"
  require "simplecov"

  SimpleCov.start do
    root File.expand_path("..", __dir__)
    track_files "lib/**/*.rb"

    enable_coverage :branch

    add_filter "/test/"
    add_filter "/dummy/"
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "logica_rb"

require "minitest/autorun"
