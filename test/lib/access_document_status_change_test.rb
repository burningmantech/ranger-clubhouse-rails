# frozen_string_literal: true

require "test_helper"

# Exercises the money-path cascades in AccessDocumentStatusChange: claiming a
# ticket banks the person's other tickets and releases the mismatched vehicle
# pass, banking the last available ticket reverts a dangling claimed pass, and
# every illegal transition raises the domain error. Audit rows are expected on
# every change.
class AccessDocumentStatusChangeTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(Time.zone.now.year, 4, 8, 12, 0, 0)
    Current.reset
  end

  teardown do
    Current.reset
    travel_back
  end

  def change(document, status, person: person(:active_ranger))
    AccessDocumentStatusChange.new(person_id: person.id, document: document, status: status).call
  end

  # --- Claim Staff Credential ----------------------------------------------

  test "claiming a Staff Credential banks other tickets and releases the SP vehicle pass" do
    before = ActionLog.count

    change(access_document(:ar_staff_credential), AccessDocument::CLAIMED)

    assert_equal AccessDocument::CLAIMED, access_document(:ar_staff_credential).reload.status
    assert_equal AccessDocument::BANKED, access_document(:ar_spt).reload.status,
                 "the other regular ticket should be banked"
    assert_equal AccessDocument::QUALIFIED, access_document(:ar_vp_sp).reload.status,
                 "the SP vehicle pass should be released"
    assert_equal AccessDocument::CLAIMED, access_document(:ar_vp_gift).reload.status,
                 "the Gift vehicle pass should be untouched by a Staff Credential claim"

    assert_operator ActionLog.count, :>, before, "audit rows should be written"
    assert ActionLog.exists?(event: "access-document-update", target_person_id: person(:active_ranger).id)
  end

  # --- Claim SP ticket -----------------------------------------------------

  test "claiming an SP ticket banks the Staff Credential and releases the Gift vehicle pass" do
    change(access_document(:ar_spt), AccessDocument::CLAIMED)

    assert_equal AccessDocument::CLAIMED, access_document(:ar_spt).reload.status
    assert_equal AccessDocument::BANKED, access_document(:ar_staff_credential).reload.status
    assert_equal AccessDocument::QUALIFIED, access_document(:ar_vp_gift).reload.status,
                 "the Gift vehicle pass should be released"
    assert_equal AccessDocument::CLAIMED, access_document(:ar_vp_sp).reload.status,
                 "the SP vehicle pass should be untouched by an SP ticket claim"
  end

  # --- Anti-gaming: banking the last ticket reverts a claimed pass ---------

  test "banking the last available ticket reverts a claimed vehicle pass to qualified" do
    before = ActionLog.count

    change(access_document(:ig_staff_credential), AccessDocument::BANKED, person: person(:inactive_ranger))

    assert_equal AccessDocument::BANKED, access_document(:ig_staff_credential).reload.status
    assert_equal AccessDocument::QUALIFIED, access_document(:ig_vp_sp).reload.status,
                 "with no available ticket the claimed vehicle pass must revert"

    assert_operator ActionLog.count, :>, before, "audit rows should be written"
  end

  # --- Illegal transitions -------------------------------------------------

  test "banking a non-regular ticket raises InvalidTransition" do
    assert_raises(AccessDocumentStatusChange::InvalidTransition) do
      change(access_document(:ar_sap), AccessDocument::BANKED)
    end
  end

  test "qualifying a document that is not a SAP, vehicle pass, or gift raises InvalidTransition" do
    assert_raises(AccessDocumentStatusChange::InvalidTransition) do
      change(access_document(:ar_spt), AccessDocument::QUALIFIED)
    end
  end

  test "qualifying an allowed type that is not claimed raises InvalidTransition" do
    assert_raises(AccessDocumentStatusChange::InvalidTransition) do
      change(access_document(:ar_sap), AccessDocument::QUALIFIED)
    end
  end

  test "an unknown status action raises InvalidTransition" do
    assert_raises(AccessDocumentStatusChange::InvalidTransition) do
      change(access_document(:ar_staff_credential), "frobnicate")
    end
  end

  test "a document not owned by the person raises InvalidTransition" do
    assert_raises(AccessDocumentStatusChange::InvalidTransition) do
      # ig_staff_credential belongs to inactive_ranger, not active_ranger
      change(access_document(:ig_staff_credential), AccessDocument::CLAIMED)
    end
  end
end
