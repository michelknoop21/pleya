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
  NAMES = %w[TMDB_READ_TOKEN TRAKT_CLIENT_ID TRAKT_CLIENT_SECRET PRIVACY_POLICY_URL].freeze
  PRIVACY = " --dart-define=PRIVACY_POLICY_URL=https://pleya.app/privacy"
  PAGE = File.expand_path("../../website/src/routes/privacy/+page.svelte", __dir__)

  def setup
    @saved = NAMES.to_h { |name| [name, ENV[name]] }
    NAMES.each { |name| ENV.delete(name) }
  end

  def teardown
    @saved.each { |name, value| ENV[name] = value }
  end

  def test_blank_trakt_id_gives_no_trakt_define_but_keeps_the_privacy_default
    ENV["TRAKT_CLIENT_ID"] = "   "
    assert_equal PRIVACY, Harness.new.api_key_defines
    ENV["TRAKT_CLIENT_ID"] = ""
    assert_equal PRIVACY, Harness.new.api_key_defines
  end

  def test_unset_env_gives_only_the_privacy_default
    assert_equal PRIVACY, Harness.new.api_key_defines
  end

  def test_set_env_gives_the_matching_define
    ENV["TRAKT_CLIENT_ID"] = "client123"
    assert_equal " --dart-define=TRAKT_CLIENT_ID=client123#{PRIVACY}", Harness.new.api_key_defines
  end

  def test_value_is_shell_escaped
    ENV["TRAKT_CLIENT_ID"] = "a b;c"
    assert_equal " --dart-define=TRAKT_CLIENT_ID=a\\ b\\;c#{PRIVACY}", Harness.new.api_key_defines
  end

  def test_privacy_url_can_be_overridden_and_blank_falls_back
    ENV["PRIVACY_POLICY_URL"] = "https://example.test/privacy"
    assert_equal " --dart-define=PRIVACY_POLICY_URL=https://example.test/privacy", Harness.new.api_key_defines
    ENV["PRIVACY_POLICY_URL"] = "  "
    assert_equal PRIVACY, Harness.new.api_key_defines
  end

  def test_secrets_and_tmdb_key_never_become_a_define
    ENV["TRAKT_CLIENT_SECRET"] = "secret"
    ENV["TMDB_READ_TOKEN"] = "eyJtest.token"
    assert_equal PRIVACY, Harness.new.api_key_defines
  end

  # The build may carry a Trakt client id only if the published page names Trakt,
  # and the default privacy link must be the page's own address.
  def test_privacy_page_names_trakt_and_matches_the_default_url
    page = File.read(PAGE)
    assert_includes page, "<h3>Trakt (optional)</h3>"
    assert_includes page, "https://trakt.tv/privacy"
    assert_includes page, "Trakt, if you connect your Trakt account and allow Pleya to send your watching"
    assert_includes page, 'href="https://pleya.app/privacy"'
    assert_includes Harness.new.api_key_defines, "https://pleya.app/privacy"
  end
end
