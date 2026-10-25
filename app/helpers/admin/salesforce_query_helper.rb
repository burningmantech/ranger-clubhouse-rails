# frozen_string_literal: true

module Admin::SalesforceQueryHelper
  # Past this many characters, or with a line break, a value wraps in a column
  # of its own width; anything shorter stays on one line.
  LONG_TEXT_LENGTH = 60
  # Whole class names, looked up with fetch -- never built by interpolation.
  VALUE_CLASSES = { long: "min-w-80 max-w-md whitespace-pre-line", short: "whitespace-nowrap" }.freeze

  # The count line, and the sentence the live region reads. Escaped here:
  # turbo_stream.update marks a plain String html_safe, so it would go out as
  # markup.
  #
  # @param query [SalesforceQuery] a query that has run
  # @return [ActiveSupport::SafeBuffer]
  def salesforce_query_summary(query)
    sentence =
      if query.error
        "The query did not run."
      elsif query.rows.any? && query.truncated?
        "#{number_with_delimiter(query.rows.size)} of #{pluralize(number_with_delimiter(query.total), 'record')}."
      elsif query.rows.any?
        "#{pluralize(number_with_delimiter(query.rows.size), 'record')}."
      elsif query.total.to_i.positive?
        # SELECT COUNT() answers with no records and the count in totalSize.
        "Salesforce counted #{pluralize(number_with_delimiter(query.total), 'record')}."
      elsif query.search?
        "Salesforce found no records for this search. Check the search term, then run it again."
      else
        "Salesforce returned no records for this query. Check the WHERE clause, then run it again."
      end

    ERB::Util.html_escape(sentence)
  end

  # Dev answers from canned data under SF_MOCK_DATA, and otherwise from the
  # live org with the dev database's production credentials -- the badge is how
  # anyone verifying the page tells the two apart.
  def salesforce_mock? = Salesforce.connector.is_a?(Salesforce::MockConnector)

  # A heading whose button sorts the rows already on the page
  # (table_sort_controller.js), with the look of BMID's server-side sort links.
  # A raw button by the owner's ruling (2026-10-05): ButtonHelper always makes
  # it a btn. aria-sort appears only once the column is sorted.
  def salesforce_query_heading(t, column, numeric:)
    t.heading(right: numeric, data: { sort_type: numeric ? "number" : "text" }) do
      tag.button(type: "button", class: Bmid::ManageHelper::SORT_LINK_CLASSES, data: { action: "table-sort#sort" }) do
        safe_join([tag.span(column), fa_icon("sort", :solid, class: "text-stone-subtle")])
      end
    end
  end

  def salesforce_query_cell(t, value, numeric:)
    case value
    when nil
      # data-sort-value "" sorts a null last in either direction.
      t.cell(right: numeric, data: { sort_value: "" }) do
        safe_join([tag.span("—", class: "text-stone-subtle", aria: { hidden: true }), tag.span("null", class: "sr-only")])
      end
    when SalesforceQuery::Children
      t.cell(pluralize(value.total, "record"), right: true, class: VALUE_CLASSES.fetch(:short),
             data: { sort_value: value.total })
    else
      # true/false, numbers and ISO dates exactly as Salesforce sent them
      text = value.to_s
      long = text.length > LONG_TEXT_LENGTH || text.include?("\n")
      t.cell(text, right: numeric, class: VALUE_CLASSES.fetch(long ? :long : :short))
    end
  end
end
