# frozen_string_literal: true

require "test_helper"

class SpigotFlowReportTest < ActiveSupport::TestCase
  include PersonPhotoTestHelper

  # Well past the Salesforce cutover and clear of the 2025/2026 fixture data.
  YEAR = 2030

  setup do
    @pnv_a = person(:prospective_ranger) # ProspectiveNewbie
    @pnv_b = person(:alpha_ranger)       # AlphaNewbie
    @outsider = person(:active_ranger)
  end

  test "post-cutover report buckets each milestone by day" do
    Position.create!(id: Position::TRAINING, title: "Training")
    Position.create!(id: Position::ALPHA, title: "Alpha")

    create_application(person: @pnv_a, status: ProspectiveApplication::STATUS_CREATED,
                       created_at: "2030-03-01 10:00")
    create_application(person: @pnv_b, status: ProspectiveApplication::STATUS_CREATED,
                       created_at: "2030-03-01 12:00")
    # Never became an account: imported only, with a blanked identity.
    create_application(person: nil, status: ProspectiveApplication::STATUS_PENDING,
                       created_at: "2030-03-02 09:00")

    # First logins: A is the plain aggregate path; B's earliest in-year login
    # predates the import and must fall back to the first post-import login.
    log_login(@pnv_a, "2030-03-05 09:00")
    log_login(@pnv_b, "2030-02-15 09:00")
    log_login(@pnv_b, "2030-03-06 18:00")

    # B drops out; a non-cohort drop must not appear.
    drop(@pnv_b, "2030-04-01 12:00")
    drop(@outsider, "2030-04-02 12:00")

    # Photos: A's counts in-year; B's carried-forward photo lands in the
    # previous-year bucket.
    create_photo(person: @pnv_a, status: PersonPhoto::APPROVED,
                 reviewed_at: Time.zone.parse("2030-03-10 10:00"))
    create_photo(person: @pnv_b, status: PersonPhoto::APPROVED,
                 reviewed_at: Time.zone.parse("2029-12-01 10:00"))

    # Online course: B's completion is filed under a different year.
    complete_online_course(@pnv_a, year: YEAR, completed_at: "2030-03-12 20:00")
    complete_online_course(@pnv_b, year: YEAR - 1, completed_at: "2030-03-13 20:00")

    training1 = create_slot(Position::TRAINING, "2030-05-01 09:00")
    training2 = create_slot(Position::TRAINING, "2030-06-01 09:00")
    signup(@pnv_a, training1, "2030-03-15 09:00")
    signup(@pnv_a, training2, "2030-03-20 09:00") # second signup — only the first counts
    signup(@pnv_b, training1, "2030-03-16 09:00")
    TraineeStatus.create!(person: @pnv_a, slot: training1, status: TraineeStatus::STATUS_PASSED)
    TraineeStatus.create!(person: @pnv_b, slot: training1, status: TraineeStatus::STATUS_NOT_PASSED)

    alpha = create_slot(Position::ALPHA, "2030-08-25 06:00")
    signup(@pnv_b, alpha, "2030-04-10 09:00")

    days = SpigotFlowReport.execute(YEAR)
    by_day = days.index_by { |day| day[:day] }

    assert_equal days.map { |day| day[:day] }.sort, days.map { |day| day[:day] }
    assert_equal SpigotFlowReport::PREVIOUS_YEAR_KEY, days.first[:day]

    march1 = by_day["2030-03-01"]
    assert_equal 2, march1[:imported].size
    assert_equal %w[AlphaNewbie ProspectiveNewbie], callsigns(march1[:created])

    march2 = by_day["2030-03-02"]
    assert_equal [{ id: "", callsign: "" }], march2[:imported]
    assert_nil march2[:created]

    assert_equal %w[ProspectiveNewbie], callsigns(by_day["2030-03-05"][:first_login])
    assert_equal %w[AlphaNewbie], callsigns(by_day["2030-03-06"][:first_login])
    assert_nil by_day["2030-02-15"]

    assert_equal %w[ProspectiveNewbie], callsigns(by_day["2030-03-10"][:photo_approved])
    assert_equal %w[AlphaNewbie],
                 callsigns(by_day[SpigotFlowReport::PREVIOUS_YEAR_KEY][:photo_approved])

    assert_equal %w[ProspectiveNewbie], callsigns(by_day["2030-03-12"][:online_trained])
    assert_nil by_day["2030-03-13"]

    assert_equal %w[ProspectiveNewbie], callsigns(by_day["2030-03-15"][:training_signups])
    assert_equal %w[AlphaNewbie], callsigns(by_day["2030-03-16"][:training_signups])
    assert_nil by_day["2030-03-20"]

    assert_equal %w[ProspectiveNewbie], callsigns(by_day["2030-05-01"][:training_passed])
    assert_nil by_day["2030-06-01"]

    assert_equal %w[AlphaNewbie], callsigns(by_day["2030-04-10"][:alpha_signups])

    assert_equal %w[AlphaNewbie], callsigns(by_day["2030-04-01"][:dropped])
    assert_nil by_day["2030-04-02"]
  end

  test "pre-cutover years use status conversions with imported equal to created" do
    convert(@pnv_a, "2024-02-01 10:00")
    convert(@pnv_a, "2024-03-01 10:00") # duplicate conversion — only the first counts
    convert(@pnv_b, "2024-02-15 10:00")

    by_day = SpigotFlowReport.execute(2024).index_by { |day| day[:day] }

    assert_equal %w[ProspectiveNewbie], callsigns(by_day["2024-02-01"][:imported])
    assert_equal %w[ProspectiveNewbie], callsigns(by_day["2024-02-01"][:created])
    assert_equal %w[AlphaNewbie], callsigns(by_day["2024-02-15"][:created])
    assert_nil by_day["2024-03-01"]
  end

  test "a year with no applicants returns an empty report" do
    assert_empty SpigotFlowReport.execute(2010)
  end

  # Datetimes are stored as machine-local wall clock while Time.zone is Phoenix,
  # so a Time.zone-anchored window starts an hour early and pulls the last hour
  # of Dec 31 into the following year. Pin both edges to the stored value, the
  # same year YEAR(created_at) reports.
  test "the last hour of Dec 31 belongs to the year it is stored under" do
    convert(@pnv_a, Time.local(2023, 12, 31, 23, 30))
    convert(@pnv_b, Time.local(2024, 12, 31, 23, 30))

    # Each record belongs to the year it is stored under and buckets on Dec 31,
    # rather than leaking forward as "2025-01-01"/"2024-01-01".
    assert_equal ["2024-12-31"], report_days(2024)
    assert_equal ["2023-12-31"], report_days(2023)
  end

  private

  def create_application(person:, status:, created_at:)
    bpguid = "SPIGOT-#{SecureRandom.hex(6)}"
    ProspectiveApplication.create!(
      bpguid:, email: "#{bpguid}@example.com", year: YEAR, status:, person:,
      created_at: Time.zone.parse(created_at)
    )
  end

  # Accepts a Time as-is so boundary tests can pin the stored wall clock.
  def convert(person, time)
    time = Time.zone.parse(time) if time.is_a?(String)
    PersonStatus.create!(person_id: person.id, old_status: Person::AUDITOR,
                         new_status: Person::PROSPECTIVE, created_at: time)
  end

  def drop(person, time)
    PersonStatus.create!(person_id: person.id, old_status: Person::PROSPECTIVE,
                         new_status: Person::PAST_PROSPECTIVE, created_at: Time.zone.parse(time))
  end

  def log_login(person, time)
    ActionLog.create!(person_id: person.id, event: "auth-login",
                      message: "", created_at: Time.zone.parse(time))
  end

  def complete_online_course(person, year:, completed_at:)
    PersonOnlineCourse.create!(person:, online_course: online_course(:training_all_2026),
                               position_id: Position::TRAINING, year:,
                               type: PersonOnlineCourse::TYPE_MOODLE,
                               completed_at: Time.zone.parse(completed_at))
  end

  def create_slot(position_id, begins)
    begins = Time.zone.parse(begins)
    Slot.create!(position_id:, begins:, ends: begins + 6.hours, max: 10,
                 description: "Session", active: true)
  end

  def signup(person, slot, time)
    PersonSlot.create!(person:, slot:, created_at: Time.zone.parse(time))
  end

  # Day keys carrying a milestone, minus the carried-forward photo bucket.
  def report_days(year)
    SpigotFlowReport.execute(year).map { |day| day[:day] } - [SpigotFlowReport::PREVIOUS_YEAR_KEY]
  end

  def callsigns(people)
    (people || []).map { |person| person[:callsign] }
  end
end
