import { Controller } from "@hotwired/stimulus"

// "Select all" toggle for checkbox tables: the toggle target checks or
// unchecks every checkbox target in scope, and individual changes keep the
// toggle in sync. Optional targets: a count target shows a live "N selected"
// text, and submit targets are disabled while nothing is checked.
// A checkbox carrying data-skip-select-all is left unchecked by "select all"
// (rows with problems), but unchecking still clears it and it stays
// individually selectable.
//
// A picker with more ways to choose (every position sharing one paycode)
// extends this: setAll(wants) takes a predicate, and countLabel() words the
// count.
export default class extends Controller {
  static targets = ["toggle", "checkbox", "count", "submit"]

  connect() {
    this.refresh()
  }

  toggleAll() {
    const checked = this.toggleTarget.checked
    this.setAll((box) => checked && this.armable(box))
  }

  setAll(wants) {
    this.checkboxTargets.forEach((box) => (box.checked = wants(box)))
    this.refresh()
  }

  refresh() {
    const boxes = this.checkboxTargets
    const selected = boxes.filter((box) => box.checked).length
    // Ticked once every box "select all" would tick is ticked.
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = selected > 0 && boxes.every((box) => box.checked || !this.armable(box))
    }
    // A live region rewritten as the page loads can be announced with nothing
    // to say what it counts, so a page that renders the count leaves connect()
    // nothing to write. trim() lets the markup put the count on its own line.
    const label = this.countLabel(selected, boxes.length)
    if (this.hasCountTarget && this.countTarget.textContent.trim() !== label) this.countTarget.textContent = label
    this.submitTargets.forEach((button) => (button.disabled = selected === 0))
  }

  // Must match BulkSelectHelper#bulk_select_count.
  countLabel(selected, _total) {
    return `${selected} selected`
  }

  // Whether "select all" ticks this box. The toggle's own state is judged by
  // the same rule, or a skipped row keeps it unticking itself.
  armable(box) {
    return !box.hasAttribute("data-skip-select-all")
  }
}
