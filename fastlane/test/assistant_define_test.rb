# Run: ruby fastlane/test/assistant_define_test.rb
require "minitest/autorun"

FASTFILE = File.expand_path("../Fastfile", __dir__)
DEFINITION = File.read(FASTFILE)[/^def assistant_define\n.*?^end\n/m]
raise "assistant_define missing" unless DEFINITION

class Harness
  class_eval(DEFINITION)
end

class AssistantDefineTest < Minitest::Test
  def setup
    @saved = ENV["PLEYA_ASSISTANT_ENABLED"]
    ENV.delete("PLEYA_ASSISTANT_ENABLED")
  end

  def teardown
    ENV["PLEYA_ASSISTANT_ENABLED"] = @saved
  end

  def test_ios_beta_enables_big_p_without_an_environment_override
    assert_equal " --dart-define=PLEYA_ASSISTANT_ENABLED=true", Harness.new.assistant_define
  end

  def test_explicit_enable_is_retained
    ENV["PLEYA_ASSISTANT_ENABLED"] = "true"
    assert_equal " --dart-define=PLEYA_ASSISTANT_ENABLED=true", Harness.new.assistant_define
  end

  def test_explicit_rollout_stop_is_retained
    ENV["PLEYA_ASSISTANT_ENABLED"] = "false"
    assert_equal "", Harness.new.assistant_define
  end

  def test_ios_beta_passes_the_define_to_config_only
    lane = File.read(FASTFILE)[/lane :ios_beta do\n.*?^end\n/m]
    assert_includes lane, 'flutter build ios --config-only --release#{git_commit_define}#{assistant_define}#{api_key_defines}'
  end
end
