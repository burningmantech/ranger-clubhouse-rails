# frozen_string_literal: true

module TeamsPositions
  # The bulk grant/revoke page's vocabulary: the position select's grouping, and
  # what each verdict looks and reads like in the preview table.
  module BulkPositionsHelper
    # The two directions, as the radio group draws them. Values match
    # TeamsPositions::BulkPositionsController::DIRECTIONS.
    DIRECTION_OPTIONS = [
      ["Grant the position", "grant"],
      ["Revoke the position", "revoke"]
    ].freeze

    # Per verdict: the pill's label and color, and the icon that carries the
    # same meaning without it -- status must never be color alone.
    VERDICT_BADGES = {
      grant: ["Will be granted", :success, "circle-plus"],
      revoke: ["Will be revoked", :warning, "circle-minus"],
      already_granted: ["No change", :secondary, "circle-check"],
      already_revoked: ["No change", :secondary, "circle-check"],
      duplicate: ["No change", :secondary, "clone"],
      not_found: ["Problem", :error, "triangle-exclamation"],
      ambiguous: ["Problem", :error, "triangle-exclamation"],
      self_change: ["Problem", :error, "triangle-exclamation"],
      blocked_status: ["Problem", :error, "triangle-exclamation"]
    }.freeze

    def bulk_position_badge(entry)
      label, color, icon = VERDICT_BADGES.fetch(entry.verdict)
      ui_badge label, color, icon:, icon_type: :solid
    end

    # The position select, grouped by team so a manager of several teams can
    # find the right one. Inactive positions are still offered -- upstream
    # offers them and a team can legitimately need one granted -- but the label
    # says so, because granting one by mistake is invisible afterwards.
    def bulk_position_options(positions, selected)
      # to_s first: a param can arrive array- or hash-shaped, and neither
      # answers to_i. Anything that is not a plain id selects nothing.
      grouped_options_for_select(position_choices_by_team(positions), selected.to_s.presence&.to_i)
    end

    # How wide the select's list is, said out loud. Upstream's only signal that
    # a manager reaches some positions and not others is the absence of the rest
    # from the list, which reads as a missing position rather than a boundary.
    #
    # Counted from the team_manager rows, not from the positions on offer: a
    # team with no positions, or whose positions were all filtered out, still
    # counts as a team you manage, and saying otherwise misstates your access.
    # The guarded-role filter is named for the same reason -- claiming the list
    # is complete when it is not sends the reader hunting for a deleted record.
    def bulk_positions_reach_hint
      reach = if Team.manages_every_team?(Current.person)
                "Every team's positions are listed."
              else
                teams = TeamManager.retrieve_team_ids_for_person(Current.person.id).size
                "Only the positions of the #{pluralize(teams, "team")} you manage are listed."
              end

      "#{reach} Positions granting Admin or Tech Ninja are left out unless you hold that role."
    end

    # The preview headline: says the position and the direction in words, before
    # anything is written. This sentence is the page's real guard against
    # granting when you meant to revoke.
    def bulk_position_preview_title(change)
      verb = change.grant? ? "Grant" : "Revoke"
      preposition = change.grant? ? "to" : "from"

      "#{verb} #{change.position.title} #{preposition} #{pluralize(change.changing.size, "person")}"
    end

    # What the final confirmation dialog says. Names the count and the direction
    # again: the dialog is the last thing read before anything is written.
    #
    # Revoking says the second consequence out loud, because it is the one the
    # reader cannot see coming: PersonPosition.remove_ids_from_person also
    # cancels every future sign-up for the position.
    def bulk_position_consequence(change)
      people = pluralize(change.changing.size, "person")

      if change.grant?
        "#{change.position.title} will be granted to #{people}. Everyone else on your list is left alone."
      else
        "#{change.position.title} will be revoked from #{people}, along with any shifts they have " \
          "already signed up for with it. Everyone else on your list is left alone."
      end
    end

    # What the apply actually did, on the page instead of only in a toast that
    # clips a long list and dismisses itself after six seconds.
    def bulk_position_outcome_headline(change, outcome)
      return "Nothing was changed." if outcome.changed.empty?

      verb = change.grant? ? "Granted" : "Revoked"
      preposition = change.grant? ? "to" : "from"

      "#{verb} #{change.position.title} #{preposition} #{pluralize(outcome.changed.size, "person")}."
    end

    # The detail behind the headline. Failures name the people so the reader can
    # retry them, but never the exception text -- that is already in the log,
    # and a raw Ruby or SQL message is not something to hand a manager.
    def bulk_position_outcome_detail(change, outcome)
      parts = []
      parts << "Changed: #{outcome.changed.map(&:callsign).to_sentence}." if outcome.changed.any?
      if outcome.failed?
        parts << "Could not be changed: #{outcome.failed.map(&:callsign).to_sentence} — " \
                 "the reason is in the log. Try those again."
      end
      parts << "#{pluralize(change.problems.size, "callsign")} could not be used." if change.problems.any?
      parts << "#{pluralize(change.skipping.size, "callsign")} already had the right state." if change.skipping.any?

      parts.compact_blank.join(" ")
    end
  end
end
