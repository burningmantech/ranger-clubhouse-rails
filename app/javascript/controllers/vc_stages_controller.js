import { Controller } from "@hotwired/stimulus"
import { local } from "controllers/storage"

const STORAGE_KEY = "vc-stages-expand-all"

// Expand/collapse all review stage cards; the preference persists per browser.
export default class extends Controller {
  static targets = ["stage", "toggle"]

  connect() {
    if (local.read(STORAGE_KEY) === "1") {
      this.apply(true)
    }
    this.updateLabel()
  }

  toggle() {
    const expand = !this.allOpen()
    this.apply(expand)
    if (expand) {
      local.write(STORAGE_KEY, "1")
    } else {
      local.remove(STORAGE_KEY)
    }
    this.updateLabel()
  }

  allOpen() {
    return this.stageTargets.every((stage) => stage.open)
  }

  apply(open) {
    this.stageTargets.forEach((stage) => { stage.open = open })
  }

  updateLabel() {
    if (!this.hasToggleTarget) return
    this.toggleTarget.textContent = this.allOpen() ? "Collapse all" : "Expand all"
  }
}
