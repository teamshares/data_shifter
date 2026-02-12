# frozen_string_literal: true

require "bundler/gem_tasks"
require "rubocop/rake_task"

task :spec do
  Dir.chdir("spec/dummy_app") do
    sh "BUNDLE_GEMFILE=Gemfile bundle exec rspec spec/"
  end
end

RuboCop::RakeTask.new

task default: %i[spec rubocop]
