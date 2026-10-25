# frozen_string_literal: true

module Communication::AnnouncementsHelper
  ALL_FILTER_OPTION = UiComponents::FilterBarHelper::ALL_FILTER_OPTION

  FILTER_CHIP_LABELS = {
    audience: "Audience",
    status: "Status"
  }.freeze

  def announcement_audience_filter_options
    [ALL_FILTER_OPTION, *Motd::AUDIENCES.map { |value, audience| [audience[:label], value] }]
  end

  def announcement_status_filter_options
    [ALL_FILTER_OPTION, ["Active", "active"], ["Expired", "expired"]]
  end

  def announcement_sort_options
    [["Expiring last", "desc"], ["Expiring first", "asc"]]
  end

  # One filter_bar chip per active filter ("all" selections are inactive); each
  # URL drops that filter and keeps the rest. Sort is not a filter and gets no
  # chip, but it rides along so dropping a chip does not reshuffle the list.
  def announcement_filter_chips(filter_params)
    active = active_filters(filter_params.except(:sort))
    display = ->(key, value) { key == :audience ? Motd::AUDIENCES.dig(value, :label) || value : value.capitalize }
    sort = filter_params[:sort] == "asc" ? { sort: "asc" } : {}

    filter_chips(active, FILTER_CHIP_LABELS, value_label: display) do |remaining|
      communication_announcements_path(remaining.merge(sort))
    end
  end

  # The status of one announcement, as an icon-and-text badge so the meaning
  # does not rest on colour alone.
  def announcement_status_badge(announcement)
    if announcement.expired?
      ui_badge "Expired", :warning, icon: "clock", icon_type: :solid
    else
      ui_badge "Active", :success, icon: "circle-check", icon_type: :solid
    end
  end
end
