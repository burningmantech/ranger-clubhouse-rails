# frozen_string_literal: true

require "test_helper"

class WelcomeMailerTest < ActionMailer::TestCase
  setup do
    @person = person(:prospective_ranger)
    @token = "00a1Tok3nXyz"
  end

  def welcome_body
    WelcomeMailer.notify(person: @person, invite_token: @token).body.to_s
  end

  # Signing in has no /login here: the link opens Set New Password, worded as a
  # welcome, on the host config.action_mailer.default_url_options names.
  test "the sign-in link opens the reset page as a welcome, on this Clubhouse" do
    expected = "http://example.com/reset-token?token=#{@token}&welcome=1"
    html = welcome_body

    assert_includes html, "http://example.com/reset-token?token=#{@token}&amp;welcome=1"
    assert_not_includes html, "/login?token="
    hrefs = Nokogiri::HTML(html).css("a[href*='reset-token']").map { |a| a["href"] }
    assert_equal [expected, expected], hrefs, "the button and the address to paste"
  end

  test "the header logo is spelled out on the same host, with one slash before the path" do
    src = Nokogiri::HTML(welcome_body).at_css("img")["src"]

    assert_equal "http://example.com#{ActionController::Base.helpers.asset_path("ranger-logo.png")}", src
    assert_not_includes src, "//assets"
  end

  test "the address to bookmark is this Clubhouse's" do
    assert_includes welcome_body, %(<a href="http://example.com/">http://example.com/</a>)
  end
end
