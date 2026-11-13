import {Controller} from "@hotwired/stimulus"
import {Turbo} from "@hotwired/turbo-rails"
import {confirmChecked} from "controllers/confirm_checkbox"

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

    const title = cb.dataset.roleTitle
    confirmChecked(cb, {
      title: "Role Already Granted",
      message: [
        `Grant ${title} manually as well?`,
        `${title} is already granted through a team membership, a position, or both.`
      ],
      confirmLabel: "Grant Manually"
    })
  }

  // Asks in the app's dialog, so the submit is held and sent again on yes.
  async submit(event) {
    if (this.allowSubmit) {
      this.allowSubmit = false
      return
    }

    const added = this.checkboxTargets.filter(
      cb => cb.dataset.council === "true" && cb.checked && this.originalCouncil.get(cb) === false
    )
    if (added.length === 0) return

    event.preventDefault()

    const titles = added.map(cb => cb.dataset.roleTitle).join(" and ")
    const confirmed = await Turbo.config.forms.confirm({
      title: "Council Approval Required",
      message: [
        `Grant ${titles}?`,
        `${titles} ${added.length === 1 ? "requires" : "require"} prior approval by the Ranger Council. ` +
          "This person will gain access to sensitive information and administrative functions."
      ],
      confirmLabel: "Grant"
    }, this.element, event.submitter)
    if (!confirmed) return

    this.allowSubmit = true
    this.element.requestSubmit(event.submitter)
  }
}
