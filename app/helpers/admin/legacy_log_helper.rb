# frozen_string_literal: true

module Admin::LegacyLogHelper
  # What an empty table means depends on how the reader got here, as on the
  # raw Clubhouse 1 Log page, with one more case: a table no one has filled
  # yet.
  def legacy_log_empty_message(form, pagy)
    return "There is nothing on page #{pagy.page}. The entries run out before it." if pagy.page > 1
    return "No entries matched the current filters." if form.query_params.any?

    "The conversion has not run yet. Once a maintainer runs it, the Clubhouse 1 Log appears here in Action Log form."
  end

  # The lines under the Data block: the source row always; the session's
  # person when the statement named someone else; and whether the first
  # Clubhouse cut the statement.
  def legacy_log_detail_items(row)
    items = [["Clubhouse 1 Entry", "##{row.log_id}"]]
    if (session_person_id = row.session_person_id.presence)
      items << ["Session Person", person_display_link(row.session_person, session_person_id, blank: "-")]
    end
    items << ["Truncated", "Yes, the first Clubhouse cut this statement short"] if row.truncated?
    items
  end
end
