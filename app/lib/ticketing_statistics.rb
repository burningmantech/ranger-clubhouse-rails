# frozen_string_literal: true

# Ticketing statistics -- how many access documents and provisions sit in each
# status right now (Laravel App\Lib\TicketingStatistics port).
#
# Nothing here is year-scoped: like upstream, the report describes what is live
# at this moment, which is why the page carries no year selector.
module TicketingStatistics
  # The types the page reports on, in the order and under the titles the Ember
  # page used. Only special price tickets and staff credentials can be banked;
  # the rest report no banked count at all, so their card shows no banked chip
  # rather than a permanent zero.
  TYPES = [
    { type: AccessDocument::SPT, label: "Special Price Tickets", bankable: true },
    { type: AccessDocument::STAFF_CREDENTIAL, label: "Staff Credentials", bankable: true },
    { type: AccessDocument::VEHICLE_PASS_SP, label: "Special Price Vehicle Passes" },
    { type: AccessDocument::VEHICLE_PASS_GIFT, label: "Gift Vehicle Passes" },
    { type: AccessDocument::LSD, label: "LSD Tickets" },
    { type: AccessDocument::VEHICLE_PASS_LSD, label: "LSD Vehicle Passes" },
    { type: AccessDocument::GIFT, label: "Gift Tickets" },
    { type: AccessDocument::SAP, label: "Setup Access Passes" }
  ].freeze

  # One type's counts plus the meter geometry its card draws. #counts is ordered
  # claimed, unclaimed, banked, submitted -- the order the old page's columns
  # ran in, and the order a document travels in.
  TypeCount = Struct.new(:label, :counts, keyword_init: true) do
    # Every document of this type in one of the reported statuses.
    def total
      counts.values.sum
    end

    # [status, percentage] for each status actually holding a document. Empty
    # statuses drop out so the meter never draws a sliver too thin to see; the
    # chips beside it still name every status this type can be in.
    def segments
      return [] if total.zero?

      counts.filter_map do |status, count|
        [status, (count * 100.0 / total).round(2)] unless count.zero?
      end
    end
  end

  class << self
    def execute
      tallies = document_tallies

      {
        people: people_counts,
        types: TYPES.map { |spec| type_count(spec, tallies) },
        sapso: sapso_counts(tallies),
        provisions: provision_counts
      }
    end

    private

    # Every card's counts in one read, keyed [type, status]. Counting each pair
    # separately meant thirty-odd COUNTs against the largest table the page
    # touches; access_document_type_status_index serves this grouped read
    # directly.
    def document_tallies
      AccessDocument.where(type: [*TYPES.pluck(:type), AccessDocument::SAPSO],
                           status: AccessDocument::CURRENT_STATUSES)
                    .group(:type, :status)
                    .count
    end

    # The four headline counts. All of them count people rather than documents,
    # and all of them look only at regular tickets (special price tickets and
    # staff credentials) -- the documents a Ranger earns.
    def people_counts
      regular = AccessDocument.where(type: AccessDocument::REGULAR_TICKET_TYPES)

      {
        claimed: distinct_people(regular.where(status: AccessDocument::CLAIMED)),
        # Banked and unclaimed both mean "and has settled nothing else", so each
        # excludes people holding a claimed (or, for unclaimed, banked) document.
        # Those exclusions deliberately span every type, not just regular
        # tickets, matching upstream's subqueries.
        unclaimed: distinct_people(
          regular.where(status: AccessDocument::QUALIFIED)
                 .where.not(person_id: holders_of(AccessDocument::CLAIMED, AccessDocument::BANKED))
        ),
        banked: distinct_people(
          regular.where(status: AccessDocument::BANKED)
                 .where.not(person_id: holders_of(AccessDocument::CLAIMED))
        ),
        submitted: distinct_people(regular.where(status: AccessDocument::SUBMITTED))
      }
    end

    def type_count(spec, tallies)
      type = spec[:type]

      counts = {
        AccessDocument::CLAIMED => tallies.fetch([type, AccessDocument::CLAIMED], 0),
        AccessDocument::QUALIFIED => tallies.fetch([type, AccessDocument::QUALIFIED], 0)
      }
      counts[AccessDocument::BANKED] = tallies.fetch([type, AccessDocument::BANKED], 0) if spec[:bankable]
      counts[AccessDocument::SUBMITTED] = tallies.fetch([type, AccessDocument::SUBMITTED], 0)

      TypeCount.new(label: spec[:label], counts: counts)
    end

    # S.O. setup access passes are counted apart from the other types: what the
    # ticketing crew needs is how many Rangers brought a partner along, which is
    # a count of people, not of passes.
    def sapso_counts(tallies)
      {
        people: distinct_people(AccessDocument.where(type: AccessDocument::SAPSO,
                                                     status: AccessDocument::CLAIMED)),
        claimed: tallies.fetch([AccessDocument::SAPSO, AccessDocument::CLAIMED], 0),
        submitted: tallies.fetch([AccessDocument::SAPSO, AccessDocument::SUBMITTED], 0)
      }
    end

    def provision_counts
      {
        earned: distinct_people(Provision.where(status: Provision::AVAILABLE, is_allocated: false)),
        allocated: distinct_people(Provision.where(status: [Provision::AVAILABLE, Provision::SUBMITTED],
                                                    is_allocated: true)),
        # Upstream asks this as "has a sibling provision whose allocation flag
        # differs". Holding at least one of each is the same set of people, and
        # says so without the correlated subquery.
        both: distinct_people(
          Provision.valid.where(is_allocated: true)
                   .where(person_id: Provision.valid.where(is_allocated: false).select(:person_id))
        ),
        banked: distinct_people(Provision.where(status: Provision::BANKED))
      }
    end

    def distinct_people(scope)
      scope.distinct.count(:person_id)
    end

    # person_id is NOT NULL on access_document, so a NOT IN against this never
    # hits the SQL null trap.
    def holders_of(*statuses)
      AccessDocument.where(status: statuses).select(:person_id)
    end
  end
end
