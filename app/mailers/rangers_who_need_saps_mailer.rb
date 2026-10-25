# frozen_string_literal: true

# The nightly twin of the Ticketing > SAP Candidates page. Rows come from
# SapCandidatesReport, so the email and the page can never disagree:
#
#   RangersWhoNeedSapsMailer.notify(rows: SapCandidatesReport.execute(year),
#                                   start_year: SapCandidatesReport.start_year(year))
#
# Nothing schedules this yet.
class RangersWhoNeedSapsMailer < ApplicationMailer
  def notify(rows:, start_year:)
    liquid_assigns.merge!(
      start_year: start_year,
      report_date: Date.current.strftime("%Y-%m-%d"),
      rows: rows.map { |row| row_values(row) }
    )

    mail(
      from: vc_from,
      to: build_addresses(Setting.get_value(Setting::TAS_SAP_REPORT_EMAIL)),
      subject: liquid_subject
    )
  end

  private

  def row_values(row)
    {
      callsign: row.person.callsign,
      person_url: person_url(row.person),
      status: row.person.status,
      has_spt: row.has_spt,
      years: row.years || [],
      tickets: row.tickets.map do |ticket|
        { reference: ticket.display_ref, type_label: ticket.short_type_label, status: ticket.status }
      end,
      schedule: row.schedule.map do |signup|
        { begins_label: signup.begins_label, position_title: signup.position_title,
          description: signup.description }
      end
    }
  end
end
