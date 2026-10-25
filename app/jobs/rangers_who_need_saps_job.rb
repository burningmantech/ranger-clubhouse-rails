# frozen_string_literal: true

# Mails the list of Rangers who look like they still need a Setup Access Pass.
# Runs weekly through the last two months before the event, while there is still
# time to grant one.
class RangersWhoNeedSapsJob < ApplicationJob
  def perform
    return if Setting.get_value(Setting::TAS_SAP_REPORT_EMAIL).blank?

    year = Current.year
    RangersWhoNeedSapsMailer.notify(rows: SapCandidatesReport.execute(year),
                                    start_year: SapCandidatesReport.start_year(year)).deliver_now
  end
end
