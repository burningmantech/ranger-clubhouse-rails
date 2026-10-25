# frozen_string_literal: true

module AgreementHelper
  # Agreement status to accent border and tint. These cards are accent cards by
  # hand, so they take ui_accent_card's own values -- BORDER_VARIANTS and
  # BG_VARIANTS, spelled the same way -- and follow the theme with them, which a
  # green-500 never could. The border is non-directional because the card sets
  # its width with border-l-4; only the left edge is drawn.
  BORDER_COLORS = {
    signed: "border-success/30",
    pending: "border-warning/30",
    not_available: "border-l-secondary"
  }.freeze

  BG_COLORS = {
    signed: "bg-success/10",
    pending: "bg-warning/10",
    not_available: "bg-base-200"
  }.freeze

  # Badge configuration by status
  BADGES = {
    signed: { text: "signed", variant: :success, aria_label: "Status: Agreement signed" },
    pending: { text: "action needed", variant: :warning, aria_label: "Status: Action needed" },
    not_available: { text: "coming soon", variant: :secondary, aria_label: "Status: Not available yet" }
  }.freeze

  # Icon configuration by status
  ICONS = {
    signed: { name: "circle-check", style: :solid },
    pending: { name: "pen-to-square", style: :solid },
    not_available: { name: "clock", style: :solid }
  }.freeze

  def agreement_status(agreement)
    if agreement.signed
      :signed
    elsif agreement.available
      :pending
    else
      :not_available
    end
  end

  def agreement_border_class(agreement)
    BORDER_COLORS.fetch(agreement_status(agreement))
  end

  def agreement_bg_class(agreement)
    BG_COLORS.fetch(agreement_status(agreement))
  end

  def agreement_badge(agreement)
    status = agreement_status(agreement)
    config = BADGES.fetch(status)

    extra_class = status == :pending ? "animate-pulse" : ""
    ui_badge(config[:text], config[:variant], size: "sm", class: extra_class, "aria-label": config[:aria_label])
  end

  def agreement_icon(agreement)
    status = agreement_status(agreement)
    config = ICONS.fetch(status)

    icon_class = case status
                 when :signed then "icon-success"
                 when :pending then "icon-warning"
                 else "text-secondary"
                 end

    fa_icon(config[:name], config[:style], { class: icon_class })
  end
end
