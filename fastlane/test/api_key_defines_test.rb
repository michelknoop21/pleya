# Regressie op fastlane/Fastfile#api_key_defines.
# Draaien: ruby fastlane/test/api_key_defines_test.rb
require "minitest/autorun"
require "shellwords"

FASTFILE = File.expand_path("../Fastfile", __dir__)
DEFINITION = File.read(FASTFILE)[/^def api_key_defines\n.*?^end\n/m]
raise "api_key_defines niet gevonden in #{FASTFILE}" unless DEFINITION

class Harness
  class_eval(DEFINITION)
end

class ApiKeyDefinesTest < Minitest::Test
  NAMES = %w[TMDB_READ_TOKEN TRAKT_CLIENT_ID TRAKT_CLIENT_SECRET].freeze

  def setup
    @saved = NAMES.to_h { |name| [name, ENV[name]] }
    NAMES.each { |name| ENV.delete(name) }
  end

  def teardown
    @saved.each { |name, value| ENV[name] = value }
  end

  def test_unset_or_blank_env_gives_no_define
    ENV["TRAKT_CLIENT_ID"] = "   "
    assert_equal "", Harness.new.api_key_defines
    ENV["TRAKT_CLIENT_ID"] = ""
    assert_equal "", Harness.new.api_key_defines
  end

  def test_set_env_gives_the_matching_define
    ENV["TRAKT_CLIENT_ID"] = "client123"
    assert_equal " --dart-define=TRAKT_CLIENT_ID=client123", Harness.new.api_key_defines
  end

  def test_value_is_shell_escaped
    ENV["TRAKT_CLIENT_ID"] = "a b;c"
    assert_equal " --dart-define=TRAKT_CLIENT_ID=a\\ b\\;c", Harness.new.api_key_defines
  end

  def test_secrets_and_tmdb_key_never_become_a_define
    ENV["TRAKT_CLIENT_SECRET"] = "secret"
    ENV["TMDB_READ_TOKEN"] = "eyJtest.token"
    assert_equal "", Harness.new.api_key_defines
  end
end
