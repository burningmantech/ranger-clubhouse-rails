# frozen_string_literal: true

module PageLayoutHelper
  # The all-years choice offered by year selectors built with include_all.
  # Controllers that honour it must catch this exact string in setup_year --
  # the shared validation coerces anything else to the current year.
  ALL_YEARS = "All"

  def page_title(title, &block)
    title_div = content_tag :h1, title, class: "text-3xl font-normal"
    return content_tag(:div, title_div, class: "mb-4") unless block_given?

    # Back link appears above title in breadcrumb style
    content_tag :div, class: "mb-4" do
      concat content_tag(:div, capture(&block), class: "mb-1")
      concat title_div
    end
  end

  def render_for_user(action, locals = {}, status = nil)
    locals[:person] = current_user
    options = {
      locals:
    }
    if status
      options[:status] = status
    end

    render action, options
  end

  def render_partial_for_user(partial, locals = {})
    locals[:person] = current_user
    render partial: partial.to_s, locals: locals
  end

  def year_selector(year, options = {})
    year = current_year if year.blank?
    year_options = year_options(options)

    content_tag :div do
      form_tag false, method: :get, data: { controller: "form" } do
        content_tag(:div, class: AppFormBuilder::HORIZONTAL_WRAPPER_CLASSES) do
          content_tag(:label,
                      "Select the year to view:",
                      for: "year-selector",
                      class: AppFormBuilder::HORIZONTAL_LABEL_CLASSES) +
            content_tag(:div) do
              select_tag(:year,
                         options_for_select(year_options, year),
                         id: "year-selector",
                         class: AppFormBuilder::SELECT_CLASSES,
                         data: { action: "change->form#submit" })
            end
        end + year_selector_keep_fields(options)
      end
    end
  end

  # Compact year selector for inline display in hero panels (desktop)
  # Uses shorter label "Year:" and compact styling
  def year_selector_compact(year, options = {})
    year = current_year if year.blank?
    year_options = year_options(options)
    selector_id = "year-selector-compact"

    form_tag false, method: :get, data: { controller: "form" }, class: "flex items-center gap-2" do
      content_tag(:label,
                  "Year to view:",
                  for: selector_id,
                  class: "text-lg font-medium text-stone-emphasis whitespace-nowrap") +
        select_tag(:year,
                   options_for_select(year_options, year),
                   id: selector_id,
                   class: "select select-sm w-auto",
                   aria: { label: "Select year to view" },
                   data: { action: "change->form#submit" }) +
        year_selector_keep_fields(options)
    end
  end

  # The selector posts an action-less GET carrying only :year, so every other
  # query param on the page -- a filter, a view, a search -- is dropped the
  # moment the reader changes year. Pages with such params pass them as
  # keep: { view: @view, ... } and get them back as hidden fields.
  def year_selector_keep_fields(options)
    keep = options[:keep]
    return "".html_safe if keep.blank?

    safe_join(keep.compact_blank.flat_map do |name, value|
      # A filter holding several values needs a field apiece, named so the page
      # reads them back as a list. One field carrying the whole array would
      # arrive as the string the array prints as, which matches nothing.
      if value.is_a?(Array)
        value.map { |item| hidden_field_tag("#{name}[]", item, id: nil) }
      else
        hidden_field_tag(name, value, id: nil)
      end
    end)
  end

  def title_year_selector(title, year, options = {}, &block)
    "#{page_title("#{year} #{title}", &block)}#{year_selector(year, options)}".html_safe
  end

  private

  def year_options(options)
    this_year = current_year
    years = options[:years]
    min_year = options[:min_year] || 1998
    skip_pandemic = options[:skip_pandemic]
    include_current_year = options.fetch(:include_current_year, true)
    include_year_argument = options.fetch(:include_year_argument, true)

    # Build list of years if not provided
    if years.nil?
      years = skip_pandemic ? EventYearSpan.years(min_year, this_year) : (min_year..this_year).to_a
    else
      years = years.dup
    end

    # Ensure current_year is included
    years << current_year if include_current_year && !years.include?(current_year)

    # Ensure a specific :year argument is included
    year_arg = options[:year]
    if include_year_argument && year_arg && year_arg != ALL_YEARS && !years.include?(year_arg.to_i)
      years << year_arg
    end

    # Descending sort
    years.sort! { |a, b| b <=> a }

    # Add "All" at end if requested
    years << ALL_YEARS if options[:include_all]

    years
  end
end
