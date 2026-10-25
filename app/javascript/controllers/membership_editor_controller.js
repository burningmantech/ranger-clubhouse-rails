import {Controller} from "@hotwired/stimulus"

/**
 * Membership Editor Controller
 *
 * Manages interactive behaviors for the person membership editor:
 * - Confirms dangerous permission grants (Admin / Tech Ninja) via dialog
 * - Auto-selects "all members" positions when a team is checked
 * - Auto-deselects non-public positions when a team is unchecked
 * - Deselects "deselect on team join" positions when a team is joined
 */
export default class extends Controller {
  static targets = ["teamCard"]

  /**
   * Handle a team membership checkbox change.
   * Delegates to the team card element which holds all per-team data.
   */
  teamToggle(event) {
    const checkbox = event.currentTarget
    const card = checkbox.closest("[data-membership-editor-target='teamCard']")
    if (!card) return

    const isDangerous = card.dataset.dangerous === "true"
    const teamTitle = card.dataset.teamTitle

    if (checkbox.checked && isDangerous) {
      if (!this._confirmDangerous(checkbox, "Clubhouse Team", teamTitle, card.dataset.dangerousPermissions)) {
        return
      }
    }

    if (checkbox.checked) {
      this._selectAllMemberPositions(card)
      this._deselectOnTeamJoin(card)
    } else {
      this._deselectNonPublicPositions(card)
    }
  }

  /**
   * Handle the team manager checkbox change.
   * Warns when assigning manager access to a cadre or delegation.
   */
  managerToggle(event) {
    const checkbox = event.currentTarget
    const card = checkbox.closest("[data-membership-editor-target='teamCard']")
    if (!card) return

    const teamType = card.dataset.teamType
    const teamTitle = card.dataset.teamTitle

    if (checkbox.checked && teamType !== "team") {
      const confirmed = confirm(
        `The Clubhouse Team "${teamTitle}" is a ${teamType}.\n\n` +
        "It is recommended cadre / delegation members are NOT assigned as Clubhouse Managers " +
        "for their cadre/delegation, only their team. Otherwise, they may be given the ability " +
        "to mint new cadre/delegation members without approval from Council first, and " +
        "unintentional privilege escalation may result.\n\nMake them a Clubhouse Manager anyway?"
      )
      if (!confirmed) {
        checkbox.checked = false
      }
    }
  }

  /**
   * Handle a position checkbox change.
   * Confirms dangerous permission grants.
   */
  positionToggle(event) {
    const checkbox = event.currentTarget
    const wrapper = checkbox.closest("[data-position-dangerous]")
    if (!wrapper) return

    const isDangerous = wrapper.dataset.positionDangerous === "true"
    const positionTitle = wrapper.dataset.positionTitle

    if (checkbox.checked && isDangerous) {
      this._confirmDangerous(checkbox, "position", positionTitle, wrapper.dataset.positionDangerousPermissions)
    }
  }

  // -- Private helpers --------------------------------------------------------

  /**
   * Show a confirmation dialog for a dangerous permission grant.
   * Unchecks the checkbox if the user cancels.
   *
   * @returns {boolean} true if confirmed
   */
  _confirmDangerous(checkbox, entityType, title, permissions) {
    const confirmed = confirm(
      `The ${entityType} "${title}" has the permission(s) ${permissions} associated.\n\n` +
      "Normally, such permission grants require approval from Council and the Tech Team first.\n\n" +
      `Grant this ${entityType} anyway?`
    )

    if (!confirmed) {
      checkbox.checked = false
      return false
    }
    return true
  }

  /**
   * When a team is selected, auto-check all "all_members" category positions.
   */
  _selectAllMemberPositions(card) {
    card.querySelectorAll("[data-position-category='all_members'] input[type='checkbox']").forEach(cb => {
      cb.checked = true
    })
  }

  /**
   * When a team is selected, deselect positions flagged for deselection on join.
   */
  _deselectOnTeamJoin(card) {
    card.querySelectorAll("[data-deselect-on-join='true'] input[type='checkbox']").forEach(cb => {
      cb.checked = false
    })
  }

  /**
   * When a team is deselected, uncheck all non-public positions.
   */
  _deselectNonPublicPositions(card) {
    card.querySelectorAll("[data-position-category='all_members'] input[type='checkbox']").forEach(cb => {
      cb.checked = false
    })
    card.querySelectorAll("[data-position-category='optional'] input[type='checkbox']").forEach(cb => {
      cb.checked = false
    })
  }
}
