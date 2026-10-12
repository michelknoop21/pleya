# Regressie op de privacypagina en het adres waar de app naar linkt.
# Draaien: ruby fastlane/test/privacy_page_test.rb
require "minitest/autorun"

PAGE = File.expand_path("../../website/src/routes/privacy/+page.svelte", __dir__)
ABOUT = File.expand_path("../../lib/screens/settings/about_screen.dart", __dir__)

class PrivacyPageTest < Minitest::Test
  # Een build met TRAKT_CLIENT_ID toont de Trakt-login: de gepubliceerde pagina
  # moet Trakt dan benoemen (docs/release-baseline.md, "Trakt login release conditions").
  def test_page_names_trakt_and_its_sharing
    page = File.read(PAGE)
    assert_includes page, "<h3>Trakt (optional)</h3>"
    assert_includes page, "https://trakt.tv/privacy"
    assert_includes page, "Trakt, if you connect your Trakt account and allow Pleya to send your watching"
  end

  # De link in Over (about_screen.dart) en de canonical van de pagina zijn één adres.
  def test_the_about_link_is_the_page_address
    default = File.read(ABOUT)[/'PRIVACY_POLICY_URL',\s*defaultValue: '([^']+)'/, 1]
    assert_equal "https://pleya.app/privacy", default
    assert_includes File.read(PAGE), %(<link rel="canonical" href="#{default}" />)
  end
end
