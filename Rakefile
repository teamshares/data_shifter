# frozen_string_literal: true

require "bundler/gem_tasks"
require "rubocop/rake_task"

task :spec do
  sh "bundle exec rspec"
end

RuboCop::RakeTask.new

task default: %i[spec rubocop]

# Ensure specs and rubocop pass before release (must run first; enhance appends)
release_task = Rake::Task["release"]
release_task.prerequisites.unshift(:default)
