# frozen_string_literal: true

# The person page's permission table: a permission's status, and the paths
# that grant it (PersonPermissionPresenter::Row).
module Person::PermissionsHelper
  PERMISSION_PATH_ICONS = { manual: "user-pen", team: "people-group", position: "user-shield", conferred: "gear" }.freeze

  def permission_status(active)
    return ui_badge("deactivated", :secondary) unless active

    safe_join([fa_icon("circle-check", :solid, class: "icon-success", end: 1), "active"])
  end

  # One line per path, a position's conditions nested beneath it, and last the
  # setting holding the permission off.
  def permission_paths(row, nda_blocked: false)
    items = row.paths.map { |path| permission_path_item(path) }
    # The status comes from RoleManager's cached set and the paths are read
    # fresh, so until a purge refreshes the set the two can disagree.
    if row.active && row.paths.none?(&:confers?)
      items << ui_icon_item("clock-rotate-left", tone: "text-stone-icon") { "Still in effect from an earlier grant" }
    elsif !row.active && !nda_blocked && row.off_setting.nil? && row.paths.any?(&:confers?)
      items << ui_icon_item("clock-rotate-left", tone: "text-stone-icon") { "Granted, but not in effect yet" }
    end
    items << ui_icon_item("gear", tone: "text-stone-icon") { "Off while the #{row.off_setting_label} setting is off" } if row.off_setting
    tag.ul(safe_join(items), class: "space-y-1")
  end

  def permission_path_item(path)
    text = case path.kind
           when :manual then "Granted manually"
           when :team then "Team: #{path.title}"
           when :position then "Position: #{path.title}"
           when :conferred then "Comes with #{path.title} while the #{path.setting} setting is on"
           end
    icon = PERMISSION_PATH_ICONS.fetch(path.kind)
    return ui_icon_item(icon, tone: "text-stone-icon") { text } if path.conditions.empty?

    # ui_icon_item's own line, with the conditions nested in the same item so
    # a screen reader hears which position they belong to.
    line = tag.div(class: UiComponents::UiIconItemHelper::ITEM_CLASSES) do
      safe_join([fa_icon(icon, :solid, class: class_names("text-stone-icon", UiComponents::UiIconItemHelper::ICON_CLASSES)),
                 tag.span(text)])
    end
    tag.li(safe_join([line, permission_conditions(path)]))
  end

  # A position's conditions, as a list nested under its line.
  def permission_conditions(path)
    items = path.conditions.map do |condition|
      if condition.met
        ui_icon_item("circle-check", tone: "icon-success") { condition.text }
      else
        ui_icon_item("ban", :solid, tone: "text-stone-icon") { condition.text }
      end
    end
    tag.ul(safe_join(items), class: "ps-5")
  end
end
