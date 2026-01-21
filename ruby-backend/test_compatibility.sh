#!/bin/bash

# Comprehensive Compatibility Test Suite Execution Script
# **Feature: ruby-backend-migration, Task 16.1: Create comprehensive compatibility test suite**

set -e

echo "🧪 Ruby Backend Migration - Comprehensive Compatibility Test Suite"
echo "=================================================================="
echo

# Check if we're in the right directory
if [ ! -f "run_compatibility_tests.rb" ]; then
    echo "❌ Error: Must be run from ruby-backend directory"
    echo "Usage: cd ruby-backend && ./test_compatibility.sh"
    exit 1
fi

# Check Ruby version
echo "🔍 Checking Ruby version..."
ruby_version=$(ruby --version)
echo "Ruby version: $ruby_version"

# Check if bundler is available
if ! command -v bundle &> /dev/null; then
    echo "❌ Error: Bundler not found. Please install bundler:"
    echo "gem install bundler"
    exit 1
fi

# Install dependencies
echo
echo "📦 Installing dependencies..."
bundle install --quiet

# Check database connection
echo
echo "🗄️  Checking database connection..."
if ! bundle exec ruby -e "require_relative 'config/test_database'; puts 'Database connection: OK'" 2>/dev/null; then
    echo "⚠️  Warning: Database connection failed. Some tests may fail."
    echo "Make sure PostgreSQL is running and test database is configured."
    echo
fi

# Set test environment
export APP_ENV=test
export JWT_SECRET=test_jwt_secret_key_for_testing_purposes_only
export JWT_TTL=60

# Create test results directory
mkdir -p test_results/compatibility

echo
echo "🚀 Starting compatibility test execution..."
echo

# Run the comprehensive compatibility test suite
ruby run_compatibility_tests.rb

exit_code=$?

echo
echo "=================================================================="
if [ $exit_code -eq 0 ]; then
    echo "✅ All compatibility tests passed successfully!"
    echo "🎉 Ruby backend is fully compatible with Legacy_System"
else
    echo "❌ Some compatibility tests failed"
    echo "🔧 Review test results and fix compatibility issues"
fi

echo
echo "📄 Test results saved in: test_results/compatibility/"
echo "📊 View detailed results in the generated JSON and text files"

exit $exit_code