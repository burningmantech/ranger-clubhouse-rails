# frozen_string_literal: true

require "test_helper"

class AgreementsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)

    @person = person(:active_ranger)
    @admin = person(:auditor_ranger)
    # admin_set_signature stamps Current.person on its audit row, so the acting
    # administrator has to be set for the whole of this case.
    Current.person = @admin
    @year = Current.year

    PersonEvent.where(person_id: @person.id).delete_all
    @person.update_columns(behavioral_agreement: false)

    Agreements::DOCUMENTS.each_key do |tag|
      Document.create!(tag:, description: tag.titleize, body: "Body",
                       person_create_id: @admin.id, person_update_id: @admin.id)
    end
  end

  teardown do
    Current.reset
    travel_back
  end

  test "retrieve hides invisible documents by default" do
    tags = Agreements.retrieve(@person).map(&:tag)

    assert_not_includes tags, Document::SANDMAN_AFFIDAVIT_TAG
    assert_includes tags, Document::BEHAVIORAL_STANDARDS_AGREEMENT_TAG
  end

  test "retrieve include_hidden returns invisible documents flagged not visible" do
    agreements = Agreements.retrieve(@person, include_hidden: true)

    assert_equal Agreements::DOCUMENTS.size, agreements.size
    sandman = agreements.find { |a| a.tag == Document::SANDMAN_AFFIDAVIT_TAG }
    assert_not sandman.visible
    behavioral = agreements.find { |a| a.tag == Document::BEHAVIORAL_STANDARDS_AGREEMENT_TAG }
    assert behavioral.visible
    assert_equal Agreements::TERM_LIFETIME, behavioral.term
  end

  test "retrieve lists the Department NDA only for a raw Event Management holder" do
    assert_not_includes Agreements.retrieve(@person).map(&:tag), Document::DEPT_NDA_TAG

    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@person, Role::EVENT_MANAGEMENT)

    # Person memoizes its RoleManager, so the grant is only seen by a fresh instance.
    assert_includes Agreements.retrieve(Person.find(@person.id)).map(&:tag), Document::DEPT_NDA_TAG
  end

  test "retrieve reads annual flags for the requested year" do
    past = @year - 1
    pe = PersonEvent.first_or_new_for_person_year(@person.id, past)
    pe.signed_motorpool_agreement = true
    pe.save!(validate: false)

    find = ->(list) { list.find { |a| a.tag == Document::MOTORPOOL_POLICY_TAG } }

    assert find.call(Agreements.retrieve(@person, year: past, include_hidden: true)).signed
    assert_not find.call(Agreements.retrieve(@person, include_hidden: true)).signed
  end

  test "admin_set_signature sets and clears a lifetime flag with an audit log" do
    assert_difference -> { ActionLog.where(event: "agreement-signature", target_person_id: @person.id).count } do
      Agreements.admin_set_signature(@person, Document::BEHAVIORAL_STANDARDS_AGREEMENT_TAG, true)
    end
    assert @person.reload.behavioral_agreement

    Agreements.admin_set_signature(@person, Document::BEHAVIORAL_STANDARDS_AGREEMENT_TAG, false)
    assert_not @person.reload.behavioral_agreement
  end

  test "admin_set_signature sets an annual flag on the current year person event" do
    Agreements.admin_set_signature(@person, Document::MOTORPOOL_POLICY_TAG, true)

    assert PersonEvent.first_or_new_for_person_year(@person.id, @year).signed_motorpool_agreement
  end

  test "admin_set_signature is a no-op when the flag is unchanged" do
    assert_no_difference -> { ActionLog.where(event: "agreement-signature").count } do
      Agreements.admin_set_signature(@person, Document::MOTORPOOL_POLICY_TAG, false)
    end
  end

  test "admin_set_signature raises for an unknown tag" do
    assert_raises(ActiveRecord::RecordNotFound) do
      Agreements.admin_set_signature(@person, "no-such-agreement", true)
    end
  end
end
