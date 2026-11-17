# frozen_string_literal: true

# The person page's permission tables: the paths that grant a permission, and
# why an inactive one is not in effect (PersonPermissionPresenter::Row).
module Person::PermissionsHelper
  PERMISSION_PATH_ICONS = { manual: "user-pen", team: "people-group", position: "user-shield", conferred: "gear" }.freeze

  # Everything holding the permission off, most sweeping first: the unsigned
  # policy, the setting, then each position whose conditions are unmet. A
  # position is named with its conditions, since meeting any one position's
  # is enough.
  def permission_inactive_reasons(row, nda_blocked: false)
    items = []
    items << ui_icon_item("ban", :solid, tone: "text-stone-icon") { "Sensitive Data Access and Use Policy not signed" } if nda_blocked
    items << ui_icon_item("gear", tone: "text-stone-icon") { "#{row.off_setting_label} setting is off" } if row.off_setting
    if row.paths.none?(&:confers?)
      blocked = row.paths.uniq
      items << tag.li("Any one of these would make it active:") if blocked.many?
      items.concat(blocked.map { |path| permission_path_item(path.with(conditions: path.conditions.reject(&:met))) })
    elsif items.empty?
      # RoleManager's set is cached and the paths are read fresh, so until a
      # purge refreshes the set a path can confer what is not in effect yet.
      items << ui_icon_item("clock-rotate-left", tone: "text-stone-icon") { "Granted, but not in effect yet" }
    end
    return value_or_dash(nil) if items.empty?

    tag.ul(safe_join(items), class: "space-y-1")
  end

  # One line per path, a position's conditions nested beneath it.
  def permission_paths(row)
    items = row.paths.map { |path| permission_path_item(path) }
    # RoleManager's set is cached and the paths are read fresh, so until a
    # purge refreshes the set it can hold what no path confers any longer.
    if row.active && row.paths.none?(&:confers?)
      items << ui_icon_item("clock-rotate-left", tone: "text-stone-icon") { "Still in effect from an earlier grant" }
    end
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
