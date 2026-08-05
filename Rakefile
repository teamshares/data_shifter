# frozen_string_literal: true

require "bundler/gem_tasks"
require "rubocop/rake_task"

task :spec do
  sh "bundle exec rspec"
end

RuboCop::RakeTask.new

task default: %i[spec rubocop]

# Gate release on tests, the axn-core way: `release` (from bundler/gem_tasks) depends on `build`,
# so enhancing `build` to require the default task (specs + RuboCop) runs the full suite before the
# gem is built or pushed — a failure aborts the release before any tag/push. Mirrors axn core's
# `Rake::Task["build"].enhance([:verify])`.
Rake::Task["build"].enhance([:default])
