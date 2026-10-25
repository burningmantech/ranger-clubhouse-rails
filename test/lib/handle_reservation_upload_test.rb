# frozen_string_literal: true

require "test_helper"

class HandleReservationUploadTest < ActiveSupport::TestCase
  BRC_TERM = HandleReservation::RESERVATION_TYPE_BRC_TERM
  TWII = HandleReservation::RESERVATION_TYPE_TWII_PERSON

  def upload(handles, **options)
    HandleReservationUpload.execute(handles: handles, reservation_type: BRC_TERM, **options)
  end

  test "reports a handle the list repeats without saving anything" do
    results = assert_no_difference "HandleReservation.count" do
      upload("Fresh One\nfresh  one\nFresh Two")
    end

    assert_nil results[0][:error]
    assert_equal "Handle is listed more than once in this upload", results[1][:error]
    assert_nil results[2][:error]
  end

  test "a repeat never saves twice on commit" do
    results = assert_difference "HandleReservation.count", 1 do
      upload("Fresh One\nFresh One", commit: true)
    end

    assert_nil results[0][:error]
    # The first row is saved by the time the second is checked, so the model's
    # own uniqueness check reports it and the wording differs from a verify.
    assert_match "has already been reserved", results[1][:error]
  end

  test "reports a repeat among twii entries, which key on the year too" do
    results = HandleReservationUpload.execute(handles: "Fresh One\nFresh One",
                                              reservation_type: TWII,
                                              twii_year: 2029)

    assert_equal "Handle is listed more than once in this upload", results[1][:error]
  end

  test "carries the source line and its number for every row" do
    results = upload("\nFresh One\n\nBadline,notadate\n")

    assert_equal [2, 4], results.map { |row| row[:line_number] }
    assert_equal ["Fresh One", "Badline,notadate"], results.map { |row| row[:line] }
    assert_equal "Invalid Date", results[1][:error]
  end

  test "still reports a handle already reserved in the database" do
    results = upload(handle_reservation(:ranger_term).handle,
                     reservation_type: HandleReservation::RESERVATION_TYPE_RANGER_TERM)

    assert_match "has already been reserved for this type", results[0][:error]
  end
end
