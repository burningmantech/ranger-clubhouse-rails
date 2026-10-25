# frozen_string_literal: true

# What each position sanity check is called, what it means, and what its table
# shows.
#
# One table, read by the index rows, the check page heading, and the empty
# states, so a check cannot be described one way on the board and another way
# on its own page. PositionSanityCheck holds the facts the queries need; the
# words live here.
#
# Every method is prefixed position_check_ rather than sanity_check_. Rails
# mixes all helpers into one namespace for every view, and
# Bmid::SanityCheckHelper already owns sanity_check_meta -- the shorter name
# silently replaced its version once and broke the BMID page instead of raising.
module TeamsPositions::PositionSanityCheckerHelper
  # blurb: is the check page's hero description, so it is ONE sentence -- the
  # rule the check holds accounts to, or what its rows are. repair: is what the
  # button below the findings will do, and the page prints it there, beside the
  # button, rather than in the hero. A test holds every check to both.
  CHECK_META = {
    deactivated_accounts: {
      label: "Deactivated accounts with grants",
      icon: "user-slash",
      summary: "Bonked, resigned, or dismissed and still holding something",
      blurb: "These accounts are out — bonked, deceased, dismissed, past prospective, " \
             "resigned, or uberbonked — and still hold positions, team membership, or " \
             "permissions.",
      repair: "Repairing revokes all three: positions, team membership, and permissions.",
      empty: "No deactivated account still holds a position, a team, or a permission.",
      action: "Revoke everything"
    },
    retired_accounts: {
      label: "Retired accounts holding too much",
      icon: "box-archive",
      summary: "More than the new-user set",
      blurb: "A retired Ranger keeps the positions an auditor or prospective would have " \
             "and nothing else.",
      repair: "Repairing resets each account to the new-user set.",
      empty: "Every retired account holds only the new-user positions.",
      action: "Reset to the new-user set"
    },
    deactivated_positions: {
      label: "Deactivated positions still granted",
      icon: "ban",
      summary: "A switched-off position someone still holds",
      blurb: "These positions have been switched off but are still granted.",
      repair: "Repairing revokes the position from the people you pick.",
      empty: "No switched-off position is still granted.",
      action: "Revoke the position"
    },
    deactivated_teams: {
      label: "Deactivated teams with members",
      icon: "users-slash",
      summary: "A switched-off team someone still belongs to",
      blurb: "These teams have been switched off but still have members.",
      repair: "Repairing removes each person from the team and revokes that team's positions with it.",
      empty: "No switched-off team still has members.",
      action: "Remove from the team"
    },
    emyr: {
      label: "Event Management Year Round granted directly",
      icon: "key",
      summary: "The permission with nothing behind it",
      blurb: "This permission is meant to arrive through a position or a team.",
      repair: "These people were handed the permission directly and hold no position or team " \
              "that grants it, so the reason for it is gone. Repairing revokes the permission.",
      empty: "Everyone with Event Management Year Round holds a position or team that grants it.",
      action: "Revoke the permission"
    },
    missing_positions: {
      label: "Accounts missing basic positions",
      icon: "user-plus",
      summary: "Short of the All Rangers or New User set",
      blurb: "Every Ranger account should hold the All Rangers positions, and every live " \
             "account the New User ones.",
      repair: "Repairing grants each account what its row lists.",
      empty: "Every account holds the basic positions for its status.",
      action: "Grant the missing positions"
    },
    team_positions: {
      label: "Team members missing team positions",
      icon: "clipboard-check",
      summary: "On the team, short of its basic positions",
      blurb: "A team member should hold all of that team's basic positions.",
      repair: "Each row is one missing position, so you can grant one and leave another.",
      empty: "Every team member holds their team's basic positions.",
      action: "Grant the position"
    },
    team_membership: {
      label: "Team positions with no team membership",
      icon: "user-group",
      summary: "Holds the positions, not on the team",
      blurb: "Holding a team's basic positions should mean belonging to the team.",
      repair: "Repairing adds each person to the team their positions point at.",
      empty: "Everyone holding a team's basic positions belongs to that team.",
      action: "Add to the team"
    },
    shiny_pennies: {
      label: "Shiny Penny position",
      icon: "star",
      summary: "First-year Rangers, and only them",
      blurb: "Rangers who walked Alpha this year hold Dirt - Shiny Penny, and no one else does.",
      repair: "This check finds both mistakes at once, and each row is repaired whichever way " \
              "it is wrong — granted if it is missing, revoked if it is stale.",
      empty: "Every Shiny Penny holds the position, and no one else does.",
      action: "Grant or revoke as each row needs"
    }
  }.freeze

  # Who acts on a band, and what they are deciding. The heading is the promise
  # the grouping makes; what: is the board's card answering what is under it,
  # so each line has to say so on its own.
  BAND_META = {
    revoke: { title: "Access to Take Away",
              what: "Someone holds a position, a team, or a permission that is no longer theirs." },
    grant: { title: "Access to Hand Out",
             what: "Someone is missing a position or membership their status or team implies." },
    reconcile: { title: "Right for Some, Wrong for Others",
                 what: "Rows there can be wrong in either direction. The repair does whichever " \
                       "each row needs." }
  }.freeze

  # What each check's table shows beyond the checkbox, callsign, and status
  # every table carries. [heading, cell key] pairs, rendered by
  # #position_check_cell.
  #
  # The two grouped checks list nothing: their heading already names the
  # position or team, and repeating it in every row of the section under it
  # would be the same word forty times.
  COLUMNS = {
    deactivated_accounts: [["Still holds", :labels]],
    retired_accounts: [["Positions beyond the new-user set", :labels]],
    deactivated_positions: [],
    deactivated_teams: [],
    emyr: [],
    missing_positions: [["Missing positions", :titles]],
    team_positions: [["Team", :group], ["Missing position", :target]],
    team_membership: [["Missing team membership", :target], ["Team positions held", :labels]],
    shiny_pennies: [["Mentor year", :mentor_year], ["Holds the position", :holds_position]]
  }.freeze

  def position_check_meta(key) = CHECK_META.fetch(key.to_sym)

  def position_check_band_meta(band) = BAND_META.fetch(band.to_sym)

  def position_check_columns(key) = COLUMNS.fetch(key.to_sym)

  def position_check_path(key, **options)
    teams_positions_position_sanity_checker_check_path(key.to_s.dasherize, **options)
  end

  def position_check_repair_path(key)
    teams_positions_position_sanity_checker_repair_path(key.to_s.dasherize)
  end

  # One cell of a check's table. Lists go through value_list, the app-wide
  # "several values in one cell" helper the sibling Team Records and Position
  # Records tables use, so these cells match theirs; yes/no goes through
  # yes_no_badge for the same reason.
  #
  # An unrecognized key raises rather than rendering blank: COLUMNS and this
  # table have to agree, and a silently empty column is how they stop agreeing
  # without anyone noticing.
  def position_check_cell(finding, key)
    case key
    when :target then finding.target_label
    when :group then finding.group_label
    when :labels then value_list(Array(finding.detail))
    when :titles then value_list(Array(finding.detail).map(&:last))
    when :mentor_year then finding.detail[:mentor_year] || "Not recorded"
    when :holds_position then yes_no_badge(finding.detail[:holds_position])
    else raise ArgumentError, "Unknown position check cell #{key.inspect}"
    end
  end

  # Findings are a problem, not an achievement, so a count that is not zero is
  # never styled as success.
  #
  # size: "base" when the badge goes into a drill-down row, which renders its
  # headline at text-lg and every sibling index passes it. The default stays
  # xs for the standalone badge on the check page, where nothing sits beside it.
  def position_check_badge(count, size: nil)
    ui_badge(pluralize(count, "finding"), count.zero? ? :success : :error, size:)
  end
end
