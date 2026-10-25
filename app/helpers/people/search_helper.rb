# frozen_string_literal: true

# Chip labels, column descriptors, and cell formatting for People Search.
# Named people_search_* throughout -- helper methods share one global
# namespace, so nothing here can be spelled the way the controller is.
module People::SearchHelper
  YEARS_OP_LABELS = { "eq" => "exactly", "gte" => "at least", "lte" => "at most" }.freeze

  # Column keys whose value is a date/time rather than plain text.
  DATE_KEYS = %i[status_changed_at online_course_started online_course_finished
                 training_date training_signed_up_at ticketing_started_at
                 ticketing_finished_at created_at].freeze

  # Column keys holding a person status, rendered through the app's one status
  # vocabulary (person_status_badge) so "active" stays plain text and the
  # exceptions are the only coloured things in the column.
  STATUS_CELL_KEYS = %i[status current_status old_status new_status].freeze

  # A criteria category's disclosure title -- icon plus name. The card variant
  # bolds plain strings itself but leaves a SafeBuffer's weight alone, so the
  # markup an icon forces here has to carry its own.
  def people_search_category_title(icon, text)
    tag.span(safe_join([fa_icon(icon, :solid, end: 2), text]), class: "font-semibold")
  end

  # The subtitle under a category's title: what is set, or an invitation to
  # open it. Mirrors the Action Logs event-category disclosure, which is the
  # pattern this panel follows -- with the invitation dropped once the card is
  # already open, where "Show ... options" would be describing something the
  # reader is looking at.
  def people_search_category_subtitle(count, noun, open:)
    return "#{count} selected" if count.positive?

    "Show #{noun} options" unless open
  end

  # Extra-column checkboxes, year-prefixed where the column is year scoped.
  # The three checkboxes below are this year's snapshot; the other three are
  # not tied to a year at all. [key, label] order, matching what
  # common/checkbox_grid expects as its options: [value, label] pairs.
  def people_search_column_options
    year_scoped = %w[online_course training_status ticketing_info]

    PersonSearchForm::COLUMN_OPTIONS.map do |key, label|
      text = year_scoped.include?(key) ? "#{Current.year} #{label}" : label
      [key, text]
    end
  end

  # One chip per active criterion; each chip's URL is the search with that
  # one criterion dropped, everything else kept.
  def people_search_filter_chips(form)
    values = form.query_params[PersonSearchForm::PARAM_SCOPE] || {}
    chips = []

    if form.statuses.any?
      chips << { label: "Status: #{form.statuses.join(", ")}", url: people_search_chip_url(values, :statuses) }
    end

    if form.status_year_mode?
      chips << { label: "Updated During: #{form.status_year}", url: people_search_chip_url(values, :status_year) }
    end

    if form.years_worked.present?
      op = YEARS_OP_LABELS.fetch(form.years_worked_op, form.years_worked_op)
      chips << { label: "Years Rangered: #{op} #{form.years_worked}",
                url: people_search_chip_url(values, :years_worked, :years_worked_op) }
    end

    if form.photo_status.present?
      chips << { label: "Photo: #{form.photo_status}", url: people_search_chip_url(values, :photo_status) }
    end

    if form.online_course_status.present?
      chips << { label: "Online Course: #{form.online_course_status}",
                url: people_search_chip_url(values, :online_course_status) }
    end

    if form.training_status.present?
      chips << { label: "Training: #{form.training_status}",
                url: people_search_chip_url(values, :training_status) }
    end

    if form.ticketing_status.present?
      chips << { label: "Ticketing: #{form.ticketing_status}",
                url: people_search_chip_url(values, :ticketing_status) }
    end

    if form.year_created.to_i.positive?
      label = (form.year_created.to_i == PersonSearchForm::CREATED_PRIOR_SENTINEL) ? PersonSearchForm::CREATED_PRIOR_LABEL : form.year_created.to_s
      chips << { label: "Account Created: #{label}", url: people_search_chip_url(values, :year_created) }
    end

    if form.columns.any?
      chips << { label: "Columns: #{people_search_columns_chip_names(form.columns)}",
                url: people_search_chip_url(values, :columns) }
    end

    chips
  end

  # The dynamic table columns -- read by both the header row and every body
  # row, so the two can never drift out of step with each other.
  def people_search_columns(form)
    columns = []

    if form.status_year_mode?
      columns << { key: :current_status, heading: "Current Status" }
      columns << { key: :old_status, heading: "Old Status" }
      columns << { key: :new_status, heading: "Updated Status" }
      columns << { key: :status_changed_at, heading: "Status Updated On" }
    else
      columns << { key: :status, heading: "Status" }
    end

    columns << { key: :years_worked, heading: "Years Rangered", right: true } if form.show_years_worked?
    columns << { key: :photo_status, heading: "Photo Status" } if form.show_photo_status?

    if form.show_online_course?
      columns << { key: :online_course_started, heading: "Online Course Started" }
      columns << { key: :online_course_finished, heading: "Online Course Completed" }
    end

    if form.show_training_status?
      columns << { key: :training_status, heading: "Training Status" }
      columns << { key: :training_date, heading: "Training Date" }
      columns << { key: :training_signed_up_at, heading: "Signed-Up At" }
    end

    if form.show_ticketing_info?
      columns << { key: :ticketing_started_at, heading: "Ticketing Started" }
      columns << { key: :ticketing_finished_at, heading: "Ticketing Finished" }
    end

    columns << { key: :created_at, heading: "Account Created" } if form.show_created_at?

    columns
  end

  # The value a column key reads off a result row, before any formatting.
  def people_search_raw_value(row, key)
    case key
    when :current_status, :status then row.person.status
    when :old_status then row.old_status
    when :new_status then row.new_status
    when :created_at then row.person.created_at
    else row.public_send(key)
    end
  end

  # A results table cell: statuses go through the shared badge vocabulary,
  # dates keep their column-stable width, everything else prints as text with
  # blanks as a dash.
  def people_search_cell(row, column)
    key = column[:key]
    if STATUS_CELL_KEYS.include?(key)
      value = people_search_raw_value(row, key)
      return value.present? ? person_status_badge(value) : value_or_dash(nil)
    end

    people_search_display(row, key)
  end

  # The value as shown on screen: dates in ymd form, blanks as a dash.
  def people_search_display(row, key)
    value_or_dash(people_search_csv_value(row, key))
  end

  # The value for a CSV cell: dates in ymd form, blanks left empty rather
  # than carrying the on-screen dash.
  #
  # Dates are read back on the clock they were stored on. Stored times are
  # machine local while the app reads in Phoenix time, so between November and
  # March a late-evening time would otherwise print as the following day --
  # and a search would show a date outside the very year it matched on.
  def people_search_csv_value(row, key)
    value = people_search_raw_value(row, key)
    return value unless DATE_KEYS.include?(key)

    ymd_format(value.respond_to?(:getlocal) ? value.getlocal : value)
  end

  private

  # The chip names its columns instead of counting them, so the collapsed
  # panel does not ask the reader to remember what they ticked. Past three,
  # the tail folds into a count.
  def people_search_columns_chip_names(columns)
    labels = PersonSearchForm::COLUMN_OPTIONS.to_h
    names = columns.map { |key| labels.fetch(key, key) }
    return names.join(", ") if names.size <= 3

    "#{names.first(2).join(", ")}, +#{names.size - 2} more"
  end

  def people_search_chip_url(values, *drop_keys)
    remaining = values.except(*drop_keys)
    remaining.present? ? people_search_path(filter: remaining) : people_search_path
  end
end
