# frozen_string_literal: true

module Admin::Clubhouse1LogHelper
  CLUBHOUSE1_LOG_FILTER_CHIP_LABELS = {
    user_callsign: "User",
    target_callsign: "Target",
    start_time: "From",
    end_time: "Until",
    event_text: "Contains",
    sort: "Sort"
  }.freeze

  # One filter_bar chip per active filter, plus one per chosen event category.
  # Each URL drops that one filter and keeps the rest.
  def clubhouse1_log_filter_chips(form)
    values = form.query_params[Clubhouse1LogFilterForm::PARAM_SCOPE]&.except(:page) || {}
    active = values.slice(*CLUBHOUSE1_LOG_FILTER_CHIP_LABELS.keys)
    display = ->(key, value) { clubhouse1_log_chip_value(form, key, value) }

    # The chip URLs drop the field from the whole values hash rather than from
    # the sliced one, so the chosen categories survive.
    field_chips = filter_chips(active, CLUBHOUSE1_LOG_FILTER_CHIP_LABELS, value_label: display) do |_remaining, key|
      admin_clubhouse1_log_path(clubhouse1_log_chip_params(values.except(key)))
    end

    category_chips = form.event_categories.map do |key|
      remaining = values.merge(event_categories: form.event_categories - [key])
      { label: "Events: #{Clubhouse1LogFilterForm::CATEGORY_LABELS.fetch(key, key)}",
        url: admin_clubhouse1_log_path(clubhouse1_log_chip_params(remaining)) }
    end

    field_chips + category_chips
  end

  # What an empty table means depends on how the reader got here: a search that
  # matched nothing, a page past the last entry, or simply a log with no
  # entries at all. Saying "no entries matched the filters" when none were set
  # sends the reader looking for a filter to clear.
  def clubhouse1_log_empty_message(form, pagy)
    return "There is nothing on page #{pagy.page}. The entries run out before it." if pagy.page > 1
    return "No entries matched the current filters." if form.query_params.any?

    "The Clubhouse 1 Log holds no entries."
  end

  # The log names people by id. Tech Ninjas can read this page but not the
  # person pages, so person_display_link gives them the callsign without a link
  # that would only bounce them back to their own page.
  #
  # A zero means the same as no id at all -- the first Clubhouse wrote both for
  # an action with no one on the other end -- and it has to be turned into one,
  # or 37,000 entries would each claim a person who was never deleted because
  # they never existed.
  def clubhouse1_log_person_label(person, person_id)
    person_display_link(person, person_id.to_i.zero? ? nil : person_id, blank: "-")
  end

  private

  def clubhouse1_log_chip_value(form, key, value)
    case key
    when :start_time, :end_time then clubhouse1_log_chip_time(form, key)
    when :sort then Clubhouse1LogFilterForm::SORT_OPTIONS.rassoc(value)&.first || value
    else value
    end
  end

  def clubhouse1_log_chip_time(form, key)
    parsed = (key == :start_time) ? form.parsed_start_time : form.parsed_end_time
    parsed ? parsed.strftime(DateTimeHelper::CHIP_TIME) : form.public_send(key)
  end

  def clubhouse1_log_chip_params(values)
    cleaned = values.reject { |_key, value| value.blank? }
    cleaned.empty? ? {} : { Clubhouse1LogFilterForm::PARAM_SCOPE => cleaned }
  end
end
