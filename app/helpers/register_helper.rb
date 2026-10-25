# frozen_string_literal: true

# View helpers for the auditor registration page.
module RegisterHelper
  # The three things a reader is asked for, in order, and which step of the
  # page belongs to each. Steps not listed here -- the closed notice and the
  # finished account -- show no progress at all.
  REGISTER_STEP_TITLES = [
    "Why are you here?",
    "Before you register",
    "Your details"
  ].freeze

  REGISTER_STEP_POSITIONS = {
    "intent" => 0,
    "volunteer" => 1,
    "acknowledge" => 1,
    "form" => 2
  }.freeze

  # Shows how far along the page a reader is. Each step is numbered, the ones
  # already done carry a tick, and the one being read carries a mark of its own
  # and is named to a screen reader, so which step you are on never rests on
  # colour alone.
  def register_step_chips(step)
    current = REGISTER_STEP_POSITIONS[step]
    return if current.nil?

    tag.nav class: "flex flex-row flex-wrap gap-2 my-4", aria: { label: "Registration progress" } do
      safe_join(REGISTER_STEP_TITLES.each_with_index.map { |title, position|
        register_step_chip(title, position, current)
      })
    end
  end

  private

  def register_step_chip(title, position, current)
    label = "#{position + 1}. #{title}"

    if position == current
      ui_badge(label, :primary, size: "base", icon: "circle-dot", aria: { current: "step" })
    elsif position < current
      ui_badge(label, :secondary, size: "base", icon: "check")
    else
      ui_badge(label, :secondary, size: "base")
    end
  end
end
