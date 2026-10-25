# frozen_string_literal: true

require "test_helper"

class UpdateMailingListSubscriptionsMailerTest < ActionMailer::TestCase
  test "the body links to the person's page on this Clubhouse" do
    person = person(:active_ranger)
    mail = UpdateMailingListSubscriptionsMailer.notify(person:, user: person, old_email: "old@example.com",
                                                       additional_lists: nil, teams: [])

    hrefs = Nokogiri::HTML(mail.body.to_s).css("a").map { |a| a["href"] }
    assert_includes hrefs, "http://example.com/person/#{person.id}"
  end
end
