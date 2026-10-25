import { Controller } from "@hotwired/stimulus"

/**
 * Locks the submit button once a session form is on its way.
 *
 * These forms opt out of Turbo, so a submit is a full page load with no
 * feedback of its own. On a slow playa connection that reads as "nothing
 * happened", and the retaps burn the ten-attempts-per-45-seconds rate limit
 * on a password that was correct the first time.
 *
 * Bound on the layout wrapper, so it covers every form on every session page.
 */
export default class extends Controller {
  pending(event) {
    // ponytail: the submitter carries no value the server reads, so disabling it
    // here cannot drop a field from the payload.
    const button = event.target.querySelector("[type=submit]")
    if (!button) return

    if (button.disabled) {
      event.preventDefault()
      return
    }

    button.disabled = true
    button.value = button.dataset.pendingLabel || "Working…"
  }
}
