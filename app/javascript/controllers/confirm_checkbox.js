import { Turbo } from "@hotwired/turbo-rails"

// Asks in the app's dialog before a box stays ticked, and unticks it on no.
// Resolves true when it stays. The question is a confirm as application.js
// takes one: {title, message, confirmLabel, ...}.
export async function confirmChecked(checkbox, question) {
    if (await Turbo.config.forms.confirm(question, checkbox)) return true
    checkbox.checked = false
    return false
}
