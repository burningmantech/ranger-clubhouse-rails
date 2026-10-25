import { Controller } from "@hotwired/stimulus"

// A native <dialog> opened as a modal: the browser supplies the backdrop, the
// focus trap, Escape, and putting focus back where it was on close. This owns
// the little every such dialog needs and nothing else; the mega menu and the
// search bar extend it.
//
// An open modal dialog must not be captured in Turbo's snapshot cache -- a
// restoration visit would revive it without its top-layer, modal state -- so
// it is closed before the page is cached.

// Text entry that owns its own keystrokes: a document-bound hotkey must never
// take a key away from an editor someone is typing in.
const EDITORS = "[contenteditable='true'], lexxy-editor, .ProseMirror"

// How long a request may run before the dialog says so and offers a retry
export const SLOW_MS = 10_000

export default class extends Controller {
  // error: the dialog's failure callouts (application/_dialog_status), one per kind
  static targets = ["dialog", "error"]

  // The snapshot keeps attributes, so a callout left showing (and the mega
  // menu's hidden frame) would come back on Back, to a controller that no
  // longer knows anything failed.
  connect() {
    this.closeBeforeCache = () => {
      this.close()
      this.showError(null)
    }
    document.addEventListener("turbo:before-cache", this.closeBeforeCache)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.closeBeforeCache)
  }

  open() {
    if (this.dialogTarget.open) return

    // One modal at a time. A second showModal() stacks top layers, so the
    // dialog underneath is buried with no backdrop of its own left to click
    // and takes a second Escape to reach.
    document.querySelectorAll("dialog:modal").forEach((dialog) => dialog.close())
    this.dialogTarget.showModal()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  toggle() {
    if (this.dialogTarget.open) {
      this.close()
    } else {
      this.open()
    }
  }

  // Shared body for a document-bound keyboard shortcut. Subclasses that gate
  // on a permission override this, check, and call super.
  hotkey(event) {
    // Chrome brackets every value it autofills with a plain keydown and keyup
    // Event -- no key, no modifiers, not a KeyboardEvent -- and Stimulus applies
    // the ".meta+k" filter to KeyboardEvents only, so that keydown arrived here
    // unfiltered and opened this dialog over the form being filled.
    if (!(event instanceof KeyboardEvent)) return
    if (event.repeat) return
    // Not while the first-sign-in tour is up (driver.js marks the body): its
    // overlay would leave the dialog unclickable, and the Escape that closed
    // the dialog would end the tour.
    if (document.body.classList.contains("driver-active")) return
    if (!this.hasDialogTarget) return
    if (document.activeElement?.closest(EDITORS)) return

    event.preventDefault()
    event.stopPropagation()
    this.toggle()
  }

  // The backdrop belongs to the dialog element, so a click on it arrives with
  // the dialog as its target -- but so does one on bare dialog surface inside
  // the box, between children. Only a click outside the box closes it.
  backdropClose(event) {
    if (event.target !== this.dialogTarget) return

    const box = this.dialogTarget.getBoundingClientRect()
    const inside = event.clientX >= box.left && event.clientX <= box.right &&
      event.clientY >= box.top && event.clientY <= box.bottom
    if (!inside) this.close()
  }

  // Shows the error callout for kind and hides the rest; null hides them all.
  // "slow" is a warning while the request is still out, not a failure.
  showError(kind) {
    this.errorKind = kind
    this.failed = kind !== null && kind !== "slow"
    this.errorTargets.forEach((callout) => {
      callout.hidden = callout.dataset.kind !== kind
    })
  }

  // This page again, which the server sends to sign-in and then back here. A
  // page a form re-rendered sits at the form's own address, which may answer
  // only to a POST, so its view hands over a page to load instead (url).
  signIn({ params: { url } }) {
    if (url) {
      window.location.assign(url)
    } else {
      window.location.reload()
    }
  }
}
