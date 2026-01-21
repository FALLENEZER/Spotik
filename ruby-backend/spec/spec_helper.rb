# RSpec configuration for Spotik Ruby Backend

require 'bundler/setup'
require 'rspec'
require 'rack/test'

# Set test environment before loading application
ENV['APP_ENV'] = 'test'

# Load application
require_relative '../server'

# Configure RSpec
RSpec.configure do |config|
  # Include Rack::Test methods
  config.include Rack::Test::Methods

  # Define app for Rack::Test
  def app
    SpotikServer
  end

  # Skip database cleaner for now since we don't have database tests yet
  # We'll add this back when we implement database models

  # RSpec configuration
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end

# Property-based testing configuration
require 'rantly'
require 'rantly/rspec_extensions'

RSpec.configure do |config|
  # Property-based test configuration
  config.before(:each, :property) do
    # Set up property test environment
  end
end