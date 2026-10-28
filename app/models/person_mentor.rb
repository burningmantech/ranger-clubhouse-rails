# frozen_string_literal: true

class PersonMentor < ApplicationRecord
  self.table_name = "person_mentor"

  # Matching upstream's `protected bool $auditModel = true` on App\Models\PersonMentor,
  # which this class was missing. Who a person walked with, and whether they
  # passed, is the record the mentor cadre is later asked to justify, so every
  # create/update/destroy writes an ActionLog row. Switched on with the Alpha
  # Mentor Assignments page.
  self.audit_model = true

  # Status constants
  STATUS_PASS = "pass" # person passed their alpha shift
  STATUS_BONK = "bonk" # person was bonked
  STATUS_SELF_BONK = "self-bonk" # person decided to self bonk
  STATUS_PENDING = "pending" # person is walking an Alpha shift with assigned mentors.
  # Two verdicts only an ART walk records (ruled 2026-10-27): its roster offers
  # them, the Alpha pages never do.
  STATUS_ABSTAIN = "abstain" # the mentor declined to give a verdict
  STATUS_NOT_COMPLETED = "not-completed" # the mentee did not complete the shift

  # What an Alpha walk records, and all the Alpha pages offer or accept.
  ALPHA_STATUSES = [STATUS_PASS, STATUS_BONK, STATUS_SELF_BONK, STATUS_PENDING].freeze
  # What the column holds, and what an ART walk records.
  STATUSES = (ALPHA_STATUSES + [STATUS_ABSTAIN, STATUS_NOT_COMPLETED]).freeze

  # Which verdict wins when a person's same-year rows disagree: either refusal
  # outranks a pass, a bonk outranks a self-bonk, and a pending row -- still
  # walking -- yields to any recorded verdict. A row with no status at all
  # yields to every one of them (see .year_verdict). An ART walk's Not completed
  # and Abstained are not passes either, so they rank under the bonks and over a
  # pass (ruled 2026-10-27); the ART roster writes one status across a walk's
  # rows, so only a half-finished edit could make them disagree.
  #
  # Ranked explicitly rather than by taking the smallest value, which only looks
  # equivalent: the verdicts sort "bonk" < "pass" < "self-bonk", so a MIN is
  # cautious against a bonk and the opposite against a self-bonk -- it would mint
  # an Alpha who had chosen to stop. `order(:status).first` is a third answer
  # again, because `status` is an
  # `enum('pass','bonk','self-bonk','pending','abstain','not-completed')` and
  # MySQL sorts an ENUM by declaration index while MIN/MAX compare the string:
  # that one answers "pass" for every disagreement. Three plausible one-liners,
  # three different verdicts, so the order is written down.
  #
  # AlphaMentorAssignment writes one status across all of a year's rows, so a
  # disagreement means rows this app did not write -- the Laravel side, or a
  # half-finished edit.
  VERDICT_PRECEDENCE = [STATUS_BONK, STATUS_SELF_BONK, STATUS_NOT_COMPLETED, STATUS_ABSTAIN,
                        STATUS_PASS, STATUS_PENDING].freeze

  # Data classes for query results
  MentorInfo = Data.define(:id, :callsign)
  MentorWithAvatar = Data.define(:id, :callsign, :avatar, :can_message?)
  MenteeInfo = Data.define(:id, :callsign, :avatar, :status, :can_message?, :mentor_status, :last_worked, :fkas, :mentors)
  YearCohort = Data.define(:year, :alphas, :passed, :bonked)
  PassingResult = Data.define(:year, :current_status, :mentors)

  # Associations
  belongs_to :person
  # Optional only for an ART pass; the check below holds every other walk to it.
  belongs_to :mentor, class_name: "Person", optional: true
  # An ART walk's mentee shift. Optional: an Alpha walk has none, and a walk
  # outlives a deleted entry (ruled 2026-10-21).
  belongs_to :timesheet, optional: true

  # Validations
  validates :person_id, presence: true
  validates :mentor_year, presence: true
  # The table is shared by mentee position: position_id names the position the
  # walk was for, every reader below takes it as a required keyword, and every
  # writer passes it. This only refuses an explicit nil. A writer that omits the
  # column gets the database default, Position::ALPHA, and silently records an
  # Alpha walk, so nothing here catches a forgotten position.
  validates :position_id, presence: true
  # An ART walk (it names a timesheet entry) may also end Abstained or Not
  # completed; an Alpha walk never does, since every Alpha reader knows four.
  validates :status, presence: true, inclusion: { in: ->(row) { row.timesheet_id ? STATUSES : ALPHA_STATUSES } }
  # Every walk names its mentor except an ART pass recorded without one (owner,
  # 2026-10-28): one row with mentor_id NULL (ArtMentoring::Assignment).
  validates :mentor, presence: { message: :required }, unless: :mentor_optional?
  # An ART walk is one row per mentor who walked the mentee's shift, each
  # naming the mentee's timesheet entry. Alpha walks leave it NULL.
  validates :timesheet_id, uniqueness: { scope: :mentor_id,
                                         message: "That mentor is already recorded for this mentee shift" },
                           allow_nil: true
  # One row per mentor, mentee, year and position for an Alpha walk. The
  # database's person_id key spells this out but cannot hold it: the key ends
  # in timesheet_id, which an Alpha row leaves NULL, and MariaDB never matches
  # one NULL against another. Here a nil scope value is compared with IS NULL.
  # An ART row is held by its timesheet_id instead. Checked only when the key
  # can change: Rails cannot skip the query for an unchanged row whose scope
  # holds a NULL, and an Alpha save restates every row's status.
  validates :mentor_id, uniqueness: { scope: %i[person_id mentor_year position_id timesheet_id],
                                      message: "That mentor is already recorded for this person and year" },
                        if: lambda {
                          timesheet_id.nil? &&
                            (new_record? || changed.intersect?(%w[person_id mentor_id mentor_year position_id timesheet_id]))
                        }

  # An ART walk's pass, the one walk that may name no mentor.
  def mentor_optional? = timesheet_id.present? && status == STATUS_PASS

  class << self
    # May the mentoring pages offer Send Message to this person: a Ranger the
    # compose page accepts (Person#messaging_permitted?).
    def can_message?(person) = person.is_ranger? && person.messaging_permitted?.present?

    # One person's verdict for one year from the statuses of that year's rows,
    # settled by VERDICT_PRECEDENCE, so it is the same whichever order the rows
    # arrive in. nil only when no row carries a status.
    def year_verdict(statuses)
      statuses.min_by { |status| VERDICT_PRECEDENCE.index(status) || VERDICT_PRECEDENCE.size }
    end

    def retrieve_mentees_for_person(mentor_id, position_id:)
      # The inner join drops rows whose mentee has been deleted, as upstream's
      # JOIN person did; nothing removes person_mentor rows when a person goes.
      mentees = PersonMentor.joins(:person)
                            .where(mentor_id:, position_id:)
                            .where.not(status: STATUS_PENDING)
                            .includes([{ person: [:person_fka, :photo] }])

      return [] if mentees.empty?

      mentee_ids = mentees.map(&:person_id).uniq

      person_mentors = PersonMentor.where(person_id: mentee_ids, position_id:)
                                   .where("EXISTS (SELECT 1 FROM person_mentor pm WHERE pm.mentor_id=:person_id AND pm.person_id=person_mentor.person_id AND pm.mentor_year=person_mentor.mentor_year AND pm.position_id=person_mentor.position_id)", person_id: mentor_id)
                                   .includes(:mentor)
                                   .group_by(&:person_id).transform_values { |person| person.group_by(&:mentor_year) }

      # Leaves out the Alpha walk and Training. Alpha-specific on purpose: whether
      # another mentee position's shift counts as rangering is not decided yet,
      # so revisit this list when a caller passes a position other than Alpha.
      last_worked = Timesheet
                      .select("person_id, YEAR(on_duty) as year")
                      .where(person_id: mentee_ids)
                      .where(is_echelon: false)
                      .where.not(position_id: [Position::ALPHA, Position::TRAINING])
                      .group("person_id, YEAR(on_duty)")
                      .order("YEAR(on_duty)")
                      .index_by(&:person_id)

      mentees.group_by(&:mentor_year).map do |year, cohort|
        alphas = cohort.map do |person_mentor|
          person_id = person_mentor.person_id
          person = person_mentor.person
          MenteeInfo.new(
            id: person_id,
            callsign: person.callsign,
            avatar: person.avatar_photo,
            status: person.status,
            can_message?: can_message?(person),
            mentor_status: person_mentor.status,
            last_worked: last_worked[person_id]&.year,
            fkas: person.person_fka.reject(&:is_irrelevant).map(&:fka),
            mentors: person_mentors[person_id][year].map do |mentor|
              MentorInfo.new(
                id: mentor.mentor_id,
                callsign: mentor.mentor&.callsign || "Deleted ##{mentor.mentor_id}"
              )
            end.sort_by(&:callsign)
          )
        end.sort_by(&:callsign)

        YearCohort.new(
          year: year,
          alphas: alphas,
          passed: alphas.count { |alpha| alpha.mentor_status == STATUS_PASS },
          bonked: alphas.count { |alpha| alpha.mentor_status != STATUS_PASS }
        )
      end.sort_by(&:year).reverse
    end

    # Find the most recent year of mentor records for a person, returning
    # the year, its shared status, and the mentor list. Status is not filtered,
    # so callers can distinguish between passing and non-passing years.
    def retrieve_passing_for_person(person_id, position_id:)
      walks = where(person_id:, position_id:)
      most_recent_year = walks.maximum(:mentor_year)
      return PassingResult.new(year: nil, current_status: nil, mentors: []) unless most_recent_year

      rows = walks.select("person_mentor.*")
               .joins(:mentor)
               .where(mentor_year: most_recent_year)
               .order("mentor.callsign")
               .includes(mentor: :photo)

      mentors = rows.map do |row|
        MentorWithAvatar.new(
          id: row.mentor_id,
          callsign: row.mentor.callsign,
          avatar: row.mentor.avatar_photo,
          can_message?: can_message?(row.mentor)
        )
      end

      PassingResult.new(
        year: most_recent_year,
        # The year's verdict, settled like every other reader's: the rows can
        # disagree, and the first by callsign is just whichever sorts first.
        current_status: year_verdict(rows.map(&:status)),
        mentors: mentors
      )
    end

    # Which years each person bonked or self-bonked, ascending -- the "Prior
    # Bonks" column of the Mentor Shift Report (upstream
    # MentorShiftReport::fetchBonks). People with no bonks have no key.
    def bonk_years_by_person(person_ids, position_id:)
      where(person_id: person_ids, position_id:, status: [STATUS_BONK, STATUS_SELF_BONK])
        .distinct
        .pluck(:person_id, :mentor_year)
        .group_by(&:first)
        .transform_values { |pairs| pairs.map(&:last).sort }
    end

    # One person's slice of retrieve_all_mentors_for_ids, flattened for display:
    # oldest year first, each row `{ year:, status:, mentors: [callsign] }`.
    # Callers wanting upstream's newest-first order reverse it.
    def history_rows(mentorships)
      mentorships.sort.map do |mentor_year, info|
        { year: mentor_year, status: info[:status], mentors: info[:mentors].map { |m| m[:callsign] } }
      end
    end

    # Bulk retrieve mentor history for a set of people, grouped by person then
    # mentor_year. Upstream's PHP method takes a $year cutoff parameter, but a
    # loop variable also named $year immediately shadows it, so the parameter
    # is dead code and every mentor_year is returned unfiltered. Ported as-is
    # (no year parameter here) rather than adding a filter that never existed.
    #
    # A year's status is .year_verdict of its rows. Upstream read the first row,
    # which is whichever one the database returns first when they disagree --
    # the review pane, the bonk chip and the mentor worksheet all read this.
    def retrieve_all_mentors_for_ids(person_ids, position_id:)
      rows = where(person_id: person_ids, position_id:)
               .order(:person_id, :mentor_year)
               .includes(:mentor)

      rows.group_by(&:person_id).transform_values do |person_rows|
        person_rows.group_by(&:mentor_year).transform_values do |year_rows|
          {
            status: year_verdict(year_rows.map(&:status)),
            mentors: year_rows.map do |row|
              {
                id: row.mentor_id,
                callsign: row.mentor&.callsign || "Deleted ##{row.mentor_id}"
              }
            end.sort_by { |mentor| mentor[:callsign].downcase }
          }
        end
      end
    end
  end
end
