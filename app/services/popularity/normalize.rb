module Popularity
  module Normalize
    LOG_SCALES = {
      "github" => 6.0,
      "qiita" => 4.0,
      "zenn" => 4.0,
      "manual" => 4.0
    }.freeze

    module_function

    def call(provider:, raw_value:)
      raw = [ raw_value.to_i, 0 ].max
      return 0.0 if raw.zero?

      scale = LOG_SCALES.fetch(provider.to_s, 4.0)
      (Math.log10(raw + 1) / scale).clamp(0.0, 1.0).round(5)
    end
  end
end
