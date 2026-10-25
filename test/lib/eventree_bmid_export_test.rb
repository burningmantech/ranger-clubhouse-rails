# frozen_string_literal: true

require "test_helper"

# The Eventree export batch job: CSV building from provision-derived values,
# the upstream note wording, materialization of synthesized badges, and the
# all-or-nothing transaction.
class EventreeBmidExportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @person = person(:active_ranger)

    Bmid.delete_all
    BmidExport.delete_all
    AccessDocument.delete_all
    Provision.delete_all
    Setting.where(name: [Setting::TAS_DEFAULT_SAP_DATE, Setting::TAS_SAP_DATE_RANGE]).delete_all
    Setting.create!(name: Setting::TAS_DEFAULT_SAP_DATE, value: "#{YEAR}-08-15")
    Setting.create!(name: Setting::TAS_SAP_DATE_RANGE, value: "10-25")
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  test "the CSV reads meals and showers from the live provisions, not the badge columns" do
    # The stale snapshot says everything; the live provisions say pre-event
    # meals only and no showers. The vendor gets the live values.
    Bmid.create!(person: @person, year: YEAR, status: Bmid::READY_TO_PRINT,
                 title1: "Shift Lead", meals: "all", showers: true)
    meal_for(@person, pre_event_meals: true)

    export = export_badges![:export]

    row = export.csv_file.download.split("\n").second
    assert_equal [@person.first_name, @person.last_name, @person.email, @person.callsign,
                  "Shift Lead", "Rangers 660", "", "", "No", "Yes", "No", "No", "", ""].join(","),
                 row
  end

  test "the CSV is stored under exports/ by a filename that carries the second" do
    export = export_badges![:export]

    assert_equal "ranger-bmids-#{YEAR}-04-08-12-00-00.csv", export.filename
    assert_equal "exports/#{export.filename}", export.csv_file.blob.key
  end

  test "the export note separates allocated from earned provisions in upstream wording" do
    meal_for(@person, is_allocated: true,
                      pre_event_meals: true, event_week_meals: true, post_event_meals: true)
    meal_for(@person, event_week_meals: true)
    provision_for(@person, is_allocated: true)

    export_badges!

    saved = Bmid.find_for_person_year(@person.id, YEAR)
    assert_match "Exported [meals all alloc, event earned] [showers alloc]", saved.notes
  end

  test "exporting a synthesized badge INSERTs it as submitted with the batch stamp" do
    assert_nil Bmid.find_for_person_year(@person.id, YEAR)

    result = export_badges!(batch_info: "Batch #2, stragglers")

    saved = Bmid.find_for_person_year(@person.id, YEAR)
    assert saved
    assert_equal Bmid::SUBMITTED, saved.status
    assert_equal "Batch #2, stragglers", saved.batch
    assert_equal [saved], result[:exported]
    assert_empty result[:rejected]
    assert_empty result[:missing_ids]
    assert_equal [@person.id], result[:export].person_ids
    assert_equal "Batch #2, stragglers", result[:export].batch_info
  end

  test "an unprintable badge comes back rejected and a vanished id comes back missing" do
    Bmid.create!(person: @person, year: YEAR, status: Bmid::SUBMITTED)
    ghost_id = Person.maximum(:id) + 1_000

    result = EventreeBmidExport.export!([@person.id, ghost_id],
                                        year: YEAR, batch_info: "", exporter: @person)

    assert_nil result[:export]
    assert_empty result[:exported]
    assert_equal [@person.id], result[:rejected].map(&:person_id)
    assert_equal [ghost_id], result[:missing_ids]
    assert_nil BmidExport.last, "nothing printable must write nothing"
  end

  test "a batch record that cannot save rolls back every badge and provision write" do
    meal = meal_for(@person, pre_event_meals: true)

    assert_raises(ActiveRecord::RecordInvalid) do
      export_badges!(exporter: nil)
    end

    assert_nil Bmid.find_for_person_year(@person.id, YEAR),
               "the materialized badge must roll back with the failed batch"
    assert_equal Provision::AVAILABLE, meal.reload.status
    assert_nil BmidExport.last
  end

  test "un-submitting returns the batch's badges and provisions and removes the record" do
    meal = meal_for(@person, pre_event_meals: true)
    export = export_badges![:export]

    result = EventreeBmidExport.unsubmit!(export, year: YEAR)

    badge = Bmid.find_for_person_year(@person.id, YEAR)
    assert_equal Bmid::IN_PREP, badge.status
    assert_nil badge.batch
    assert_match "Un-submitted from print export", badge.notes
    assert_equal Provision::AVAILABLE, meal.reload.status

    assert_equal [badge.id], result[:reverted].map(&:id)
    assert_empty result[:skipped]
    assert_empty result[:missing_ids]
    assert_equal [meal.id], result[:provisions_by_person][@person.id].map(&:id)
    assert_nil BmidExport.last
  end

  test "a badge now under another batch is left alone" do
    meal = meal_for(@person, pre_event_meals: true)
    export = export_badges![:export]
    Bmid.find_for_person_year(@person.id, YEAR).update_columns(batch: "Batch #9")

    result = EventreeBmidExport.unsubmit!(export, year: YEAR)

    assert_empty result[:reverted]
    assert_equal [@person.id], result[:skipped].map(&:person_id)
    assert_equal Bmid::SUBMITTED, Bmid.find_for_person_year(@person.id, YEAR).status
    assert_equal Provision::SUBMITTED, meal.reload.status
    assert_nil BmidExport.last, "the record is removed even when every badge is skipped"
  end

  test "a stamped provision the batch never touched is not returned" do
    meal = meal_for(@person, pre_event_meals: true)
    export = export_badges![:export]

    # A leftover from an older consumption: same stamp, same status, but
    # untouched by this batch's run. Only the time fence tells them apart.
    stale = meal_for(@person, status: Provision::SUBMITTED, event_week_meals: true,
                     comments: Provision::BMID_EXPORT_COMMENT)
    stale.update_columns(updated_at: 2.years.ago)

    EventreeBmidExport.unsubmit!(export, year: YEAR)

    assert_equal Provision::AVAILABLE, meal.reload.status
    assert_equal Provision::SUBMITTED, stale.reload.status
  end

  test "an exported person with no badge row left comes back missing" do
    export = export_badges![:export]
    Bmid.delete_all

    result = EventreeBmidExport.unsubmit!(export, year: YEAR)

    assert_empty result[:reverted]
    assert_empty result[:skipped]
    assert_equal [@person.id], result[:missing_ids]
    assert_nil BmidExport.last
  end

  private

  def export_badges!(batch_info: "Batch #1", exporter: @person)
    EventreeBmidExport.export!([@person.id], year: YEAR, batch_info: batch_info, exporter: exporter)
  end

  def provision_for(holder, type: Provision::WET_SPOT, status: Provision::AVAILABLE, **attributes)
    Provision.create!(person: holder, type:, status:, source_year: YEAR,
                      expires_on: Date.new(YEAR + 3, 9, 1), **attributes)
  end

  def meal_for(holder, **attributes)
    provision_for(holder, type: Provision::MEALS, **attributes)
  end
end
