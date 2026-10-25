# frozen_string_literal: true

module TicketingMaintenance
  # Grant a Setup Access Pass to every Ranger the SAP candidates report says
  # still needs one. Port of the Laravel GrantPasses.grantWAPsToRangers; the
  # candidate selection is SapCandidatesReport, already a faithful port of
  # findRangersWhoNeedWAPs (rangered recently or signed up this year, not
  # covered by a SAP or Staff Credential, holding an SPT or signed up).
  class GrantSaps < GrantTask
    def self.title = "Grant Ranger SAPs"

    def self.description
      "Grant Setup Access Passes to active or inactive Rangers who don't have one already " \
        "and who rangered in the last three events or are signed up for this one."
    end

    def self.access_date = Setting.get_value(Setting::TAS_DEFAULT_SAP_DATE)

    def self.blocked_reason
      return if access_date.present?

      "The #{Setting::TAS_DEFAULT_SAP_DATE} setting (default SAP access date) is blank. " \
        "Set it before granting SAPs."
    end

    def self.card_note = "Default access date: #{access_date}"

    def execute
      access_date = self.class.access_date
      granting(AccessDocument::SAP) do
        SapCandidatesReport.execute(current_year).map do |candidate|
          grant_row(candidate.person,
                    type: AccessDocument::SAP,
                    status: AccessDocument::QUALIFIED,
                    delivery_method: AccessDocument::DELIVERY_EMAIL,
                    access_date:,
                    detail: "access date #{access_date}")
        end
      end
    end
  end
end
