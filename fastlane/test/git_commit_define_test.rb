# Regressie op fastlane/Fastfile#git_commit_define (review L29).
# Draaien: ruby fastlane/test/git_commit_define_test.rb
require "minitest/autorun"

FASTFILE = File.expand_path("../Fastfile", __dir__)
DEFINITION = File.read(FASTFILE)[/^def git_commit_define\n.*?^end\n/m]
raise "git_commit_define niet gevonden in #{FASTFILE}" unless DEFINITION

class Harness
  PROJECT_ROOT = "/repo/root".freeze

  module UI
    Error = Class.new(StandardError)
    def self.user_error!(message)
      raise Error, message
    end
  end

  attr_reader :calls

  def initialize(&result)
    @result = result
    @calls = []
  end

  def sh(*command, **_options)
    @calls << command
    @result.call
  end

  class_eval(DEFINITION)
end

class GitCommitDefineTest < Minitest::Test
  def test_short_sha_becomes_a_dart_define
    harness = Harness.new { "abc1234\n" }
    assert_equal " --dart-define=GIT_COMMIT=abc1234", harness.git_commit_define
    assert_equal [["git", "-C", "/repo/root", "rev-parse", "--short", "HEAD"]], harness.calls
  end

  def test_a_failing_git_call_stops_the_lane
    harness = Harness.new { raise "Exit status of command 'git ...' was 128" }
    assert_raises(RuntimeError) { harness.git_commit_define }
  end

  def test_empty_output_is_a_user_error
    harness = Harness.new { "\n" }
    error = assert_raises(Harness::UI::Error) { harness.git_commit_define }
    assert_match(/geen sha/, error.message)
  end
end
