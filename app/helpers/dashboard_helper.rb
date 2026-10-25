module DashboardHelper
  # Badge configuration by status (text, variant, and accessible label)
  STEP_BADGES = {
    DashboardTask::STATUS_COMPLETED => { text: "completed", variant: :success, aria_label: "Status: Task completed" },
    DashboardTask::STATUS_URGENT => { text: "urgent", variant: :error, aria_label: "Status: Urgent action required" },
    DashboardTask::STATUS_ACTION_NEEDED => { text: "action needed", variant: :warning, aria_label: "Status: Action needed" },
    DashboardTask::STATUS_WAITING => { text: "pending", variant: :secondary, aria_label: "Status: Pending" },
    DashboardTask::STATUS_NOT_AVAILABLE => { text: "not available yet", variant: :secondary, aria_label: "Status: Not available yet" },
    DashboardTask::STATUS_OPTIONAL => { text: "optional", variant: :secondary, aria_label: "Status: Optional task" },
    DashboardTask::STATUS_BLOCKED => { text: "blocked", variant: :error, aria_label: "Status: Blocked" }
  }.freeze

  # Icon configuration by status
  STEP_ICONS = {
    DashboardTask::STATUS_COMPLETED => { name: "circle-check", style: :solid },
    DashboardTask::STATUS_WAITING => { name: "hourglass-half", style: :solid },
    DashboardTask::STATUS_ACTION_NEEDED => { name: "arrow-right", style: :solid },
    DashboardTask::STATUS_NOT_AVAILABLE => { name: "circle", style: :regular },
    DashboardTask::STATUS_URGENT => { name: "triangle-exclamation", style: :solid },
    DashboardTask::STATUS_BLOCKED => { name: "circle-xmark", style: :solid },
    DashboardTask::STATUS_OPTIONAL => { name: "circle-info", style: :solid },
    DashboardTask::STATUS_NOTE => { name: "hand-point-right", style: :regular }
  }.freeze

  def dashboard_step_status_class(result)
    case result
    when DashboardTask::STATUS_COMPLETED then "text-success"
    when DashboardTask::STATUS_URGENT then "text-error"
    when DashboardTask::STATUS_ACTION_NEEDED then "text-primary"
    when DashboardTask::STATUS_WAITING, DashboardTask::STATUS_NOT_AVAILABLE then "text-stone-muted"
    when DashboardTask::STATUS_OPTIONAL then "text-secondary"
    when DashboardTask::STATUS_BLOCKED then "text-error"
    else ""
    end
  end

  def dashboard_step_badge(result)
    config = STEP_BADGES[result]
    return "" unless config

    extra_class = (result == DashboardTask::STATUS_ACTION_NEEDED) ? "animate-pulse" : ""
    ui_badge(config[:text], config[:variant], size: "sm", class: extra_class, "aria-label": config[:aria_label])
  end

  def dashboard_step_icon(result)
    config = STEP_ICONS[result]
    return "bug #{result}" unless config

    icon_class = case result
                 when DashboardTask::STATUS_COMPLETED then "icon-success"
                 when DashboardTask::STATUS_ACTION_NEEDED then "icon-warning"
                 when DashboardTask::STATUS_URGENT then "icon-error"
                 when DashboardTask::STATUS_BLOCKED then "icon-error"
                 else "text-stone-muted"
                 end

    fa_icon(config[:name], config[:style], { end: 2, class: icon_class })
  end

  # Get icon name for accent card helper
  def dashboard_step_icon_name(result)
    config = STEP_ICONS[result]
    config ? config[:name] : nil
  end

  # Get icon style for accent card helper
  def dashboard_step_icon_type(result)
    config = STEP_ICONS[result]
    config ? config[:style] : :solid
  end

  def dashboard_resolve_path(route_path)
    return "#" if route_path.blank?

    if respond_to?(route_path)
      send(route_path)
    else
      route_path
    end
  end

  # Determine icon for section based on title
  def dashboard_section_icon(title)
    case title
    when /Preparation|Before/i then "sun"
    when /IMMEDIATE|Urgent/i then "triangle-exclamation"
    when /Event|During/i then "campground"
    when /Completed/i then "circle-check"
    when /Setup|Account/i then "user-gear"
    when /Train/i then "graduation-cap"
    when /Alpha|Attend/i then "person-walking"
    when /Note/i then "circle-info"
    when /Off.?Season|After/i then "snowflake"
    when /Post.?Event/i then "clipboard-check"
    else "clipboard-list"
    end
  end

  # Map dashboard step result to accent card variant
  def dashboard_step_variant(result)
    case result
    when DashboardTask::STATUS_COMPLETED then :success
    when DashboardTask::STATUS_URGENT, DashboardTask::STATUS_BLOCKED then :error
    when DashboardTask::STATUS_ACTION_NEEDED then :warning
    when DashboardTask::STATUS_OPTIONAL, DashboardTask::STATUS_NOTE then :info
    else :secondary
    end
  end
end
