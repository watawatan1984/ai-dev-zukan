require "test_helper"

class Popularity::NormalizeTest < ActiveSupport::TestCase
  test "returns a bounded logarithmic score for GitHub stars" do
    assert_equal 0.0, Popularity::Normalize.call(provider: :github, raw_value: 0)
    assert_operator Popularity::Normalize.call(provider: :github, raw_value: 1_000), :>,
      Popularity::Normalize.call(provider: :github, raw_value: 100)
    assert_equal 1.0, Popularity::Normalize.call(provider: :github, raw_value: 10_000_000)
  end

  test "normalizes article reactions on a smaller scale" do
    github_score = Popularity::Normalize.call(provider: :github, raw_value: 1_000)
    qiita_score = Popularity::Normalize.call(provider: :qiita, raw_value: 1_000)

    assert_operator qiita_score, :>, github_score
  end
end
