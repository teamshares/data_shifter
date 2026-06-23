# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# PRO-2774: track the Axn::Configurable DSL branch until it ships in a release.
# Once axn cuts a release including Axn::Configurable, drop this git pin.
gem "axn", github: "teamshares/axn", branch: "kali/pro-2769-axn-configuration-dsl-for-downstream-gem-consistency"

group :development, :test do
  gem "factory_bot_rails", "~> 6.0"
  gem "rails", "~> 7.0"
  gem "rspec", "~> 3.0"
  gem "rspec-rails", "~> 7.0"
  gem "sidekiq", "~> 8.0"
  gem "sqlite3", "~> 2.0"
end

gem "rake", "~> 13.0"
gem "rubocop", "~> 1.21"
