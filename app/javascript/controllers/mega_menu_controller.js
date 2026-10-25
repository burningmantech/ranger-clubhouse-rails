import Dialog, { SLOW_MS } from "controllers/dialog_controller"

// Connects to data-controller="mega-menu"
// Owns the navbar mega-menu <dialog>: open/close from the dialog base, plus
// client-side panel switching. Panels are server-rendered inside a lazy Turbo
// Frame; the active one is shown by clearing its hidden attribute.
//
// The menu also says when a request fails: the server cannot be reached, it
// answers with an error, or the sign-in has expired. Only the frame load and
// the star form fetch through the dialog -- link prefetch is off app-wide --
// so its Turbo events are the menu's own.
export default class extends Dialog {
  static targets = ["panel", "chrome", "search", "results", "noResults", "frame"]

  disconnect() {
    clearTimeout(this.slowTimer)
    super.disconnect()
  }

  // Picking a panel ends the search: the next star re-render would otherwise
  // re-apply the stale filter and pull the person back to the results.
  show(event) {
    const key = event.params.panel
    this.priorPanel = null
    this.clearSearch()
    this.showPanel(key)

    // A trigger inside the panel it just hid (a Favorites shortcut, the phone
    // Categories index, Back) would leave focus on nothing. Hand it to the new
    // panel's first rendered control: the heading star on desktop, Back on a phone.
    if (event.currentTarget.closest("[hidden]")) {
      const panel = this.panelTargets.find((p) => p.dataset.panel === key)
      const controls = [...panel.querySelectorAll("a[href], button")]
      controls.find((el) => el.checkVisibility())?.focus()
    }
  }

  // Ctrl+Shift+K / Cmd+Shift+K reaches the inherited hotkey by data-action.
  // The unshifted chord belongs to the search bar; Stimulus 3.2 matches all
  // four modifier flags exactly, so the two cannot both fire.

  // The menu is a search box first. On the very first open the panels are
  // still in flight inside the lazy frame, so there is nothing to focus yet
  // and the autofocus on the field itself covers that arrival.
  //
  // Opening again after a failure tries again. After a failed star that also
  // brings back the server's true stars: a flaky POST may have landed.
  open() {
    super.open()
    if (this.failed) this.retry()
    if (this.hasSearchTarget) this.searchTarget.focus()
  }

  // Closing by any route -- button, backdrop, Escape, hotkey -- drops the
  // filter. Without this the next open resumes a search the person has long
  // since forgotten, on a panel they never chose.
  close() {
    super.close()
    this.clearSearch()
  }

  // Starring an item re-renders the whole menu from the server, which knows
  // nothing about the filter -- it is client state, and "search" is never an
  // :active panel. Re-apply it to the fresh box, then put focus back on the
  // star: a star inside a [hidden] panel cannot take it.
  //
  // Fresh content from the server, by frame load or star, also ends whatever
  // was waiting or had failed.
  searchTargetConnected(input) {
    clearTimeout(this.slowTimer)
    this.showError(null)

    if (this.filter) {
      input.value = this.filter
      this.search()
    }

    // After the filter, so the star's panel is the one showing
    if (this.starId) {
      document.getElementById(this.starId)?.focus()
      this.starId = null
    }
  }

  // Turbo disables a submitting button, which drops its focus before the
  // toggle re-renders the menu, so Turbo's own restore-by-id finds nothing to
  // restore. Remember the star and focus its replacement on the way back.
  rememberStar(event) {
    this.starId = event.detail.formSubmission.submitter?.id
  }

  // A failed toggle re-renders nothing, so searchTargetConnected never puts
  // focus back. By submit-end Turbo has enabled the star again. A toggle the
  // next star called off ends with neither an answer nor an error, and focus
  // belongs to that next star.
  starSubmitted({ detail }) {
    if (detail.success || !(detail.fetchResponse || detail.error)) return

    document.getElementById(this.starId)?.focus()
    this.starId = null
  }

  // Only the frame load gets the slow warning: a hung star already shows as a
  // disabled button.
  fetchStarted(event) {
    if (event.target !== this.frameTarget) return

    clearTimeout(this.slowTimer)
    this.slowTimer = setTimeout(() => this.showError("slow"), SLOW_MS)
  }

  // A good answer settles nothing yet. This arrives with the headers; Turbo
  // reads the body afterwards, and a body that stalls or breaks off sends no
  // event at all, so the slow timer runs on until the menu itself arrives
  // (searchTargetConnected).
  fetchAnswered(event) {
    const { fetchResponse } = event.detail
    if (fetchResponse.succeeded) return

    // Stops Turbo painting the error page over the whole page
    event.preventDefault()
    clearTimeout(this.slowTimer)
    this.showError(fetchResponse.statusCode === 401 ? "expired" : "failed")
  }

  // Never preventDefault here. Turbo counts a lazy frame as loaded only once
  // its first visit settles, and a prevented error never settles it.
  unreachable() {
    clearTimeout(this.slowTimer)
    this.showError("offline")
  }

  // A 200 without the frame, such as a captive portal answering in the
  // server's place. Prevented, so the app-wide handler does not show that
  // page in place of the one the menu was opened on.
  frameMissing(event) {
    event.preventDefault()
    clearTimeout(this.slowTimer)
    this.showError("failed")
  }

  // One visit either way. A frame that has rendered something (a menu whose
  // star failed, a missing frame) reloads. One that never has turns eager,
  // which starts the visit and calls off a hung one: a lazy frame ignores
  // reload() until its first visit settles.
  //
  // Hiding the callout drops the focus on its button, so a loaded menu hands
  // it to the search box, which stays until the reload lands.
  retry() {
    this.showError(null)
    if (this.hasSearchTarget) this.searchTarget.focus()

    if (this.frameTarget.hasAttribute("complete")) {
      this.frameTarget.reload()
    } else {
      this.frameTarget.loading = "eager"
    }
  }

  // Until the menu arrives a failure replaces the spinner, and "slow" sits
  // above it. Once the menu has arrived, every message sits above the menu.
  showError(kind) {
    super.showError(kind)
    if (this.hasSearchTarget) return

    this.frameTarget.hidden = this.failed
    if (this.failed) {
      this.errorTargets.find((callout) => !callout.hidden).querySelector("button").focus()
    }
  }

  // Real-time filter over the flat search panel. Clearing the box returns the
  // person to whichever panel they were on before they started typing.
  search() {
    this.filter = this.searchTarget.value
    const query = this.filter.trim().toLowerCase()

    // No prior panel means typing never switched away from one, so the panel
    // on screen is already the right one to leave alone.
    if (!query) {
      if (this.priorPanel) this.showPanel(this.priorPanel)
      this.priorPanel = null
      return
    }

    if (!this.priorPanel) this.priorPanel = this.currentPanel()

    let matches = 0
    this.resultsTarget.querySelectorAll(".mega-menu-item").forEach((item) => {
      const hit = item.dataset.searchText.includes(query)
      item.hidden = !hit
      if (hit) matches += 1
    })
    this.noResultsTarget.hidden = matches > 0
    this.showPanel("search")
  }

  // Escape clears the query first; only an empty box closes the dialog.
  cancel(event) {
    if (this.clearSearch()) event.preventDefault()
  }

  // Empties the box and drops the filter. Returns whether there was a query.
  clearSearch() {
    if (!this.hasSearchTarget || !this.searchTarget.value) return false

    this.searchTarget.value = ""
    this.search()
    return true
  }

  currentPanel() {
    return this.panelTargets.find((panel) => !panel.hidden)?.dataset.panel
  }

  showPanel(key) {
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.panel !== key
    })
    this.chromeTargets.forEach((button) => {
      button.setAttribute("aria-current", button.dataset.panel === key ? "true" : "false")
    })
  }
}
