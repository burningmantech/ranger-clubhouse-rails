# frozen_string_literal: true

# Category filters for the BMID management listing.
#
# Port of the Laravel App\Lib\BMIDManagement::retrieveCategoryToManage. Every
# category resolves to a set of person ids; Bmid.find_for_person_ids then loads
# the badges those people already have and synthesizes an in-prep badge for
# everyone else, so a category shows the people who need attention whether or
# not a badge record exists yet.
#
# Deliberately not ported:
#   * the "signedup" category -- deprecated upstream, superseded by "qualified".
#   * the EXISTS(provision ...) sub-clause inside the special category's BMID
#     query -- it is a strict subset of the standalone provision query below.
class BmidManagement
  SPECIAL = "special"
  ALPHA = "alpha"
  QUALIFIED = "qualified"
  NONPRINT = "nonprint"
  NO_SHIFTS = "no-shifts"

  # Everything falls back to this, including unknown filter values.
  DEFAULT_FILTER = SPECIAL

  FILTER_OPTIONS = [
    ["Specials (titles, meals, showers, or early arrival)", SPECIAL],
    ["Alphas", ALPHA],
    ["Vets w/claimed tickets/SAPs OR In-Person training sign-ups", QUALIFIED],
    ["BMIDs marked as Issues or Do Not Print", NONPRINT],
    ["No shift sign-ups", NO_SHIFTS],
    ["In Prep", Bmid::IN_PREP],
    ["Ready To Print", Bmid::READY_TO_PRINT],
    ["Submitted BMIDs", Bmid::SUBMITTED]
  ].freeze

  FILTERS = FILTER_OPTIONS.map(&:last).freeze

  # Signing up for one of these earns a badge (the "In-Person training" arm).
  TRAINING_POSITIONS = [
    Position::TRAINING,
    Position::TRAINER,
    Position::TRAINER_ASSOCIATE,
    Position::TRAINER_UBER
  ].freeze

  # Documents that can grant early or any-time arrival.
  EARLY_ACCESS_TYPES = [AccessDocument::STAFF_CREDENTIAL, AccessDocument::SAP].freeze
  EARLY_ACCESS_STATUSES = [
    AccessDocument::BANKED,
    AccessDocument::QUALIFIED,
    AccessDocument::CLAIMED,
    AccessDocument::SUBMITTED
  ].freeze

  # Provisions that make a badge special (they get printed on it).
  SPECIAL_PROVISION_TYPES = [Provision::WET_SPOT, Provision::MEALS].freeze
  SPECIAL_PROVISION_STATUSES = [Provision::AVAILABLE, Provision::CLAIMED, Provision::SUBMITTED].freeze

  # Holding one of these earns a badge (the "claimed ticket" arm).
  QUALIFYING_TICKET_TYPES = [
    AccessDocument::SPT,
    AccessDocument::STAFF_CREDENTIAL,
    AccessDocument::SAP
  ].freeze
  QUALIFYING_TICKET_STATUSES = [AccessDocument::CLAIMED, AccessDocument::SUBMITTED].freeze

  class << self
    # Every badge in a category, real or synthesized, sorted by callsign.
    #
    # Departed people are dropped from the current year only: a past year's
    # badge list is a historical record and should still show them.
    #
    # @param filter [String] one of FILTERS; anything else means DEFAULT_FILTER
    # @param year [Integer]
    # @return [Array<Bmid>]
    def retrieve_category_to_manage(filter, year)
      Bmid.find_for_person_ids(year, category_person_ids(filter, year), year == Current.year)
    end

    # The people a category covers.
    #
    # @param filter [String] one of FILTERS; anything else means DEFAULT_FILTER
    # @param year [Integer]
    # @return [Array<Integer>]
    def category_person_ids(filter, year)
      case filter
      when ALPHA
        alpha_person_ids
      when QUALIFIED
        qualified_person_ids(year)
      when NONPRINT
        bmid_person_ids_with_status(year, [Bmid::ISSUES, Bmid::DO_NOT_PRINT])
      when NO_SHIFTS
        bmid_person_ids_without_shifts(year)
      when Bmid::IN_PREP, Bmid::READY_TO_PRINT, Bmid::SUBMITTED
        bmid_person_ids_with_status(year, [filter])
      else
        special_person_ids(year)
      end
    end

    private

    # Alphas & Prospectives, regardless of year, tickets, or sign-ups: they all
    # need a badge made for them.
    def alpha_person_ids
      Person.where(status: [Person::ALPHA, Person::PROSPECTIVE]).pluck(:id)
    end

    # Rangers who claimed a ticket or signed up for In-Person Training.
    #
    # The ticket arm is not year-scoped -- upstream parity; a claimed ticket is
    # for the upcoming event by definition.
    def qualified_person_ids(year)
      ticket_ids = AccessDocument.joins(:person)
                                 .where(person: { status: Person::ACTIVE_STATUSES })
                                 .where(type: QUALIFYING_TICKET_TYPES)
                                 .where(status: QUALIFYING_TICKET_STATUSES)
                                 .distinct
                                 .pluck(:person_id)

      training_ids = PersonSlot.joins(:person, :slot)
                               .where(person: { status: Person::ACTIVE_STATUSES })
                               .where(slot: { begins_year: year, active: true, position_id: TRAINING_POSITIONS })
                               .distinct
                               .pluck(:person_id)

      ticket_ids | training_ids
    end

    # Badges worth a second look: a title, meals, or showers on the badge, an
    # arrival earlier than everyone else's, or a wet spot / meal provision.
    def special_person_ids(year)
      badge_person_ids(year) | early_access_person_ids(year) | special_provision_person_ids
    end

    # Badges carrying a printed extra. This is the last reader of the meals &
    # showers columns anywhere in the app: nothing displays them, nothing here
    # writes them, and the printer takes its meals and showers from the live
    # provision rows instead. They still mark the badges an earlier year fussed
    # over, so upstream keeps them in this one query, and so do we.
    def badge_person_ids(year)
      scope = Bmid.where(year: year)

      scope.where.not(title1: nil)
           .or(scope.where.not(title2: nil))
           .or(scope.where.not(title3: nil))
           .or(scope.where.not(meals: nil))
           .or(scope.where(showers: true))
           .pluck(:person_id)
    end

    # People who can get in at any time, or before the default SAP date.
    def early_access_person_ids(year)
      scope = AccessDocument.where(type: EARLY_ACCESS_TYPES).where(status: EARLY_ACCESS_STATUSES)
      any_time = scope.where(access_any_time: true)
      cutoff = early_arrival_cutoff

      # With no usable setting, only any-time access counts as early: there is
      # nothing to compare an access date against.
      if cutoff
        # where_year already excludes rows with no access date.
        early = scope.where_year("access_date", year).where(access_date: ...cutoff)
        any_time = any_time.or(early)
      end

      any_time.distinct.pluck(:person_id)
    end

    # Anyone holding a usable wet spot or meal provision. Deliberately not
    # year-scoped -- upstream parity.
    def special_provision_person_ids
      Provision.where(type: SPECIAL_PROVISION_TYPES)
               .where(status: SPECIAL_PROVISION_STATUSES)
               .distinct
               .pluck(:person_id)
    end

    # The day general SAP access starts. Arriving before it is what makes a
    # badge special. Built with Time.local because access_date is stored as
    # machine-local wall clock (see GlobalRelationExtensions#where_year).
    #
    # @return [Time, nil] nil when the setting is missing or unreadable
    def early_arrival_cutoff
      value = Setting.get_value(Setting::TAS_DEFAULT_SAP_DATE)
      return nil if value.blank?

      date = Date.parse(value.to_s)
      Time.local(date.year, date.month, date.day)
    rescue Date::Error, TypeError
      nil
    end

    def bmid_person_ids_with_status(year, statuses)
      Bmid.where(year: year, status: statuses).pluck(:person_id)
    end

    # Badges belonging to people with nothing on the schedule this year.
    #
    # Only people who already have a badge row are considered -- upstream
    # parity, and the question ("why is this badge being made?") only makes
    # sense for a badge that exists.
    def bmid_person_ids_without_shifts(year)
      signed_up = PersonSlot.joins(:slot).where(slot: { begins_year: year }).select(:person_id)

      Bmid.where(year: year).where.not(person_id: signed_up).pluck(:person_id)
    end
  end
end
