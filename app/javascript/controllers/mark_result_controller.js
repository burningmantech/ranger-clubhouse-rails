import { Controller } from "@hotwired/stimulus"

// Writes one result into every ticked row of a worksheet -- the "mark selected
// as passed" shortcut on the Alpha Mentor Assignments page. Nothing is saved:
// the sheet still has to be submitted, which is upstream's behaviour too.
//
// Assigning to .value fires no event of its own, so each write dispatches a
// bubbling change. Without it the unsaved-changes guard on the form would not
// notice the edit and would let the page be navigated away from silently.
export default class extends Controller {
  static targets = ["row"]
  static values = { selector: String, result: String }

  apply() {
    this.rowTargets.forEach((row) => {
      const box = row.querySelector("input[type=checkbox]")
      if (!box || !box.checked) return

      const field = row.querySelector(this.selectorValue)
      if (!field || field.value === this.resultValue) return

      field.value = this.resultValue
      field.dispatchEvent(new Event("change", { bubbles: true }))
    })
  }
}
