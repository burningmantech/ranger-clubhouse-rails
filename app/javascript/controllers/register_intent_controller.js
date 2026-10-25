import { Controller } from "@hotwired/stimulus"

// The auditor form offers "become a Ranger" as a reason on purpose: readers who
// mean to will pick it however firmly they are told this is not the path.
// Choosing it opens no account. The moment it is picked this reveals where the
// reader belongs instead and holds the submit, so no one fills the whole form
// out only to be turned away at the end. The server turns the same answer around
// on submit as well, so the catch still holds with JavaScript off.
//
// Scoped to the form so it can reach both the reason radios and the submit; it
// only acts on the reason field and leaves every other change alone.
export default class extends Controller {
  static targets = ["message", "submit"]
  static values = { trigger: String }

  connect() {
    this.#apply(this.#checkedIntent())
  }

  // Bound to the form, so this runs for every field's change event; act only on
  // the reason radios and let the rest pass.
  check(event) {
    const field = event.target
    if (!field.name || !field.name.endsWith("[intent]")) return
    this.#apply(field.value)
  }

  #apply(value) {
    const wrongPlace = value === this.triggerValue
    this.messageTarget.classList.toggle("hidden", !wrongPlace)
    if (this.hasSubmitTarget) this.submitTarget.disabled = wrongPlace
  }

  #checkedIntent() {
    const checked = this.element.querySelector("input[name$='[intent]']:checked")
    return checked ? checked.value : null
  }
}
