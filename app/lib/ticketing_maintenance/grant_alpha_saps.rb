# frozen_string_literal: true

module TicketingMaintenance
  # Grant claimed Setup Access Passes to Alphas and to prospectives signed up
  # for a training this year. Port of the Laravel GrantPasses.grantWAPsToAlphas.
  # Claimed, not qualified, on purpose: Alphas should not have to log in and
  # claim a pass themselves.
  class GrantAlphaSaps < GrantTask
    def self.title = "Grant Alpha SAPs"

    def self.description
      "Grant Setup Access Passes to Alphas, plus prospectives signed up for a training this year. " \
        "The SAPs are created as claimed."
    end

    def self.access_date = Setting.get_value(Setting::TAS_DEFAULT_ALPHA_SAP_DATE)

    def self.blocked_reason
      return if access_date.present?

      "The #{Setting::TAS_DEFAULT_ALPHA_SAP_DATE} setting (default Alpha SAP access date) is blank. " \
        "Set it before granting Alpha SAPs."
    end

    def self.card_note = "Default access date: #{access_date}"

    def self.people
      alpha_ids = Person.where(status: Person::ALPHA).select(:id)
      training_ids = Person.where(status: [Person::PROSPECTIVE, Person::ALPHA])
                           .joins(:slot)
                           .where(slot: { begins_year: Current.year, position_id: Position::TRAINING })
                           .select(:id)
      # A SAP cannot be banked, so CURRENT_STATUSES is the same set upstream
      # spelled out -- see the matching note in SapCandidatesReport.
      covered_ids = AccessDocument.where(type: AccessDocument::SAP,
                                         status: AccessDocument::CURRENT_STATUSES)
                                  .select(:person_id)

      Person.where(id: alpha_ids).or(Person.where(id: training_ids))
            .where.not(id: covered_ids)
            .order(:callsign)
            .select(:id, :callsign, :status)
    end

    def execute
      access_date = self.class.access_date
      granting(AccessDocument::SAP) do
        self.class.people.map do |person|
          grant_row(person,
                    type: AccessDocument::SAP,
                    status: AccessDocument::CLAIMED,
                    delivery_method: AccessDocument::DELIVERY_EMAIL,
                    access_date:,
                    detail: "access date #{access_date}")
        end
      end
    end
  end
end
