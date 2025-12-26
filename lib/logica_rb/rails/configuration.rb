# frozen_string_literal: true

module LogicaRb
  module Rails
    Configuration = Data.define(
      :import_root,
      :cache,
      :cache_mode,
      :default_engine
    )
  end
end
