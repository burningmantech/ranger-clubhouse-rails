# frozen_string_literal: true

# Helper names are one shared pool across the whole app, so everything here is
# prefixed with the page it belongs to.
module People::StatusChangeRecommendationsHelper
  VINTAGE_YES = "yes"
  VINTAGE_NO = "no"
  VINTAGE_VALUES = [VINTAGE_YES, VINTAGE_NO].freeze

  # Everything a link on this page has to carry: the period being asked about,
  # and whatever filters are in force. Without them a drill link, a chip, or an
  # export would quietly hand back a different list than the one on screen.
  #
  # The current period is left out, because that is what an address with no
  # period means anyway.
  def status_change_query(period, filters = {}, **overrides)
    query = filters.merge(overrides)
    query[:period] = period if period == RecommendStatusChangeReport::PERIOD_NEXT
    query
  end

  # The two period buttons. The one being shown takes the brand colour, so the
  # pair reads as a choice with an answer rather than as two actions.
  def status_change_period_buttons(period, filters = {})
    RecommendStatusChangeReport::PERIODS.map do |candidate|
      variant = candidate == period ? :primary : :secondary
      button_link RecommendStatusChangeReport::PERIOD_LABELS[candidate], variant,
                  people_status_change_recommendations_path(status_change_query(candidate, filters)),
                  aria: { current: (candidate == period ? "page" : nil) }
    end
  end

  # What a number reads as when no one is in the group.
  def status_change_count(count) = pluralize(count, "person", plural: "people")

  # The vintage mark, said in words as well as shown, so the column does not
  # rely on a symbol alone.
  def status_change_vintage(vintage)
    return ui_badge("Vintage", :secondary, icon: "award", icon_type: :solid) if vintage

    tag.span("—", class: "text-stone-muted", aria: { label: "Not vintage" })
  end

  FILTER_LABELS = { status: "Current Status", vintage: "Vintage",
                    last_year: "Last year rangered" }.freeze

  # One chip per filter in force. Each chip's link drops just that filter and
  # keeps the rest.
  def status_change_chips(group, period, filters)
    filter_chips(filters, FILTER_LABELS, value_label: method(:status_change_filter_value)) do |rest|
      people_status_change_recommendations_group_path(group.key, status_change_query(period, rest))
    end
  end

  def status_change_filter_value(key, value)
    case key
    when :vintage then value == VINTAGE_YES ? "Marked" : "Not marked"
    else value
    end
  end

  # The confirm dialog, with the year being judged spelled into it. On the
  # forecast period that event has not happened yet, and this dialog is the
  # last place to say so before a change that cannot be undone.
  def status_change_confirm(group, year, period)
    tail = if period == RecommendStatusChangeReport::PERIOD_NEXT
             " This list is judged as if the #{year} event is over, and that event has not happened yet."
           else
             " This list is judged as if the #{year} event is over."
           end
    group.confirm.merge(message: group.confirm[:message] + tail)
  end

  def status_change_vintage_options
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION,
     ["Marked vintage", VINTAGE_YES],
     ["Not marked", VINTAGE_NO]]
  end

  def status_change_year_options(years)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] + years.map { |year| [year.to_s, year.to_s] }
  end
end
