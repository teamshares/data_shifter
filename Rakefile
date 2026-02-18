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

# Ensure specs and rubocop pass before release (must run first; enhance appends)
release_task = Rake::Task["release"]
release_task.prerequisites.unshift(:default)
