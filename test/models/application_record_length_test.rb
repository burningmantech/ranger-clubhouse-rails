# frozen_string_literal: true

require "test_helper"

# ApplicationRecord#values_fit_their_columns: a value longer than its column is
# refused with a message beside the field, rather than written for MariaDB to
# raise ActiveRecord::ValueTooLong.
class ApplicationRecordLengthTest < ActiveSupport::TestCase
  test "a varchar holds as many characters as it is declared with, however many bytes they take" do
    vehicle = vehicle(:approved_owner_vehicle)

    vehicle.vehicle_make = "é" * 191
    assert_empty errors_on(vehicle, :vehicle_make)

    vehicle.vehicle_make = "é" * 192
    assert_equal ["Vehicle make is too long (maximum is 191 characters)."], errors_on(vehicle, :vehicle_make)
  end

  test "a text column holds as many bytes as it is declared with" do
    vehicle = vehicle(:approved_owner_vehicle)

    vehicle.notes = "x" * 65_535
    assert_empty errors_on(vehicle, :notes)

    # A quarter as many characters, at four bytes each: one byte too many.
    vehicle.notes = "😀" * 16_384
    assert_equal ["Notes is too long to save. Shorten it and try again."], errors_on(vehicle, :notes)
  end

  # Person's identical errors collapse by themselves (ActiveRecord's errors.uniq!
  # after validation, on any model with a has_many), so this takes a rule below
  # its column, whose message differs.
  test "a column with a maximum of its own gets only that rule's message" do
    person = person(:active_ranger)
    person.callsign_pronounce = "x" * 201

    assert_equal ["Pronunciation is too long (maximum is 20 characters)."], errors_on(person, :callsign_pronounce)
  end

  # A rule that lets a blank value through never measured it, so the column does.
  test "a blank value longer than its column is refused where the model's own rule allows blank" do
    group = SurveyGroup.new(type: SurveyGroup::TYPE_NORMAL, report_title: "\u00A0" * 192)

    assert_equal ["Report title is too long (maximum is 191 characters)."], errors_on(group, :report_title)
  end

  # MariaDB trims spaces past the end of a column with only a note.
  test "spaces past the end of a varchar do not count" do
    vehicle = vehicle(:approved_owner_vehicle)
    vehicle.vehicle_make = "#{"x" * 191}   "

    assert_empty errors_on(vehicle, :vehicle_make)
  end

  # Without the cut, the audit row's refusal would turn the asset's save into a
  # quiet false (ApplicationRecord.truncates_to_column).
  test "an audited save from a browser with a long user agent still saves" do
    Current.user_agent = "x" * 300
    asset = asset(:radio_current_year)

    assert asset.update(description: "Spare radio")
    assert_equal 191, ActionLog.where(event: "asset-update").last.user_agent.length
  end

  # Puma hands request headers over as binary, where String#first counts bytes:
  # a cut there could end on half a character, which MariaDB refuses.
  test "a header cut to its column keeps whole characters" do
    log = ActionLog.new(user_agent: "#{"a" * 190}é".b, ip: "fe80::1%#{"x" * 300}")

    assert_equal "#{"a" * 190}é", log.user_agent
    assert_equal 191, log.ip.length

    log.user_agent = "#{"a" * 190}#{"é" * 5}".b
    assert_predicate log.user_agent, :valid_encoding?
    assert_equal "#{"a" * 190}é", log.user_agent
  end

  # ActiveRecord's save would answer false, with nothing to show, for a row a
  # callback writes and the column check refuses; the record being saved
  # carries the complaint instead (ApplicationRecord#create_or_update).
  test "a refused row written by a callback is reported on the record being saved" do
    application = prospective_application(:approved_ready)
    application.update_columns(why_volunteer: "a" * 30_000)

    # The change log holds the old and new answer, about 70,000 bytes, in a
    # 65,535-byte column.
    assert_not application.update(why_volunteer: "b" * 40_000)
    assert_equal ["This change is too large to record. Shorten the longest answers and try again."],
                 application.errors[:base]

    assert_equal "a" * 30_000, application.reload.why_volunteer

    # save! raises it as the record's own invalidity, as a refusal of its own would.
    error = assert_raises(ActiveRecord::RecordInvalid) { application.update!(why_volunteer: "b" * 40_000) }
    assert_same application, error.record
  end

  # A rule above its column promises more than the column holds: its message
  # names a number the column refuses, and the form's maxlength, taken from the
  # rule, lets the reader type past it. A text column counts bytes, and utf8mb4
  # spends up to four on a character, so a character maximum there has a
  # quarter of the column to fill.
  test "no length rule allows more than its column holds" do
    Rails.application.eager_load!

    too_generous = ApplicationRecord.descendants.flat_map do |model|
      next [] if model.abstract_class? || !model.table_exists?

      model.validators.grep(ActiveModel::Validations::LengthValidator).flat_map do |rule|
        maximum = rule.options[:maximum] || rule.options[:is]
        rule.attributes.filter_map do |attribute|
          column = model.columns_hash[attribute.to_s]
          next unless maximum.is_a?(Integer) && column&.limit && column.type.in?(%i[string text])

          room = column.type == :string ? column.limit : column.limit / 4
          "#{model.name}.#{attribute} allows #{maximum}, its column holds #{room}" if maximum > room
        end
      end
    end

    assert_empty too_generous.uniq
  end

  private

  def errors_on(record, attribute)
    record.validate
    record.errors.messages_for(attribute)
  end
end
