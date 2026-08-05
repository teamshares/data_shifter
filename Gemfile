# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "csv" # exercises inline_csv in specs; not a runtime dependency (see gemspec) since it's opt-in
  gem "factory_bot_rails", "~> 6.0"
  gem "rails", "~> 7.0"
  gem "rspec", "~> 3.0"
  gem "rspec-rails", "~> 7.0"
  gem "sidekiq", "~> 8.0"
  gem "sqlite3", "~> 2.0"
end

gem "lefthook", "~> 2.0" # Git-hook manager (pre-commit RuboCop on staged files)
gem "rake", "~> 13.0"
gem "rubocop", "~> 1.21"
