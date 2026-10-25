# frozen_string_literal: true

module Certificates::CertificatesReportHelper
  FILTER_CHIP_LABELS = { status: "Status" }.freeze

  # Chip URLs point back at this certification's own page, so dropping a filter
  # keeps the reader on the roster they are reading.
  def certificates_report_filter_chips(filter_params, certification)
    active = active_filters(filter_params)

    filter_chips(active, FILTER_CHIP_LABELS) do |remaining|
      certificates_report_detail_path(certification, remaining)
    end
  end
end
