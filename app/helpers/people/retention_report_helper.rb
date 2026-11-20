# frozen_string_literal: true

module People::RetentionReportHelper
  FILTER_CHIP_LABELS = { status: "Status", last_year: "Last Rangered" }.freeze

  def retention_report_url(filters)
    filter_url(:people_retention_report_path, filters)
  end

  def retention_report_filter_chips(filter_params)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: method(:retention_report_chip_value)) do |remaining|
      retention_report_url(remaining)
    end
  end

  # Chips echo the words the page uses, not the raw param value.
  def retention_report_chip_value(key, value)
    case key
    when :last_year then retention_report_year_label(value)
    else value
    end
  end

  # One choice per year somebody's Rangering ended in, most recent first, so
  # the group the survey is aimed at sits at the top. Only years the report
  # holds are offered: a choice that can only return nothing is not a filter.
  #
  # matching: the counts the choice will actually deliver, since the status
  # filter narrows the roster this select navigates to. Ordering still comes
  # from the full counts, so the options do not reshuffle as status changes.
  def retention_report_year_options(counts, matching: nil)
    labels = matching || counts

    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      counts.sort_by { |year, _count| -year.to_i }
            .map { |year, _count| ["#{retention_report_year_label(year)} (#{labels.fetch(year, 0)})", year] }
  end

  def retention_report_year_label(year)
    (year == RetentionReport::NO_YEARS) ? RetentionReport::NO_YEARS_LABEL : year
  end

  # How many Rangers stopped after each of the last two events, for the count
  # boxes. Anyone earlier than that, and anyone with no credited year, is
  # counted together: the survey treats them the same.
  def retention_report_counts(report, counts)
    total = report.rows.size
    newest, prior = report.years.last(2).reverse
    rangered = counts.fetch(newest.to_s, 0)
    lapsed = counts.fetch(prior.to_s, 0)

    [
      [total.to_s, "Rangers in the report", :secondary],
      [rangered.to_s, "Rangered #{newest}", :success],
      [lapsed.to_s, "Last rangered #{prior}", :warning],
      [(total - rangered - lapsed).to_s, "Last rangered earlier", :secondary]
    ]
  end
end
