# frozen_string_literal: true

require "test_helper"

# The nightly twin of the Ticketing > SAP Candidates page. It renders
# SapCandidatesReport rows, so the rows are built here rather than queried.
class RangersWhoNeedSapsMailerTest < ActionMailer::TestCase
  YEAR = 2026

  setup do
    Setting.find_or_create_by(name: Setting::TAS_SAP_REPORT_EMAIL).update!(value: "ticketing@example.com")
    @person = person(:active_ranger)
  end

  test "notify lists a candidate holding a ticket" do
    ticket = AccessDocument.create!(person: @person, type: AccessDocument::SPT,
                                    status: AccessDocument::QUALIFIED, source_year: YEAR,
                                    delivery_method: AccessDocument::DELIVERY_NONE,
                                    expiry_date: "#{YEAR + 3}-09-15")
    signup = SapCandidatesReport::SignUp.new(begins: Time.local(YEAR, 8, 25, 9, 0, 0),
                                             position_title: "Dirt", description: "Graveyard")
    row = SapCandidatesReport::Row.new(person: @person, has_spt: true, tickets: [ticket],
                                       years: [YEAR - 1], schedule: [signup])

    mail = RangersWhoNeedSapsMailer.notify(rows: [row], start_year: YEAR - 3)

    assert_equal ["ticketing@example.com"], mail.to
    assert_match "Ranger SAP Candidates", mail.subject

    body = mail.body.to_s
    assert_includes body, @person.callsign
    assert_includes body, Rails.application.routes.url_helpers.person_url(@person, host: "example.com")
    assert_includes body, "RAD-#{ticket.id} SPT qualified"
    assert_includes body, "Years with shifts since #{YEAR - 3}"
    assert_includes body, (YEAR - 1).to_s
    assert_includes body, "Tue Aug 25 @ 09:00 Dirt Graveyard"
  end

  test "notify spells out a candidate with no ticket and no history" do
    row = SapCandidatesReport::Row.new(person: @person, has_spt: false, tickets: [],
                                       years: [], schedule: [])

    body = RangersWhoNeedSapsMailer.notify(rows: [row], start_year: YEAR - 3).body.to_s

    assert_includes body, "NO SPT"
    assert_includes body, "No years"
    assert_includes body, "No sign-ups"
  end

  test "notify says so when no one needs a sap" do
    body = RangersWhoNeedSapsMailer.notify(rows: [], start_year: YEAR - 3).body.to_s

    assert_includes body, "No Rangers found who may need SAPs."
  end
end
