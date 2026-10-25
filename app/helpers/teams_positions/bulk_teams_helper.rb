# frozen_string_literal: true

module TeamsPositions
  # The bulk team grant/revoke page's vocabulary: the team select's grouping,
  # what each verdict looks and reads like in the preview table, and the
  # sentences that name the positions a membership carries with it.
  #
  # Every method here keeps the page's prefix. Helper modules share one
  # namespace on the view context, so a bare `badge` or `consequence` would
  # silently replace the Bulk Positions page's.
  module BulkTeamsHelper
    # The two directions, as the radio group draws them. Values match
    # TeamsPositions::BulkTeamsController::DIRECTIONS.
    DIRECTION_OPTIONS = [
      ["Grant team membership", "grant"],
      ["Revoke team membership", "revoke"]
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

    # Group order for the select, rather than alphabetical: a cadre and a
    # delegation are different kinds of thing from a team, and an admin sees
    # every one of them in a single list. The headings themselves come from
    # team_record_type_label, so the Team Records page and this select cannot
    # end up calling the same kind of record by different names.
    TYPE_ORDER = [Team::TYPE_TEAM, Team::TYPE_CADRE, Team::TYPE_DELEGATION].freeze

    def bulk_team_badge(entry)
      label, color, icon = VERDICT_BADGES.fetch(entry.verdict)
      ui_badge label, color, icon:, icon_type: :solid
    end

    # The team select, grouped by kind. Inactive teams are still offered --
    # upstream offers them, and a team stood down for the season can
    # legitimately need a membership moved -- but the label says so, because
    # granting one by mistake is invisible afterwards.
    def bulk_team_options(teams, selected)
      by_type = teams.group_by(&:type)
      # Known kinds first, then anything else. A type this list does not name
      # keeps its own group rather than vanishing from the select: team.type is
      # a plain string column -- not an enum, and on a table the Laravel app
      # also writes -- so the three above are a convention, not a guarantee. A
      # team missing from the only page that can grant it reads as a deleted
      # record, which is a worse failure than an odd heading.
      ordered = TYPE_ORDER + (by_type.keys - TYPE_ORDER).sort

      grouped = ordered.filter_map do |type|
        listed = by_type[type]
        next if listed.blank?

        [team_record_type_label(type).pluralize,
         listed.map { |team| [title_marking_inactive(team), team.id] }]
      end

      # to_s first: a param can arrive array- or hash-shaped, and neither
      # answers to_i. Anything that is not a plain id selects nothing.
      grouped_options_for_select(grouped, selected.to_s.presence&.to_i)
    end

    # How wide the select's list is, said out loud. Upstream's only signal that
    # a manager reaches some teams and not others is the absence of the rest
    # from the list, which reads as a missing team rather than a boundary.
    #
    # Says what is listed without counting it. A count had to come from
    # somewhere, and every source disagreed with the select in some case:
    # team_manager rows carry no unique index (the Laravel app writes that table
    # too, so a duplicate row promised three teams above a list of two), and
    # counting the listed teams called a cadre a team -- the very thing
    # team_record_type_label exists to stop, right above a select that groups
    # them apart. The list itself is the honest answer to "how many".
    #
    # The guarded caveat covers both narrowing rules: a team whose own
    # membership confers Admin or Tech Ninja is missing entirely, and one that
    # confers them through a position is listed but cannot be granted.
    def bulk_teams_reach_hint
      reach = if Team.manages_every_team?(Current.person)
                "Listing every team, cadre, and delegation."
              else
                "Listing only the teams, cadres, and delegations you manage."
              end

      "#{reach} One granting Admin or Tech Ninja is either left out or cannot be granted " \
        "here — move those memberships one person at a time from their own page."
    end

    # The preview headline: says the team and the direction in words, before
    # anything is written. This sentence is the page's real guard against
    # granting when you meant to revoke.
    def bulk_team_preview_title(change)
      verb = change.grant? ? "Grant" : "Revoke"
      preposition = change.grant? ? "to" : "from"

      "#{verb} #{change.team.title} #{preposition} #{pluralize(change.changing.size, "person")}"
    end

    # The positions a membership carries with it, named. This is the part of the
    # operation no one can see coming from the form: the reader chose a team,
    # and positions move too.
    #
    # Says "anyone who holds"/"does not already hold" rather than promising the
    # change for everyone, because both writers skip the ids that would be
    # no-ops -- a member holding none of these loses only the membership.
    #
    # "Upcoming" is load-bearing: the sign-up sweep is scoped to this year's
    # future slots, so last year's shifts and next year's are both left alone.
    def bulk_team_position_effect(change)
      positions = change.moved_positions
      return bulk_team_no_positions(change) if positions.empty?

      titles = positions.map { |position| title_marking_inactive(position) }.to_sentence
      pronoun = positions.many? ? "them" : "it"

      return "Also grants #{titles} to anyone who does not already hold #{pronoun}." if change.grant?

      "Also revokes #{titles} from anyone who holds #{pronoun}, along with their upcoming " \
        "shifts for #{positions.many? ? "those positions" : "that position"}."
    end

    # What the final confirmation dialog says. Names the count, the direction,
    # and the positions again: the dialog is the last thing read before anything
    # is written.
    def bulk_team_consequence(change)
      people = pluralize(change.changing.size, "person")
      verb = change.grant? ? "granted to" : "revoked from"

      "#{change.team.title} will be #{verb} #{people}. #{bulk_team_position_effect(change)} " \
        "Everyone else on your list is left alone."
    end

    # The colour and icon the results banner wears, per verdict. Kept out of the
    # view because "did this work?" has three answers, not two: a write that
    # raised, a list where nothing could be used, and a clean run.
    OUTCOME_ICONS = {
      error: "triangle-exclamation",
      warning: "circle-exclamation",
      success: "circle-check"
    }.freeze

    # Success is reserved for a run that changed something and left nothing
    # needing attention. Anything else is amber or red, because the banner's
    # colour is what a reader scanning the page acts on.
    def bulk_team_outcome_banner(change, outcome)
      variant = if outcome.failed?
                  :error
                elsif outcome.changed.empty? || change.problems.any?
                  :warning
                else
                  :success
                end

      [variant, OUTCOME_ICONS.fetch(variant)]
    end

    # What the apply actually did, on the page instead of only in a toast that
    # clips a long list and dismisses itself after six seconds.
    def bulk_team_outcome_headline(change, outcome)
      return "Nothing was changed." if outcome.changed.empty?

      verb = change.grant? ? "Granted" : "Revoked"
      preposition = change.grant? ? "to" : "from"

      "#{verb} #{change.team.title} #{preposition} #{pluralize(outcome.changed.size, "person")}."
    end

    # The detail behind the headline. Failures name the people so the reader can
    # retry them, but never the exception text -- that is already in the log,
    # and a raw Ruby or SQL message is not something to hand a manager.
    def bulk_team_outcome_detail(change, outcome)
      parts = []
      parts << "Changed: #{outcome.changed.map(&:callsign).to_sentence}." if outcome.changed.any?
      if outcome.failed?
        parts << "Could not be changed: #{outcome.failed.map(&:callsign).to_sentence} — " \
                 "the reason is in the log. Try those again."
      end
      # Named, not just counted: the apply re-renders the form, so the per-line
      # table that identified each bad callsign is no longer on the page. A bare
      # count would send the reader back through the preview to find out which.
      if change.problems.any?
        parts << "Could not be used: #{change.problems.map(&:callsign).to_sentence}."
      end
      # "Needed no action" rather than "already had the right state": the
      # skipping bucket also holds the repeats of a line, and a callsign matching
      # no one has no state to be right. Saying it that way asserted a state for
      # a typo, and counted an already-changed person a second time when their
      # callsign was pasted twice.
      parts << "#{pluralize(change.skipping.size, "callsign")} needed no action." if change.skipping.any?

      parts.join(" ")
    end

    private

    # Said out loud rather than left as silence: a team with no positions of the
    # relevant kind is unusual enough that the reader should know it was checked
    # and not simply omitted.
    # Says why, not what: the preview's lede already states that only the
    # membership moves, so repeating it here would fill two sentences with one
    # fact. What the reader cannot see is that the team simply has none.
    def bulk_team_no_positions(change)
      kinds = change.grant? ? "Recommended" : "Recommended or Optional"

      "This team has no #{kinds} positions to move."
    end
  end
end
