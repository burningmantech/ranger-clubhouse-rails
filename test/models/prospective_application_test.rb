# frozen_string_literal: true

require "test_helper"

class ProspectiveApplicationTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset
    @application = prospective_application(:pending_qualified)
  end

  teardown do
    Current.reset
    travel_back
  end

  test "event qualification math excludes pandemic years and old events" do
    @application.events_attended = "2013;2014;2020;2021;2023"

    assert_equal [2013, 2014, 2020, 2021, 2023], @application.all_events
    assert_equal [2013, 2014, 2023], @application.non_pandemic_events
    assert @application.have_pandemic_years?
    # cutoff for qualified_events is 2026 - 11 = 2015
    assert_equal [2023], @application.qualified_events
    # cutoff for old_events is 2026 - 10 = 2016
    assert_equal [2013, 2014], @application.old_events
    assert @application.qualified_event_year?
    assert @application.brc_experience_okay?
    assert_nil @application.experience_issue
  end

  test "the last 10 events skip the years with no event" do
    # The ten events before 2026 reach back to 2014: 2020 and 2021 had none.
    @application.events_attended = "2014"
    assert @application.qualified_event_year?

    @application.events_attended = "2013"
    assert_not @application.qualified_event_year?
    assert_equal "No qualifying event within the last 10 events (not years)", @application.experience_issue
  end

  test "pandemic-only attendance does not qualify" do
    application = prospective_application(:pending_unqualified)

    assert_not application.brc_experience_okay?
    assert_equal "NO QUALIFIED EVENT YEARS LISTED", application.experience_issue
  end

  test "events_attended treats None as blank" do
    @application.events_attended = "None"
    assert_equal "", @application.events_attended
    assert_empty @application.all_events
  end

  test "handles setter strips carriage returns and blank lines" do
    @application.handles = "Alpha\r\n\r\n  \nBravo\r\n"
    assert_equal "Alpha\nBravo", @application.handles
    assert_equal ["Alpha", "Bravo"], @application.handle_list
  end

  test "handle_list_issues flags the word ranger and punctuation" do
    @application.handles = "Dusty Ranger\nWow!"
    issues = @application.handle_list_issues
    assert_equal 2, issues.size
  end

  test "record_rejections stacks newest first and clears handles" do
    Current.person = person(:auditor_ranger)
    @application.record_rejections("Too on the nose")

    assert_equal "", @application.handles
    assert_equal 1, @application.rejected_handles.size
    rejection = @application.rejected_handles.first
    assert_equal ["Dusty Dawn", "Sparkle Pony"], rejection["handles"]
    assert_equal "Too on the nose", rejection["message"]
    assert_equal person(:auditor_ranger).id, rejection["rejected_by_id"]

    @application.handles = "Third Try"
    @application.record_rejections(nil)
    assert_equal ["Third Try"], @application.rejected_handles.first["handles"]
    assert_equal ["Dusty Dawn", "Sparkle Pony"], @application.rejected_handles.second["handles"]
  end

  test "screen_handles detects existing people and reservations" do
    application = prospective_application(:handle_check)
    HandleReservation.create!(handle: "Moonbeam", reservation_type: HandleReservation::TYPE_RADIO_JARGON)

    application.screen_handles
    screened = application.screened_handles

    # "Test Ranger" normalizes to the active_ranger's callsign_normalized
    assert_equal person(:active_ranger).id, screened.first[:existing_person].id
    assert_not screened.first[:is_applicant]

    assert_equal "Moonbeam", screened.second[:handle]
    assert_nil screened.second[:existing_person]
    assert_equal 1, screened.second[:reserved_handles].size
  end

  test "screen_handles marks the applicant's own account" do
    application = prospective_application(:created_account)
    application.handles = "Test Ranger"
    application.screen_handles

    assert application.screened_handles.first[:is_applicant]
  end

  test "blank_personal_info lists missing fields with country-aware state" do
    application = prospective_application(:pending_unqualified)

    fields = application.blank_personal_info
    assert_includes fields, "Street Address"
    assert_includes fields, "State"
    assert_includes fields, "Telephone number"
    assert application.personal_info_issues?

    assert_empty @application.blank_personal_info
    assert_not @application.personal_info_issues?
  end

  test "updating stamps updated_by and review columns and records an audit entry" do
    Current.person = person(:auditor_ranger)

    assert_difference -> { @application.audit_logs.count }, 1 do
      @application.update!(why_volunteer_review: ProspectiveApplication::WHY_VOLUNTEER_REVIEW_OKAY)
    end

    assert_equal person(:auditor_ranger).id, @application.updated_by_person_id
    assert_not_nil @application.updated_by_person_at
    assert_equal person(:auditor_ranger).id, @application.review_person_id
    assert_not_nil @application.reviewed_at

    log = @application.audit_logs.order(:created_at).last
    assert_equal "updated", log.action
    assert_equal %w[unreviewed okay], log.data["why_volunteer_review"]
    assert_not log.data.key?("updated_by_person_id")
  end

  test "log meta resolves assigned person callsigns" do
    Current.person = person(:auditor_ranger)
    @application.update!(assigned_person_id: person(:active_ranger).id)

    log = @application.audit_logs.order(:created_at).last
    assert_equal [nil, "TestRanger"], log.meta[:assigned_person]
  end

  test "destroy removes notes and audit logs" do
    assert_equal 2, @application.notes.count
    assert @application.audit_logs.any?

    @application.destroy!

    assert_equal 0, ProspectiveApplicationNote.where(prospective_application_id: @application.id).count
    assert_equal 0, ProspectiveApplicationLog.where(prospective_application_id: @application.id).count
  end

  test "personal_info validation context requires the PII fields" do
    application = prospective_application(:pending_unqualified)
    application.assign_attributes(street: "", phone: "")

    assert application.valid?
    assert_not application.valid?(:personal_info)
    assert application.errors[:street].any?
    assert application.errors[:phone].any?
    assert application.errors[:state].any?
  end

  test "a personal-info save holds the email to Person's address rule" do
    @application.email = "name@gmailcom"
    assert_not @application.valid?(:personal_info)
    assert_equal [I18n.t("errors.messages.email_invalid", attribute: "Email")], @application.errors[:email]

    @application.email = "invalid-email"
    assert_not @application.valid?(:personal_info)
    assert_equal [I18n.t("errors.messages.email_invalid", attribute: "Email")], @application.errors[:email], "told once"
  end

  # Accepted: the VC corrects an imported address before anything else on
  # that form saves. Import itself saves without the context.
  test "a stored email no mail could reach holds up every personal-info save" do
    @application.update_columns(email: "name@gmailcom")
    @application.reload.city = "Elsewhere"

    assert_not @application.save(context: :personal_info)
    assert_equal [I18n.t("errors.messages.email_invalid", attribute: "Email")], @application.errors[:email]

    assert @application.save, @application.errors.full_messages.to_sentence
    assert_equal "Elsewhere", @application.reload.city
  end

  test "search_for_applications handles each query form" do
    assert_equal [@application], ProspectiveApplication.search_for_applications("A-#{@application.id}")
    assert_equal [@application], ProspectiveApplication.search_for_applications("R-1001")
    assert_equal [@application], ProspectiveApplication.search_for_applications("alice.applicant@example.com")
    assert_includes ProspectiveApplication.search_for_applications("Alice Applicant"), @application
  end

  test "find_by_application_id strips the A- prefix" do
    assert_equal @application, ProspectiveApplication.find_by_application_id!("A-#{@application.id}")
    assert_equal @application, ProspectiveApplication.find_by_application_id!(@application.id.to_s)
  end

  test "related_applications finds other records for the same bpguid" do
    other = @application.dup
    other.year = 2025
    other.save!

    assert_equal [other], @application.related_applications.to_a
  end

  test "status predicates and groupings" do
    assert @application.status_pending?
    assert_not @application.stop_status?

    @application.status = ProspectiveApplication::STATUS_REJECT_TOO_YOUNG
    assert @application.stop_status?

    @application.status = ProspectiveApplication::STATUS_MORE_HANDLES
    assert @application.held_status?
    assert @application.processing_callsign?

    @application.status = ProspectiveApplication::STATUS_REJECT_PRE_BONK
    assert @application.bonked?
  end
end
