source "https://rubygems.org"

ruby ">= 3.0"

gem "fastlane", "~> 2.235"
gem "dotenv"

# Stdlib gems extracted from Ruby 3.4+ that fastlane still needs at runtime.
gem "bigdecimal"
gem "logger"
gem "benchmark"
gem "mutex_m"
gem "nkf"
gem "multi_json"
gem "abbrev"

# Load fastlane plugins declared in fastlane/Pluginfile (e.g. versioning).
plugins_path = File.join(File.dirname(__FILE__), "fastlane", "Pluginfile")
eval_gemfile(plugins_path) if File.exist?(plugins_path)
