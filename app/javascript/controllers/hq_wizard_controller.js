import {Controller} from "@hotwired/stimulus"

// HQ On-Site Registration wizard engine — port of the Ember step machinery
// (port/components/ui-wizard.js + ui-wizard-step.js) over server-rendered
// step sections presented inside one <dialog> (upstream renders each active
// step in a ModalDialog). One step is visible at a time; Back and Cancel are
// pure client-side transitions, and ESC's native dialog close takes the
// Cancel path. Advancing happens only when:
//   - the server streams the advance-signal element into the signal region
//     (successful step save, or a radio check needing no confirmation),
//   - the operator confirms the streamed "No Event Radios Checked Out" modal
//     (its Confirm button carries data-hq-wizard-confirm; the modal lives in
//     the app-wide "modal" region outside this controller's scope, hence the
//     document click watcher), or
//   - a step explicitly requests a client-side advance (the emergency-contact
//     step when the operator may not edit the field — no no-op save).
// Cancelling after starting shows the "On-Site Registration Not Completed"
// notice, mirroring the upstream siteCheckInStarted/showSiteCheckInWizard
// state pair. Finishing is a full-page redirect, which resets everything.
export default class extends Controller {
  static targets = ["dialog", "step", "abandoned", "signal", "advance"]

  connect() {
    this.stepIndex = 0
    this.started = false
    // A restored Turbo snapshot can carry the dialog's open attribute; started
    // is already false, so the close event below shows no notice.
    if (this.dialogTarget.open) {
      this.dialogTarget.close()
    }
  }

  // "Begin On-Site Registration". Re-clicking while the wizard is open is a
  // no-op (upstream startSiteCheckIn); reopening after a cancel restarts from
  // the first step (upstream unmounts and remounts the step components).
  start() {
    if (this.dialogTarget.open) {
      return
    }
    this.started = true
    this.stepIndex = 0
    this.abandonedTarget.hidden = true
    this.showStep()
    this.dialogTarget.showModal()
  }

  // Cancel buttons show the notice directly rather than relying on the close
  // event round-trip; closed() covers ESC — the native dialog cancel — so both
  // exits land on the same (idempotent) abandon.
  cancel() {
    this.abandon()
    this.dialogTarget.close()
  }

  // Native close event: show the not-completed notice. Finishing never lands
  // here — it is a full-page redirect, so no close fires before navigation.
  closed() {
    this.abandon()
  }

  abandon() {
    if (this.started) {
      this.abandonedTarget.hidden = false
      this.abandonedTarget.scrollIntoView({block: "nearest"})
    }
  }

  back() {
    if (this.stepIndex === 0) {
      return
    }
    this.stepIndex -= 1
    this.showStep()
  }

  // Client-side advance. Ignored when the wizard is not open so a stale
  // stream (for example, one arriving after a cancel) cannot reopen it.
  advance() {
    if (!this.dialogTarget.open || this.stepIndex >= this.stepTargets.length - 1) {
      return
    }
    this.stepIndex += 1
    this.showStep()
  }

  // Server-confirmed advance: the advance-signal partial connected inside the
  // signal region. Remove it immediately so the region is clean for the next
  // signal and reconnects never double-fire.
  advanceTargetConnected(element) {
    element.remove()
    this.advance()
  }

  // Watches document clicks for the no-radio modal's Confirm button.
  documentClick(event) {
    if (event.target.closest("[data-hq-wizard-confirm]")) {
      this.advance()
    }
  }

  showStep() {
    this.stepTargets.forEach((step, index) => {
      step.hidden = index !== this.stepIndex
    })
    const step = this.stepTargets[this.stepIndex]
    step.scrollIntoView({block: "nearest"})
    step.querySelector("[autofocus]")?.focus()
  }
}
