import { Controller } from "@hotwired/stimulus"

/**
 * Shows or hides what was typed in a password field.
 *
 * The field is masked by default and a press unmasks it until the next press.
 * The button carries the state: aria-pressed for a screen reader, whose label
 * "Show password" stays put (pressed says the rest), and the eye glyph open or
 * struck through. Focus stays on the button, so a keyboard reader is not thrown
 * back into the field they just left.
 */
export default class extends Controller {
  static targets = ["input", "button", "show", "hide"]

  toggle() {
    const show = this.inputTarget.type === "password"

    this.inputTarget.type = show ? "text" : "password"
    this.buttonTarget.setAttribute("aria-pressed", String(show))
    this.showTarget.classList.toggle("hidden", show)
    this.hideTarget.classList.toggle("hidden", !show)
  }
}
