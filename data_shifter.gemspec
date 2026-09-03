# frozen_string_literal: true

require_relative "lib/data_shifter/version"

Gem::Specification.new do |spec|
  spec.name = "data_shifter"
  spec.version = DataShifter::VERSION
  spec.authors = ["Kali Donovan"]
  spec.email = ["kali@teamshares.com"]

  spec.summary = "Rake-backed data migrations with dry-run, progress bars, and one-liner registration."
  spec.description = "DataShifter: backfills and one-off fixes as rake tasks. Dry run by default, " \
                     "auto rollback, progress bars, consistent summaries."
  spec.homepage = "https://github.com/teamshares/data_shifter"
  spec.license = "MIT"

  # NOTE: depends on axn which requires 3.2.1+
  spec.required_ruby_version = ">= 3.2.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/teamshares/data_shifter/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Allowlist (not a denylist): enumerate only the shippable surface so nothing
  # internal (docs, tooling, agent notes) silently leaks into the packaged gem.
  spec.files = IO.popen(
    %w[git ls-files -z --
       lib README.md CHANGELOG.md LICENSE.txt],
    chdir: __dir__, err: IO::NULL,
  ) { |ls| ls.readlines("\x0", chomp: true) }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.2"
  spec.add_dependency "activesupport", ">= 7.2"
  spec.add_dependency "axn", ">= 0.1.0-alpha.6", "< 0.2.0" # A terse convention for business logic
  spec.add_dependency "railties", ">= 7.2"
  spec.add_dependency "ruby-progressbar", ">= 1.13"
  spec.add_dependency "webmock", ">= 3.18"
end
