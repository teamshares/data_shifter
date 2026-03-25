# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:default, :development, :test)

# All specs run against the embedded Rails dummy app under spec/dummy_app.
require_relative "dummy_app/spec/spec_helper"
