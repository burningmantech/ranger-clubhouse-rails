import { Controller } from "@hotwired/stimulus"

// Refreshes the slot form's trainer/parent link fieldsets when the position
// select changes. The fieldsets live inside a Turbo Frame; pointing the frame
// at the link-options endpoint re-renders them for the newly selected position
// while every other form field keeps its value.
export default class extends Controller {
  static values = { url: String, frame: String }

  refresh(event) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("position_id", event.target.value)

    // Carry the current link selections so an unchanged parent position keeps them.
    for (const name of ["trainer_slot_id", "parent_signup_slot_id"]) {
      const field = this.element.querySelector(`[name="slot[${name}]"]`)
      if (field) url.searchParams.set(name, field.value)
    }

    document.getElementById(this.frameValue).src = url
  }
}
