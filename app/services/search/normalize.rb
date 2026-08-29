module Search
  module Normalize
    module_function

    def call(value)
      value.to_s
        .unicode_normalize(:nfkc)
        .downcase
        .gsub(/\s+/, " ")
        .strip
    end
  end
end
