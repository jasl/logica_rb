# frozen_string_literal: true

module LogicaRb
  module Rails
    Configuration = Data.define(
      :import_root,
      :default_format,
      :default_engine,
      :cache
    )
  end
end
