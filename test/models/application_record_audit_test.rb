# frozen_string_literal: true

require "test_helper"

class ApplicationRecordAuditTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 8, 15, 0, 0)
    Current.reset
    Current.person = person(:auditor_ranger)
    ActionLog.delete_all
  end

  teardown do
    Current.reset
    travel_back
  end

  test "unaudited models do not write action logs" do
    assert_no_difference("ActionLog.count") do
      PersonStatus.record(
        person(:active_ranger).id,
        Person::ACTIVE,
        Person::RETIRED,
        "manual transition",
        Current.person_id
      )
    end
  end

  test "access document writes action logs for create update and destroy" do
    document = nil

    assert_difference("ActionLog.count", 1) do
      document = AccessDocument.create!(
        person: person(:active_ranger),
        type: AccessDocument::SPT,
        status: AccessDocument::QUALIFIED,
        source_year: Current.year,
        delivery_method: AccessDocument::DELIVERY_NONE
      )
    end

    create_log = ActionLog.order(:id).last
    assert_equal "access-document-create", create_log.event
    assert_equal Current.person_id, create_log.person_id
    assert_equal person(:active_ranger).id, create_log.target_person_id
    assert_equal document.id, create_log.data["id"]
    assert_equal AccessDocument::SPT, create_log.data["type"]
    assert_instance_of String, create_log.data["created_at"]

    ActionLog.delete_all

    assert_difference("ActionLog.count", 1) do
      document.audit_reason = "bank document"
      document.update!(status: AccessDocument::BANKED)
    end

    update_log = ActionLog.order(:id).last
    assert_equal "access-document-update", update_log.event
    assert_equal "bank document", update_log.message
    assert_equal document.id, update_log.data["id"]
    assert_equal [AccessDocument::QUALIFIED, AccessDocument::BANKED], update_log.data["status"]

    ActionLog.delete_all

    assert_difference("ActionLog.count", 1) do
      document.audit_reason = "remove document"
      document.destroy!
    end

    destroy_log = ActionLog.order(:id).last
    assert_equal "access-document-delete", destroy_log.event
    assert_equal "remove document", destroy_log.message
    assert_equal document.id, destroy_log.data["id"]
    assert_equal AccessDocument::BANKED, destroy_log.data["status"]
  end

  test "person writes action logs for create update and destroy" do
    created_person = nil

    with_stubbed_person_side_effects do
      assert_difference("ActionLog.count", 1) do
        created_person = build_person_for_audit_test
        created_person.save!
      end
    end

    create_log = ActionLog.order(:id).last
    assert_equal "person-create", create_log.event
    assert_equal Current.person_id, create_log.person_id
    assert_equal created_person.id, create_log.target_person_id
    assert_equal created_person.id, create_log.data["id"]
    assert_equal created_person.email, create_log.data["email"]
    assert_instance_of String, create_log.data["created_at"]

    ActionLog.delete_all

    previous_camp_location = created_person.camp_location

    assert_difference("ActionLog.count", 1) do
      created_person.audit_reason = "update camp"
      created_person.update!(camp_location: "Camp Audit Trail")
    end

    update_log = ActionLog.order(:id).last
    assert_equal "person-update", update_log.event
    assert_equal "update camp", update_log.message
    assert_equal created_person.id, update_log.target_person_id
    assert_equal created_person.id, update_log.data["id"]
    assert_equal [previous_camp_location, "Camp Audit Trail"], update_log.data["camp_location"]

    ActionLog.delete_all

    assert_difference("ActionLog.count", 1) do
      created_person.audit_reason = "delete account"
      created_person.destroy!
    end

    destroy_log = ActionLog.order(:id).last
    assert_equal "person-delete", destroy_log.event
    assert_equal "delete account", destroy_log.message
    assert_equal created_person.id, destroy_log.target_person_id
    assert_equal created_person.email, destroy_log.data["email"]
  end

  test "person slot destroy is audited while delete_all bypasses shared callbacks" do
    slot = Slot.create!(
      position: positions(:training_lead),
      begins: Time.zone.local(2026, 4, 10, 9, 0, 0),
      ends: Time.zone.local(2026, 4, 10, 11, 0, 0),
      max: 10,
      active: true
    )

    person_slot = nil

    assert_difference("ActionLog.count", 1) do
      person_slot = PersonSlot.create!(person: person(:active_ranger), slot: slot)
    end

    create_log = ActionLog.order(:id).last
    assert_equal "person-slot-create", create_log.event
    assert_equal person(:active_ranger).id, create_log.target_person_id
    assert_equal person_slot.id, create_log.data["id"]

    ActionLog.delete_all

    assert_difference("ActionLog.count", 1) do
      person_slot.audit_reason = "manual signup removal"
      person_slot.destroy!
    end

    destroy_log = ActionLog.order(:id).last
    assert_equal "person-slot-delete", destroy_log.event
    assert_equal "manual signup removal", destroy_log.message
    assert_equal person(:active_ranger).id, destroy_log.target_person_id
    assert_equal slot.id, destroy_log.data["slot_id"]

    person_slot = PersonSlot.create!(person: person(:active_ranger), slot: slot)
    ActionLog.delete_all

    assert_no_difference("ActionLog.count") do
      PersonSlot.where(id: person_slot.id).delete_all
    end
  end

  private

  def build_person_for_audit_test
    person = person(:active_ranger).dup
    person.callsign = "Audit Person #{SecureRandom.hex(3)}"
    person.email = "audit-person-#{SecureRandom.hex(3)}@example.com"
    person.password = "temporary-password"
    person
  end

  def with_stubbed_person_side_effects
    original_change = PersonStatusManagement.method(:change)
    original_email_history = EmailHistory.method(:record)
    PersonStatusManagement.define_singleton_method(:change) { |**| nil }
    EmailHistory.define_singleton_method(:record) { |*| nil }
    yield
  ensure
    PersonStatusManagement.define_singleton_method(:change, original_change)
    EmailHistory.define_singleton_method(:record, original_email_history)
  end
end
