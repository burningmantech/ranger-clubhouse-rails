# frozen_string_literal: true

module Quartermaster::SwagHelper
  # Shirts predating the shirt type field have none, and the Ember table showed
  # a dash for them.
  def swag_shirt_type_label(swag)
    ShirtHelper::SHIRT_TYPE_LABELS[swag.shirt_type] || "—"
  end

  def swag_status_badge(swag)
    if swag.active
      ui_badge "Active", :success, icon: "circle-check", icon_type: :solid
    else
      ui_badge "Inactive", :warning, icon: "circle-xmark", icon_type: :solid
    end
  end

  # Deleting a swag takes its issued records with it, and a shirt also clears
  # itself from every Ranger who picked it. Both are silent, so the confirmation
  # spells out what goes.
  def swag_delete_message(swag, issued_count)
    parts = ["Delete \"#{swag.title}\"?"]

    if issued_count.positive?
      parts << "It will also be removed from the #{pluralize(issued_count, 'Ranger record')} it was issued on."
    end

    if swag.type == Swag::TYPE_DEPT_SHIRT
      parts << "Any Ranger who chose this shirt will have that choice cleared."
    end

    parts << "This cannot be undone."
    parts.join(" ")
  end
end
