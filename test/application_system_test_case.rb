require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver|
    driver.add_argument("--no-sandbox") if driver.respond_to?(:add_argument)
  end
end
