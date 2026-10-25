import {Controller} from "@hotwired/stimulus"

/**
 * Permission Editor Controller
 *
 * Guards manual permission grants on the person permission editor:
 * - Confirms when manually granting a role the person already holds through a
 *   team membership and/or a granted position.
 * - Warns before saving newly-added roles that require Ranger Council approval
 *   (Admin / View Personal Info).
 */
export default class extends Controller {
  static targets = ["checkbox"]

  connect() {
    this.originalCouncil = new Map()
    this.checkboxTargets.forEach(cb => {
      if (cb.dataset.council === "true") {
        this.originalCouncil.set(cb, cb.checked)
      }
    })
  }

  toggle(event) {
    const cb = event.currentTarget
    if (!cb.checked || cb.dataset.granted !== "true") return

    const ok = confirm(
      `${cb.dataset.roleTitle} is already granted through a team membership and/or a position.\n\n` +
      "Grant it manually as well?"
    )
    if (!ok) cb.checked = false
  }

  submit(event) {
    const added = this.checkboxTargets.filter(
      cb => cb.dataset.council === "true" && cb.checked && this.originalCouncil.get(cb) === false
    )
    if (added.length === 0) return

    const titles = added.map(cb => cb.dataset.roleTitle).join(" and ")
    const ok = confirm(
      `WARNING: ${titles} require prior approval by the Ranger Council.\n\n` +
      "This person will gain access to sensitive information and administrative functions.\n\n" +
      `Grant ${titles} anyway?`
    )
    if (!ok) event.preventDefault()
  }
}
