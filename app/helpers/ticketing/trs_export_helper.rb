# frozen_string_literal: true

module Ticketing::TrsExportHelper
  # Build a data: URI holding the export CSV. The CSV only exists on the one
  # POST render that stamped the export comments -- a GET could not re-derive
  # it -- so the download rides along inside the page, the same way the
  # application-import failure CSV does.
  def trs_csv_data_uri(csv_text)
    "data:text/csv;charset=utf-8,#{ERB::Util.url_encode(csv_text)}"
  end

  # The filter select choices: the ungrouped All first, then the upstream
  # optgroups, with the current selection baked in.
  def trs_filter_choices(selected)
    ungrouped, grouped = TrsExport::FILTER_GROUPS.partition { |group, _filters| group.nil? }
    plain = ungrouped.flat_map { |_group, filters| filters.map { |entry| [entry.label, entry.slug] } }
    groups = grouped.map { |group, filters| [group, filters.map { |entry| [entry.label, entry.slug] }] }

    safe_join([options_for_select(plain, selected), grouped_options_for_select(groups, selected)])
  end
end
