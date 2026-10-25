# frozen_string_literal: true

# Ticketing Management module
#
# Ported from Laravel's App\Lib\TicketingManagement (retrieveCurrentByPerson).
#
# Powers the Ticketing > Access Documents summary page: every still-live access
# document, gathered under the person holding it, plus the arrival-date problems
# worth flagging to a VC.
#
# The upstream $forDelivery variant's delivery overrides and delivery errors
# live in TrsExport (the TRS export page), which reuses the access-date
# validation and SAP day range below.
module TicketingManagement
  # Allowable SC & SAP arrival days used when the TAS_SAPDateRange setting is
  # missing or malformed. Mirrors the upstream 5..26 fallback.
  DEFAULT_DAY_LOW = 5
  DEFAULT_DAY_HIGH = 26

  # Holders in these statuses never appear in the summary.
  EXCLUDED_HOLDER_STATUSES = [Person::DECEASED, Person::DISMISSED].freeze

  class << self
    # Retrieve every current (qualified, claimed, banked, or submitted) access
    # document, grouped by the person holding it.
    #
    # Upstream scopes this to ACTIVE_STATUSES, which drops submitted documents.
    # We include them deliberately: a submitted document is a live allocation
    # for the year, its holder is someone the ticketing crew still needs to see,
    # and the sibling records page has always listed them. Leaving them out hid
    # 160 people who hold nothing else.
    #
    # People are ordered by callsign. Deceased and dismissed holders are left
    # out entirely.
    #
    # Nothing is written onto the AccessDocument instances: the per-document
    # problems are returned as ready-to-display strings alongside the documents.
    #
    # @return [Hash] :people -- array of { person:, documents:, errors: },
    #                :day_low, :day_high -- the allowable arrival day window
    def retrieve_current_by_person
      day_low, day_high = sap_day_range

      # Ordering by id as well keeps "the first document of type X" stable --
      # the summary row picks one document per column, and source_year alone
      # leaves same-year rows in whatever order the database hands back.
      documents = AccessDocument.where(status: AccessDocument::CURRENT_STATUSES)
                                .includes(:person)
                                .order(:source_year, :id)
                                .to_a

      documents_by_person = documents.group_by(&:person_id)

      people = documents.filter_map(&:person)
                        .uniq(&:id)
                        .reject { |person| EXCLUDED_HOLDER_STATUSES.include?(person.status) }
                        .sort_by { |person| person.callsign.to_s.downcase }
                        .map do |person|
                          held = documents_by_person[person.id]
                          {
                            person: person,
                            documents: held,
                            errors: document_errors(held, day_low, day_high)
                          }
                        end

      { people: people, day_low: day_low, day_high: day_high }
    end

    # Vet the arrival date on the document types that must carry one
    # (Staff Credential, SAP, SO SAP). Anytime access is always fine.
    # Public because TrsExport applies the same validation per document.
    #
    # @return [String, nil] the problem, or nil when the document is in order
    def access_date_problem(document, day_low, day_high)
      return nil unless AccessDocument::HAS_ACCESS_DATE_TYPES.include?(document.type)
      return nil if document.access_any_time

      access_date = document.access_date
      return "missing access date" if access_date.nil?

      current_year = Current.year
      if access_date.year < current_year
        return "access date [#{format_date(access_date)}] is less than current year [#{current_year}]"
      end

      day = access_date.day
      return nil if day >= day_low && day <= day_high

      "access date [#{format_date(access_date)}] outside day [#{day}] range low [#{day_low}], high [#{day_high}]"
    end

    # The allowable SC & SAP arrival days, read from the TAS_SAPDateRange
    # setting -- a "DD-DD" span of August days. Falls back to 5-26 when the
    # setting is unset or cannot be read as two day numbers.
    #
    # Deliberately not TicketingInfo#sap_selectable_dates: that one answers a
    # different question (the selectable Date objects) and returns an empty
    # list rather than falling back on unusable input.
    #
    # @return [Array<Integer>] the low and high day of the month
    def sap_day_range
      parts = Setting.get_value(Setting::TAS_SAP_DATE_RANGE).to_s.strip.split("-").map(&:strip)
      return [DEFAULT_DAY_LOW, DEFAULT_DAY_HIGH] unless parts.size == 2 && parts.all? { |part| part.match?(/\A\d+\z/) }

      [parts[0].to_i, parts[1].to_i]
    end

    private

    # Build the display-ready problem list for one person's documents.
    #
    # @return [Array<String>] e.g. [ "RAD-42 - missing access date" ]
    def document_errors(documents, day_low, day_high)
      documents.filter_map do |document|
        problem = access_date_problem(document, day_low, day_high)
        "RAD-#{document.id} - #{problem}" if problem
      end
    end

    def format_date(date)
      date.strftime("%Y-%m-%d %H:%M:%S")
    end
  end
end
