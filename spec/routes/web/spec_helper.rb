# frozen_string_literal: true

require_relative "../spec_helper"

css_file = File.expand_path("../../../assets/css/app.css", __dir__)
File.write(css_file, "") unless File.file?(css_file)

require "capybara"
require "capybara/rspec"
require "capybara/validate_html5" if ENV["CLOVER_FREEZE"] == "1"

Gem.suffix_pattern

Capybara.app = Clover.app
Capybara.exact = true

module RackTestPlus
  include Rack::Test::Methods

  def app
    Capybara.app
  end
end

# Work around Middleware should not call #each error.
# Fix bugs with cookies, because the default behavior
# reuses the rack env of the last request, which is not valid.
class Capybara::RackTest::Browser
  remove_method :refresh
  def refresh
    visit last_request.fullpath
  end
end

RSpec.configure do |config|
  config.include RackTestPlus
  config.include Capybara::DSL
  config.after do
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end
end

def login(email = TEST_USER_EMAIL, password = TEST_USER_PASSWORD)
  visit "/login"
  fill_in "Email Address", with: email
  fill_in "Password", with: password
  click_button "Sign in"

  expect(page.title).to end_with("Dashboard")
end
