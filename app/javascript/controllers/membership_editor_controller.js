import {Controller} from "@hotwired/stimulus"
import {confirmChecked} from "controllers/confirm_checkbox"

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
      this._check(card, "[data-position-category='all_members']", true)
      this._check(card, "[data-deselect-on-join='true']", false)
    } else {
      this._check(card, "[data-position-category='all_members']", false)
      this._check(card, "[data-position-category='optional']", false)
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
      confirmChecked(checkbox,
        `The Clubhouse Team "${teamTitle}" is a ${teamType}.\n\n` +
        "It is recommended cadre / delegation members are NOT assigned as Clubhouse Managers " +
        "for their cadre/delegation, only their team. Otherwise, they may be given the ability " +
        "to mint new cadre/delegation members without approval from Council first, and " +
        "unintentional privilege escalation may result.\n\nMake them a Clubhouse Manager anyway?"
      )
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
    return confirmChecked(checkbox,
      `The ${entityType} "${title}" has the permission(s) ${permissions} associated.\n\n` +
      "Normally, such permission grants require approval from Council and the Tech Team first.\n\n" +
      `Grant this ${entityType} anyway?`
    )
  }

  /**
   * Ticks or unticks every position checkbox under +selector+ in the card:
   * a joined team's all-members positions on, its deselect-on-join ones off;
   * a left team's all-members and optional positions off.
   */
  _check(card, selector, checked) {
    card.querySelectorAll(`${selector} input[type='checkbox']`).forEach((box) => (box.checked = checked))
  }
}
