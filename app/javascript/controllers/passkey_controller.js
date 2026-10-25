// app/javascript/controllers/passkey_controller.js
// Walks a form through a passkey ceremony: asks the Clubhouse for the options,
// hands them to the browser, which has the phone, laptop or security key do
// its part, and puts the answer in a hidden field before letting the form go.
//
// The browser's own JSON helpers do all the encoding, so there is none here.
// A browser without them never sees passkeys at all: the wrapper stays hidden
// (or, on a page that is only about passkeys, a notice says why), and the
// password goes on signing people in.

import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

// What each ceremony asks of the browser.
const CEREMONIES = {
  create: (options) => navigator.credentials.create({ publicKey: PublicKeyCredential.parseCreationOptionsFromJSON(options) }),
  get: (options) => navigator.credentials.get({ publicKey: PublicKeyCredential.parseRequestOptionsFromJSON(options) }),
}

const MESSAGES = {
  create: {
    // The person closed the prompt, or let it time out. The browser does not
    // say which, on purpose.
    NotAllowedError: "That was cancelled or timed out. Try again when you are ready.",
    // The device already holds a passkey for this account.
    InvalidStateError: "This device or key already has a passkey for this account.",
    fallback: "The passkey could not be added. Try again, or use a different device or key.",
  },
  get: {
    NotAllowedError: "Passkey sign-in was cancelled or timed out. Try again, or sign in with your email address and password.",
    fallback: "That passkey could not be used. Try again, or sign in with your email address and password.",
  },
}

export default class extends Controller {
  static targets = ["form", "credential", "password", "submit", "error", "errorMessage", "unsupported"]
  static values = { optionsUrl: String, ceremony: String }

  connect() {
    if (this.supported) {
      // A wrapper that is only worth showing where passkeys can happen.
      this.element.hidden = false
      return
    }

    if (this.hasUnsupportedTarget) this.unsupportedTarget.hidden = false
    if (this.hasSubmitTarget) this.submitTarget.disabled = true
  }

  async run(event) {
    event.preventDefault()
    if (this.busy) return

    this.setBusy(true)
    this.hideError()

    try {
      const options = await this.fetchOptions()
      if (!options) return

      const credential = await CEREMONIES[this.ceremonyValue](options)
      this.credentialTarget.value = JSON.stringify(credential.toJSON())
      // Checked once already; it has no reason to travel again.
      if (this.hasPasswordTarget) this.passwordTarget.value = ""
      // submit(), not requestSubmit(): no submit event, so no way back in here.
      this.form.submit()
    } catch (error) {
      const messages = MESSAGES[this.ceremonyValue]
      this.showError(messages[error.name] || messages.fallback)
    }
  }

  // The options for the ceremony, or nothing once the reason has been shown.
  async fetchOptions() {
    const response = await post(this.optionsUrlValue, { body: new FormData(this.form), responseKind: "json" })

    // A session that ended while the page sat open answers with the sign-in page.
    if (response.redirected) {
      window.location.href = response.response.url
      return null
    }

    const data = await response.json.catch(() => ({}))
    if (response.ok) return data

    this.showError(data.error || MESSAGES[this.ceremonyValue].fallback)
    return null
  }

  showError(message) {
    this.errorMessageTarget.textContent = message
    this.errorTarget.hidden = false
    this.setBusy(false)
  }

  hideError() {
    this.errorTarget.hidden = true
  }

  // Waiting on the device can take a while, and a second tap would start a
  // second ceremony on top of the first.
  setBusy(busy) {
    this.busy = busy
    if (!this.hasSubmitTarget) return

    const button = this.submitTarget
    button.disabled = busy
    // Only an <input> carries its label as a value. A <button> keeps its icon
    // and words; the device's own prompt says what is being waited for.
    if (!button.dataset.pendingLabel) return

    if (busy) {
      this.idleLabel = button.value
      button.value = button.dataset.pendingLabel
    } else if (this.idleLabel) {
      button.value = this.idleLabel
    }
  }

  // The form that carries the answer: the element itself on a page that is
  // one form, a form inside it where the controller wraps more than that.
  get form() {
    return this.hasFormTarget ? this.formTarget : this.element
  }

  get supported() {
    return typeof window.PublicKeyCredential?.parseCreationOptionsFromJSON === "function" &&
      typeof window.PublicKeyCredential?.parseRequestOptionsFromJSON === "function"
  }
}
