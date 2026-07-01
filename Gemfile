# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# PRO-2774: track axn main now that the Axn::Configurable DSL is merged.
# PRO-2846: pinned past main to a branch adding the raw_<name> accessor
# Shift#progress depends on (teamshares/axn#135, not yet merged).
# Once that PR merges, switch back to `branch: "main"`; once axn cuts a
# release including Axn::Configurable, drop this git pin entirely.
gem "axn", github: "teamshares/axn", branch: "kali/raw-override-accessor"

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
