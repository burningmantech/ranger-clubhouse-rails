# frozen_string_literal: true

# The status changes worth considering once an event is over.
#
# Five groups, each with one rule and one write:
#
#   inactive          an active Ranger who has stopped turning up
#   retired           someone who has been away even longer
#   active            an inactive or retired Ranger who came back
#   past prospective  an applicant left over from the season
#   vintage           a callsign that has earned the mark
#
# `counts` answers the index page. `rows` builds one group's people.
class RecommendStatusChangeReport
  INACTIVE = "inactive"
  RETIRED = "retired"
  ACTIVE = "active"
  PAST_PROSPECTIVE = "past-prospective"
  VINTAGE = "vintage"

  # A timesheet in one of these positions is not a shift, so it does not count
  # as rangering.
  NOT_RANGERING = [Position::TRAINING, Position::DEEP_FREEZE].freeze

  # How far back each rule looks, counted in events, the one asked about
  # included -- see inactive_since.
  INACTIVE_EVENTS = 3 # no shift in the last three events
  RETIRED_EVENTS = 5  # no shift in the last five events

  # Years of rangering that earn the vintage mark.
  VINTAGE_YEARS = 10

  # The two things a reader can ask about: the event now behind us, or the one
  # after it. "next-event" judges the database as if one more event has come
  # and gone.
  PERIOD_NOW = "current-date"
  PERIOD_NEXT = "next-event"
  PERIODS = [PERIOD_NOW, PERIOD_NEXT].freeze
  PERIOD_LABELS = { PERIOD_NOW => "Right now", PERIOD_NEXT => "After the next event" }.freeze

  # Written into the status history and the audit log by every change this
  # report's page makes.
  REASON = "status change recommendations"

  # A year read off a timesheet. Spelled once so every query here counts the
  # same way.
  EVENT_YEAR = Arel.sql("YEAR(on_duty)")

  # One proposed change: who it covers, what it does to them, and the write
  # that carries it out.
  Group = Data.define(:key, :title, :meaning, :consequence, :confirm, :action) do
    # True when the change moves the person's status, false when it only sets
    # a flag.
    def sets_status? = action.handler == BulkUpload::StatusHandler

    # Applicants have no rangering history, so the three history columns would
    # be empty for every one of them.
    def shows_history? = key != PAST_PROSPECTIVE

    # The vintage mark is worth a column everywhere except the group that sets
    # it, where every row would read the same.
    def shows_vintage? = sets_status? && shows_history?

    # The status a row lands on, or nil for the group that sets a flag instead.
    def target_status = sets_status? ? action.id : nil
  end

  # One person as the page and the export print them.
  Row = Data.define(:id, :callsign, :status, :email, :vintage, :years,
                    :last_year, :alpha_year)

  GROUPS = [
    Group.new(
      key: INACTIVE,
      title: "Convert to Inactive",
      meaning: "Active Rangers with no shift in the last three events, who did ranger in the last five.",
      consequence: "Inactive status leaves every position, role, and team membership in place. " \
                   "It marks the account as one that has been away.",
      confirm: { title: "Confirm Inactive Status",
                 message: "Set the checked people to inactive status?",
                 confirm_label: "Set Inactive" },
      action: BulkUpload::Action.new(id: Person::INACTIVE, label: "Convert to Inactive",
                                     help: "callsign", handler: BulkUpload::StatusHandler)
    ),
    Group.new(
      key: RETIRED,
      title: "Convert to Retired",
      meaning: "Rangers with no shift in the last five events.",
      consequence: "Retiring a person removes every team membership, and cuts their positions and roles " \
                   "back to what a brand new account holds.",
      confirm: { title: "Confirm Retired Status",
                 message: "Set the checked people to retired status? Every team membership is removed, " \
                          "and their positions and roles are cut back to a new account's.",
                 confirm_label: "Set Retired" },
      action: BulkUpload::Action.new(id: Person::RETIRED, label: "Convert to Retired",
                                     help: "callsign", handler: BulkUpload::StatusHandler)
    ),
    Group.new(
      key: ACTIVE,
      title: "Convert to Active",
      meaning: "Inactive and retired Rangers who have rangered in the last three events.",
      consequence: "Setting a person active grants the positions every Ranger holds and the roles a new " \
                   "account starts with.",
      confirm: { title: "Confirm Active Status",
                 message: "Set the checked people back to active status?",
                 confirm_label: "Set Active" },
      action: BulkUpload::Action.new(id: Person::ACTIVE, label: "Convert to Active",
                                     help: "callsign", handler: BulkUpload::StatusHandler)
    ),
    Group.new(
      key: PAST_PROSPECTIVE,
      title: "Convert to Past Prospective",
      meaning: "Prospectives, Alphas, and bonked accounts left over from the season.",
      consequence: "This removes every position, role, and team membership, drops future shift sign-ups, " \
                   "and releases the callsign -- the person is given a generated handle instead.",
      confirm: { title: "Confirm Past Prospective Status",
                 message: "Set the checked people to past prospective status? Each one loses their " \
                          "positions, roles, team memberships, and future sign-ups, and gives up their callsign.",
                 confirm_label: "Set Past Prospective" },
      action: BulkUpload::Action.new(id: Person::PAST_PROSPECTIVE, label: "Convert to Past Prospective",
                                     help: "callsign", handler: BulkUpload::StatusHandler)
    ),
    Group.new(
      key: VINTAGE,
      title: "Mark Callsign as Vintage",
      meaning: "Ten or more years of rangering, with the vintage mark not set yet.",
      consequence: "Marking a callsign vintage sets a flag and changes nothing else. Taking the mark back " \
                   "off is a one-person edit under Person Management.",
      confirm: { title: "Confirm Vintage Mark",
                 message: "Mark the checked callsigns as vintage?",
                 confirm_label: "Mark Vintage" },
      # A bare string, not Person::VINTAGE: that constant names a retired
      # status of the same name, not the flag being set here.
      action: BulkUpload::Action.new(id: "vintage", label: "Mark callsign as Vintage",
                                     help: "callsign", handler: BulkUpload::PersonFlagHandler)
    )
  ].freeze

  GROUPS_BY_KEY = GROUPS.index_by(&:key).freeze

  class << self
    # The group with this key, or nil for anything else.
    def find_group(key) = GROUPS_BY_KEY[key.to_s]

    # Anything that is not one of the two periods reads as the current one.
    def known_period(value) = PERIODS.include?(value) ? value : PERIOD_NOW

    # The event year a period asks about.
    def year_for(period) = Current.year + (period == PERIOD_NEXT ? 1 : 0)

    # Where each rule's window opens: the first of its events, counted back
    # from the year asked about, which is one of them.
    def inactive_since(year) = EventYearSpan.last_years(INACTIVE_EVENTS, through: year).first

    def retired_since(year) = EventYearSpan.last_years(RETIRED_EVENTS, through: year).first

    # How many people each group holds, keyed by group. Reads callsigns alone,
    # because that is all the test-account check needs -- and it has to run
    # here, or the index would promise more people than the group page lists.
    def counts(year)
      GROUPS.to_h do |group|
        [group.key, candidates(group, year).pluck(:callsign).count { |callsign| real?(callsign) }]
      end
    end

    # One group's people, ordered by callsign.
    #
    # keep_ids holds people on the page whose change has just been made. The
    # change is what takes them out of the group, so dropping them the moment
    # it lands would leave no sign anything happened.
    def rows(group, year, keep_ids: [])
      scope = candidates(group, year)
      scope = scope.or(Person.where(id: keep_ids)) if keep_ids.any?

      people = scope.order(:callsign)
                    .select(:id, :callsign, :status, :email, :vintage, :years_as_ranger)
                    .to_a
                    .select { |person| real?(person.callsign) }

      people.any? ? decorate(people) : []
    end

    private

    # The people a group proposes, before test accounts are dropped.
    def candidates(group, year)
      case group.key
      when INACTIVE
        # Away for the last three events, but not so long that retiring is the
        # better answer. The first half counts a timesheet in any position:
        # someone who turned up for training has not vanished.
        Person.where(status: Person::ACTIVE)
              .where.not(id: rangered_since(inactive_since(year), any_position: true))
              .where(id: rangered_since(retired_since(year)))
      when RETIRED
        Person.where(status: [Person::ACTIVE, Person::INACTIVE, Person::INACTIVE_EXTENSION])
              .where.not(id: rangered_since(retired_since(year)))
      when ACTIVE
        Person.where(status: [Person::INACTIVE, Person::INACTIVE_EXTENSION, Person::RETIRED])
              .where(id: rangered_since(inactive_since(year)))
      when PAST_PROSPECTIVE
        Person.where(status: [Person::BONKED, Person::ALPHA, Person::PROSPECTIVE])
      when VINTAGE
        # JSON_TYPE as well as JSON_LENGTH, so this counts the same thing the
        # years column prints. The database only checks the column holds valid
        # JSON, and JSON_LENGTH answers with an object's key count -- so without
        # the type check a row could be proposed here and still show no years.
        #
        # `vintage` is nullable on a table the other application also writes,
        # and `vintage = FALSE` never matches NULL, which would hide an unmarked
        # person from the one page that proposes the mark.
        Person.where(status: [Person::ACTIVE, Person::INACTIVE])
              .where(vintage: [false, nil])
              .where("JSON_TYPE(years_as_ranger) = 'ARRAY'")
              .where("JSON_LENGTH(years_as_ranger) >= ?", VINTAGE_YEARS)
      end
    end

    # Everyone with a timesheet in the given event year or later.
    #
    # A range on on_duty rather than YEAR(on_duty), which MariaDB cannot index.
    # Time.local, not Time.zone: timesheets are stored as machine-local wall
    # clock, so a zoned boundary lands an hour off and drags in the previous
    # year's last hour. Same reasoning as the `where_year` extension.
    def rangered_since(year, any_position: false)
      scope = Timesheet.where(on_duty: Time.local(year)..).select(:person_id)
      any_position ? scope : scope.where.not(position_id: NOT_RANGERING)
    end

    # Bookkeeping and laminate accounts are not people, so they are never
    # proposed for a status change.
    def real?(callsign) = !callsign.to_s.match?(Person::TEST_CALLSIGN)

    # Three queries for the whole page, whatever its length: the last year
    # rangered, the alpha year, and the stand-in for an alpha year that was
    # never recorded.
    def decorate(people)
      ids = people.map(&:id)
      # The same position exclusion the group rules use. Without it a row could
      # read "Last year rangered 2026" under a heading that says this person has
      # not taken a shift in five events, because a training entry is a
      # timesheet too.
      last_years = Timesheet.where(person_id: ids).where.not(position_id: NOT_RANGERING)
                            .group(:person_id).maximum(EVENT_YEAR)
      alpha_years = Timesheet.where(person_id: ids, position_id: Position::ALPHA)
                             .group(:person_id).maximum(EVENT_YEAR)
      alpha_years.merge!(first_dirt_years(ids - alpha_years.keys))

      people.map do |person|
        Row.new(id: person.id, callsign: person.callsign, status: person.status,
                email: person.email, vintage: person.vintage == true,
                years: years_rangered(person),
                # to_i because the database adapter, not Rails, is what makes
                # these aggregates Integers -- and the page compares them to one.
                last_year: last_years[person.id]&.to_i,
                alpha_year: alpha_years[person.id]&.to_i)
      end
    end

    # Timesheets from before 2008 carry no alpha entry, only one placeholder
    # dirt entry for each year. The earliest of those is the year the person
    # walked, so it stands in for the alpha year.
    def first_dirt_years(ids)
      return {} if ids.empty?

      Timesheet.where(person_id: ids, position_id: Position::DIRT)
               .group(:person_id).minimum(EVENT_YEAR)
    end

    # The stored list of years rangered. The database only checks that the
    # column holds valid JSON, so anything that is not a list counts as none.
    def years_rangered(person)
      years = person.years_as_ranger
      years.is_a?(Array) ? years.size : 0
    end
  end
end
