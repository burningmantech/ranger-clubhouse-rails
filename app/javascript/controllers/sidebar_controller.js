import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="sidebar"
// Works with DaisyUI drawer component (drawer-toggle checkbox)
export default class extends Controller {
  closeDrawer(event) {
    event.preventDefault()
    const checkbox = document.getElementById("sidebar-drawer")
    if (checkbox) {
      checkbox.checked = false
    }
  }

  openDrawer(event) {
    event.preventDefault()
    const checkbox = document.getElementById("sidebar-drawer")
    if (checkbox) {
      checkbox.checked = true
    }
  }
}
