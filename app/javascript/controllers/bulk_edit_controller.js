import { Controller } from "@hotwired/stimulus"

// Spreadsheet-style bulk editing for a table of rows inside one form.
//
// On connect every row's fields are snapshotted. A row is "dirty" once any of
// its fields differs from that snapshot, and clean again the moment it is
// edited back — so the count, the row tint, and the Save button always
// describe what would actually be sent.
//
// On submit the fields of every pristine row are disabled. Disabled fields are
// not serialized, so only the changed rows travel to the server and an untouched
// row can never be rewritten by a save it had nothing to do with. They are
// re-enabled if the submission comes back without leaving the page.
//
// A row rendered with data-dirty="true" (one the server could not save) starts
// dirty, so the values still needing attention are re-submitted on the retry.
//
// The leave-the-page guard is deliberately not repeated here: pair this
// controller with unsaved-changes on the same form.
export default class extends Controller {
  static targets = ["row", "count", "submit", "discard"]
  static classes = ["dirty"]

  connect() {
    this.snapshots = new Map()
    this.forcedDirty = new Set()
    this.suppressed = []

    this.rowTargets.forEach((row) => {
      this.snapshots.set(row, this.readRow(row))
      if (row.dataset.dirty === "true") this.forcedDirty.add(row)
    })

    this.refresh = this.refresh.bind(this)
    this.suppressPristineRows = this.suppressPristineRows.bind(this)
    this.restoreSuppressed = this.restoreSuppressed.bind(this)

    this.element.addEventListener("input", this.refresh)
    this.element.addEventListener("change", this.refresh)
    this.element.addEventListener("submit", this.suppressPristineRows)
    this.element.addEventListener("turbo:submit-end", this.restoreSuppressed)

    this.refresh()
  }

  disconnect() {
    this.element.removeEventListener("input", this.refresh)
    this.element.removeEventListener("change", this.refresh)
    this.element.removeEventListener("submit", this.suppressPristineRows)
    this.element.removeEventListener("turbo:submit-end", this.restoreSuppressed)
    this.restoreSuppressed()
  }

  // Put every field back the way the page loaded it and forget every edit.
  discard() {
    this.rowTargets.forEach((row) => {
      const original = this.snapshots.get(row) || []
      this.fields(row).forEach((field, index) => {
        if (index < original.length) field.value = original[index]
      })
    })

    this.forcedDirty.clear()
    this.refresh()
  }

  refresh() {
    let changed = 0

    this.rowTargets.forEach((row) => {
      const dirty = this.isDirty(row)
      if (dirty) changed += 1

      row.dataset.dirty = dirty ? "true" : "false"
      this.dirtyClasses.forEach((name) => row.classList.toggle(name, dirty))

      const marker = row.querySelector("[data-bulk-edit-marker]")
      if (marker) marker.hidden = !dirty
    })

    if (this.hasCountTarget) this.countTarget.textContent = this.countLabel(changed)
    this.submitTargets.forEach((button) => (button.disabled = changed === 0))
    this.discardTargets.forEach((button) => (button.disabled = changed === 0))
  }

  countLabel(changed) {
    if (changed === 0) return "No rows changed"
    if (changed === 1) return "1 row changed"

    return `${changed} rows changed`
  }

  isDirty(row) {
    if (this.forcedDirty.has(row)) return true

    const original = this.snapshots.get(row) || []

    return this.readRow(row).some((value, index) => value !== original[index])
  }

  fields(row) {
    return Array.from(row.querySelectorAll("input, select, textarea"))
  }

  readRow(row) {
    return this.fields(row).map((field) => field.value)
  }

  suppressPristineRows() {
    this.suppressed = []

    this.rowTargets.forEach((row) => {
      if (this.isDirty(row)) return

      this.fields(row).forEach((field) => {
        // A field that was already disabled — a SAP date with no document to
        // change — must stay that way when the rest are restored.
        if (field.disabled) return

        field.disabled = true
        this.suppressed.push(field)
      })
    })
  }

  restoreSuppressed() {
    this.suppressed.forEach((field) => (field.disabled = false))
    this.suppressed = []
  }
}
