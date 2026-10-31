# frozen_string_literal: true

module UiComponents
  # Match Stepper Helper
  # "Match 2 of 3" between a Previous and a Next button, joined: how a reader
  # walks a search's matches one at a time. Markup alone, drawn at the match
  # the page opens on. The Stimulus controller named by +controller+ answers
  # the two buttons with its #previous and #next and rewrites the count, its
  # "count" target: a polite status, which a screen reader announces as it
  # changes.
  #
  # The mailbox's pane pins it over the messages as they scroll
  # (common/messages/_messages_panel, search_matches_controller).
  #
  # Usage:
  #   <%= ui_match_stepper "search-matches", label: "Matches in this conversation", current: 1, total: 3 %>
  #
  module UiMatchStepperHelper
    # @param controller [String] the Stimulus identifier the buttons and the count belong to
    # @param label [String] the group's accessible name
    # @param current [Integer] the match shown first, counted from 1
    # @param total [Integer] how many there are
    def ui_match_stepper(controller, label:, current:, total:)
      tag.div(class: "join", role: "group", aria: { label: }) do
        safe_join([
          tag.span("Match #{current} of #{total}", class: button_classes({ class: "join-item pointer-events-none" }, :secondary),
                                                   role: "status", data: { "#{controller}-target": "count" }),
          match_step_button(controller, :previous, "chevron-up", "Previous match"),
          match_step_button(controller, :next, "chevron-down", "Next match")
        ])
      end
    end

    private

    def match_step_button(controller, action, icon, label)
      button_action "", :secondary, icon:, icon_type: :solid, class: "join-item btn-square",
                                    aria: { label: }, data: { action: "#{controller}##{action}" }
    end
  end
end
