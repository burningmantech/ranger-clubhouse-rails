# frozen_string_literal: true

require "test_helper"

class BmidTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Current.reset
  end

  teardown do
    Current.reset
    travel_back
  end

  # --- meals_enum_value: maps a provision package's meals to the bmid enum ----

  def meals(pre: false, event: false, post: false)
    Provision::Package::Meals.new(pre:, event:, post:)
  end

  test "meals_enum_value returns nil when no periods are set" do
    assert_nil Bmid.meals_enum_value(meals)
  end

  test "meals_enum_value collapses all three periods to 'all'" do
    assert_equal "all", Bmid.meals_enum_value(meals(pre: true, event: true, post: true))
  end

  test "meals_enum_value joins two periods in pre/event/post order" do
    assert_equal "pre+event", Bmid.meals_enum_value(meals(pre: true, event: true))
    assert_equal "event+post", Bmid.meals_enum_value(meals(event: true, post: true))
    assert_equal "pre+post", Bmid.meals_enum_value(meals(pre: true, post: true))
  end

  test "meals_enum_value returns the single period" do
    assert_equal "event", Bmid.meals_enum_value(meals(event: true))
  end

  # --- not_qualified_to_print?: echelon vs everyone else ---------------------

  test "non-echelon needs a ticket or training sign-up" do
    bmid = Bmid.new(person: Person.new(status: Person::ACTIVE))
    bmid.has_ticket = false
    bmid.training_signed_up = false
    assert bmid.not_qualified_to_print?

    bmid.has_ticket = true
    refute bmid.not_qualified_to_print?
  end

  test "echelon only needs a shift sign-up" do
    bmid = Bmid.new(person: Person.new(status: Person::ECHELON))
    bmid.has_ticket = true # ignored for echelon
    bmid.has_signups = false
    assert bmid.not_qualified_to_print?

    bmid.has_signups = true
    refute bmid.not_qualified_to_print?
  end

  # --- admission_date: mirrors the SAP access-date virtual -------------------

  test "admission_date round-trips 'any time'" do
    bmid = Bmid.new
    bmid.admission_date = AccessDocument::ADMISSION_ANY
    assert bmid.access_any_time
    assert_nil bmid.access_date
    assert_equal AccessDocument::ADMISSION_ANY, bmid.admission_date
  end

  test "admission_date round-trips a specific date" do
    bmid = Bmid.new
    bmid.admission_date = "2026-08-20"
    refute bmid.access_any_time
    assert_equal "2026-08-20", bmid.admission_date
  end

  test "blank admission_date clears the access date" do
    bmid = Bmid.new
    bmid.admission_date = ""
    refute bmid.access_any_time
    assert_nil bmid.access_date
    assert_nil bmid.admission_date
  end

  # update_saps_for_person saves with validate: false, so a value the database
  # cannot cast reaches the person's real access documents as NULL and erases
  # an arrival date no one touched. The badge refuses it instead.
  test "an unparseable admission_date is refused and changes nothing" do
    holder = person(:active_ranger)
    bmid = Bmid.new(person: holder, year: YEAR, status: Bmid::IN_PREP)
    bmid.access_date = Time.zone.local(YEAR, 8, 20, 12, 0, 0)

    bmid.admission_date = "not-a-date"

    refute bmid.valid?
    assert_equal ["The SAP date must be a date, \"any\", or left unspecified."], bmid.errors[:admission_date]
    assert_equal Date.new(YEAR, 8, 20), bmid.access_date.to_date,
                 "a value the badge will not accept must not overwrite the loaded one"
  end

  test "a date that is not ISO 8601 is refused" do
    bmid = Bmid.new(person: person(:active_ranger), year: YEAR, status: Bmid::IN_PREP)

    bmid.admission_date = "8/20/2026"

    refute bmid.valid?
  end

  test "an accepted admission_date clears an earlier refusal" do
    bmid = Bmid.new(person: person(:active_ranger), year: YEAR, status: Bmid::IN_PREP)

    bmid.admission_date = "not-a-date"
    bmid.admission_date = "#{YEAR}-08-20"

    assert bmid.valid?
    assert_equal "#{YEAR}-08-20", bmid.admission_date
  end

  # --- update_sap: the write-back only fires on a real change ----------------

  def access_document(holder, type:, status:, **attributes)
    AccessDocument.create!(person: holder, type:, status:, source_year: YEAR,
                           delivery_method: AccessDocument::DELIVERY_NONE, **attributes)
  end

  # after_save :update_sap runs on every save, so any edit at all -- a title, a
  # note -- would push the date the badge happens to be holding out over every
  # other changeable pass the person owns.
  test "a save that never touched the access date writes nothing back" do
    holder = person(:active_ranger)
    claimed = access_document(holder, type: AccessDocument::SAP,
                                      status: AccessDocument::CLAIMED,
                                      access_date: Time.zone.local(YEAR, 8, 20, 12, 0, 0))
    banked = access_document(holder, type: AccessDocument::STAFF_CREDENTIAL,
                                     status: AccessDocument::BANKED)

    bmid = Bmid.find_for_person_manage(holder.id, YEAR)
    bmid.title1 = "Shift Lead"

    assert bmid.save
    assert_nil banked.reload.access_date,
               "a banked pass no one edited must keep its own access date"
    assert_equal Date.new(YEAR, 8, 20), claimed.reload.access_date.to_date
  end

  test "changing the access date still writes back to every changeable document" do
    holder = person(:active_ranger)
    claimed = access_document(holder, type: AccessDocument::SAP,
                                      status: AccessDocument::CLAIMED,
                                      access_date: Time.zone.local(YEAR, 8, 20, 12, 0, 0))
    banked = access_document(holder, type: AccessDocument::STAFF_CREDENTIAL,
                                     status: AccessDocument::BANKED)

    bmid = Bmid.find_for_person_manage(holder.id, YEAR)
    bmid.admission_date = "#{YEAR}-08-12"

    assert bmid.save
    assert_equal Date.new(YEAR, 8, 12), claimed.reload.access_date.to_date
    assert_equal Date.new(YEAR, 8, 12), banked.reload.access_date.to_date
  end

  # --- find_for_person_ids: the badge list, real rows and stand-ins ----------

  test "someone without a badge gets an unsaved in-prep one" do
    holder = person(:active_ranger)

    rows = Bmid.find_for_person_ids(YEAR, [holder.id])

    assert_equal 1, rows.size
    synthesized = rows.first
    assert_nil synthesized.id, "a stand-in badge has never been saved"
    assert_equal Bmid::IN_PREP, synthesized.status
    assert_equal YEAR, synthesized.year
    assert_equal holder.id, synthesized.person_id
  end

  test "excluding departed people drops them instead of re-synthesizing a blank badge" do
    departed = person(:deceased_ranger)
    Bmid.create!(person: departed, year: YEAR, status: Bmid::IN_PREP, title1: "Shift Lead")
    live = person(:active_ranger)

    rows = Bmid.find_for_person_ids(YEAR, [departed.id, live.id], true)

    assert_equal [live.id], rows.map(&:person_id),
                 "a departed person must not come back as a synthesized badge"
  end

  test "the badges' own year drives the flags loaded onto them" do
    holder = person(:active_ranger)
    slot = Slot.create!(position: positions(:ood_position),
                        begins: Time.zone.local(YEAR - 1, 6, 1, 9, 0, 0),
                        ends: Time.zone.local(YEAR - 1, 6, 1, 17, 0, 0),
                        max: 10,
                        active: true)
    PersonSlot.create!(person: holder, slot:)

    assert Bmid.find_for_person_ids(YEAR - 1, [holder.id]).first.has_signups
    refute Bmid.find_for_person_ids(YEAR, [holder.id]).first.has_signups,
           "last year's sign-up is not this year's"
  end
end
