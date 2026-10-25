# frozen_string_literal: true

module Vc::ApplicationImportHelper
  FAILURE_CSV_HEADER = [
    "Salesforce ID", "First Name", "Last Name", "Application Object ID", "Contact Object ID", "Error", "Details"
  ].freeze

  APPLICATION_CSV_HEADER = [
    "Clubhouse ID", "Salesforce ID", "First Name", "Last Name", "Email", "Status"
  ].freeze

  # Same data: URI trick as the failure tables — the preview rows are unsaved
  # and only exist on this one render, so the download rides along in the page.
  #
  # @param applications [Array<ProspectiveApplication>]
  # @return [String]
  def applications_csv_data_uri(applications)
    rows = applications.map do |application|
      [
        (application.application_id if application.persisted?),
        application.salesforce_name,
        application.first_name,
        application.last_name,
        application.email,
        ProspectiveApplication::STATUS_LABELS[application.status] || application.status
      ]
    end

    csv_data_uri([APPLICATION_CSV_HEADER, *rows])
  end

  # Build a data: URI holding the failure rows as CSV. The results only
  # exist on this one POST render — a CSV route would have to re-run the
  # whole Salesforce pull — so the download rides along inside the page.
  #
  # @param failures [Array<ProspectiveApplicationImport::Failure>]
  # @return [String]
  def failures_csv_data_uri(failures)
    rows = failures.map do |failure|
      application = failure.application
      [
        application.salesforce_name,
        application.first_name,
        application.last_name,
        application.salesforce_id,
        failure.contact_id,
        failure.label,
        failure.message
      ]
    end

    csv_data_uri([FAILURE_CSV_HEADER, *rows])
  end

  private

  def csv_data_uri(rows)
    "data:text/csv;charset=utf-8,#{ERB::Util.url_encode(CsvExportConcern.build(rows))}"
  end
end
