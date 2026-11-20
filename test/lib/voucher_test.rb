# frozen_string_literal: true

require "test_helper"

class VoucherTest < ActiveSupport::TestCase
  setup do
    @person = person(:active_ranger)
    @person.update_columns(uuid: SecureRandom.uuid_v7)
  end

  test "every status has a rule, and each rule names a known state" do
    assert_equal Person::ALL_STATUSES.sort, Voucher::STATES.keys.sort
    assert_empty Voucher::STATES.values.uniq - Voucher::SHOWS.keys
  end

  test "an unknown id and a blank id find nothing" do
    assert_nil Voucher.find(SecureRandom.uuid_v7)
    assert_nil Voucher.find(nil)
  end

  test "a blank id never matches the people who have no uuid" do
    assert Person.where(uuid: nil).exists?, "fixtures are loaded without a uuid"
    assert_nil Voucher.find("")
  end

  test "what each state shows" do
    { Person::ACTIVE => %i[photo callsign status years positions],
      Person::PROSPECTIVE => %i[photo callsign status],
      Person::ECHELON => %i[photo callsign],
      Person::BONKED => %i[photo],
      Person::DISMISSED => %i[photo],
      Person::SUSPENDED => [] }.each do |status, parts|
      @person.update_columns(status:)
      voucher = Voucher.find(@person.uuid)

      assert_equal parts, %i[photo callsign status years positions].select { |part| voucher.shows?(part) }, status
    end
  end

  test "positions sums finished shifts by title, without Alpha or training positions" do
    ood = positions(:ood_position)
    training = positions(:training_lead)
    training.update_columns(type: Position::TYPE_TRAINING)
    alpha = Position.find_by(id: Position::ALPHA) ||
            Position.new(title: "Alpha").tap { |position| position.id = Position::ALPHA; position.save!(validate: false) }

    start = Time.zone.local(2024, 8, 26, 9)
    [training, alpha].each do |position|
      Timesheet.new(person: @person, position:, on_duty: start, off_duty: start + 2.hours).save!(validate: false)
    end
    ood_seconds = Timesheet.where(person: @person, position: ood).where.not(off_duty: nil).sum(&:duration)
    # Still on duty: no length yet.
    Timesheet.new(person: @person, position: ood, on_duty: start + 1.day).save!(validate: false)
    # Signed out before it was signed in: counts as nothing, not as a debit.
    Timesheet.new(person: @person, position: ood, on_duty: start + 2.days, off_duty: start + 2.days - 3.hours)
             .save!(validate: false)

    totals = Voucher.find(@person.uuid).positions

    assert_operator ood_seconds, :>, 0
    assert_equal ood_seconds, totals[ood.title]
    assert_not_includes totals.keys, training.title
    assert_not_includes totals.keys, "Alpha"
    assert_equal totals.keys.sort, totals.keys
  end

  test "ensure_uuid! gives a uuid to a row without one, once" do
    bare = person(:retired_ranger)
    assert_nil bare.uuid

    uuid = bare.ensure_uuid!

    assert_equal uuid, bare.reload.uuid
    assert_equal uuid, bare.ensure_uuid!
    assert_not bare.changed?
  end

  test "ensure_uuid! keeps the uuid another request wrote first" do
    stale = person(:retired_ranger)
    Person.where(id: stale.id).update_all(uuid: "11111111-1111-7111-8111-111111111111")

    assert_equal "11111111-1111-7111-8111-111111111111", stale.ensure_uuid!
    assert_not stale.changed?
  end

  test "a new person is given a uuid" do
    assert_match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/, Person.new.uuid)
  end
end
