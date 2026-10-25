/*
 * Search Bar Controller (Stimulus)
 *
 * Global search dialog with Ctrl+K / Cmd+K hotkey. A native <dialog> on the
 * dialog base, which owns opening, closing and the backdrop click; this adds
 * the hotkey, the enabled gate, the search modes, and saying when a search
 * fails. Permission-gated via server-rendered data attribute.
 *
 * Usage:
 *   <div data-controller="search-bar"
 *        data-action="keydown.ctrl+k@document->search-bar#hotkey keydown.meta+k@document->search-bar#hotkey"
 *        data-search-bar-enabled-value="true">
 *     <button data-action="search-bar#open">Search</button>
 *     <dialog data-search-bar-target="dialog" data-action="click->search-bar#backdropClose">...</dialog>
 *   </div>
 */

import Dialog from "controllers/dialog_controller"
import {Turbo} from "@hotwired/turbo-rails"

const SEARCH_MODE_KEY = "search-mode"

// Set just before a mode-switch navigation so the freshly connected controller
// on the next page re-opens the dialog (sessionStorage: the visit replaces the
// body, so nothing in memory survives).
const REOPEN_KEY = "search-bar-reopen"

// Canonical mode: the fallback whenever a persisted/legacy value is not one the
// viewer may currently use (e.g. "swag" saved before Quartermaster was revoked).
const MODE_PERSON_MANAGE = "person_manage"

// Person pages the mode switcher can re-route: /person/N/... and /hq/N/...
const PERSON_PAGE_RE = /^\/(?:person|hq)\/(\d+)(?:\/|$)/

export default class SearchBar extends Dialog {
    static targets = ["input", "modeInput", "modeSelect", "modeHint"]
    static outlets = ["autocomplete"]
    static values = {
        enabled: {type: Boolean, default: false},
        // Canonical fallback mode (always one of enabledModes).
        defaultMode: {type: String, default: "person_manage"},
        // True when the server default is onduty-driven (viewer on duty in an
        // HQ Window / mentor position): the default then overrides the persisted
        // mode so the bar auto-selects HQ mode.
        ondutyDefault: {type: Boolean, default: false},
        // Modes the bar may actually issue searches for. A persisted/legacy value
        // outside this set is rejected so a mode the viewer cannot use (e.g. a
        // stale "hq" persisted while the HQ Window Interface was enabled) can
        // never leak into a request.
        enabledModes: {type: Array, default: []},
        // mode -> descriptive hint shown in the label above the input, so it can be
        // swapped live on change without re-deriving copy in JS.
        labels: {type: Object, default: {}},
        // mode -> destination path template ("/person/:id/swag"), from
        // SearchBarPolicy::MODE_PATHS. Used to re-route the currently-viewed
        // person when the mode changes on a /person/N or /hq/N page.
        modePaths: {type: Object, default: {}},
    }

    connect() {
        super.connect()

        // Restore the persisted mode (validated against the enabled set) and push
        // it into the autocomplete so the first fetch already uses it. Persist the
        // resolved value back so a stale/disabled entry is normalized on disk.
        // Never persist the onduty-driven default: it is a transient, duty-scoped
        // override, and writing it back would overwrite the viewer's own saved
        // mode for good (hq stays selectable off duty, so it would never lapse).
        this.applyMode(this.restoreMode(), {persist: !this.ondutyDefaultValue})

        // A mode switch on a person/hq page navigates; re-open the dialog here so
        // the switch feels like a view change, not a dismissal.
        if (this.takeReopenFlag()) {
            this.open()
        }
    }

    // =========================================================================
    // Hotkey
    // =========================================================================

    // Ctrl+K / Cmd+K, bound on the document by data-action. The base owns the
    // editor guard and the toggle; only the permission gate is ours, and it
    // returns before preventDefault so a viewer without search keeps the key.
    hotkey(event) {
        if (!this.enabledValue) return

        super.hotkey(event)
    }

    // =========================================================================
    // Open / Close
    // =========================================================================

    // Opening again after a failure runs the search again.
    open() {
        if (!this.enabledValue) return

        super.open()
        if (this.failed) this.retry()
        // showModal lands on the autofocus input already; said explicitly so
        // it does not depend on which element the browser picks first.
        this.inputTarget.focus()
    }

    // =========================================================================
    // Failures
    // =========================================================================

    // The autocomplete's own message reads the same for every failure. The
    // dialog's callouts say which it was, and what to do about it. A search
    // still out after ten seconds says so in its own "Searching..." row.
    searchFailed(event) {
        event.preventDefault()
        this.showError(event.detail.kind)
    }

    // Any change to the box: the message was about a search no longer in it
    searchEdited() {
        this.showError(null)
    }

    // The search that failed, again: same text, same filter chip. Hiding the
    // callout drops the focus on its button, so the box takes it back.
    retry() {
        this.showError(null)
        this.inputTarget.focus()
        if (this.hasAutocompleteOutlet) this.autocompleteOutlet.refetch()
    }

    // =========================================================================
    // Mode switching
    // =========================================================================

    // Fired by the radio segmented control or the small-screen select.
    modeChange(event) {
        const mode = event.target.value
        this.applyMode(mode, {persist: true})
        this.followMode(mode)
    }

    // When the viewer is looking at a person (/person/N/... or /hq/N/...), switching
    // the mode switches the view of that same person: HQ Window -> /hq/N, Timesheet
    // -> /person/N/timesheets, and so on. Anywhere else the mode only affects the
    // next search. (Ember equivalent: search-item-bar.js modeChange.)
    followMode(mode) {
        const match = PERSON_PAGE_RE.exec(window.location.pathname)
        if (!match) return

        const template = this.modePathsValue[mode]
        if (!template) return

        const target = template.replace(":id", match[1])
        if (target === window.location.pathname) return

        try {
            window.sessionStorage.setItem(REOPEN_KEY, "1")
        } catch (_e) {
            // Best-effort: the dialog simply won't re-open after the visit.
        }
        Turbo.visit(target)
    }

    // Read-and-clear the "re-open after a mode-switch visit" flag.
    takeReopenFlag() {
        try {
            if (window.sessionStorage.getItem(REOPEN_KEY) === null) return false
            window.sessionStorage.removeItem(REOPEN_KEY)
            return true
        } catch (_e) {
            return false
        }
    }

    // Read the persisted mode, mapping a legacy "account" literal to
    // "person_manage" and falling back to "person_manage" when the value isn't a
    // currently-enabled mode -- a mode the viewer's permissions no longer unlock
    // (a stale "hq"/"swag"/"timesheet") never selects itself again.
    //
    // Onduty-driven default: when the viewer is on duty in an HQ Window or
    // mentor position, the server flags ondutyDefault and sets the default mode
    // to "hq" (SearchBarPolicy.default_mode) — auto-select it and ignore the
    // persisted value, mirroring the Ember search-item-bar behavior. applyMode
    // still validates the result against the enabled set.
    restoreMode() {
        if (this.ondutyDefaultValue) return this.defaultModeValue

        let saved = null
        try {
            saved = window.localStorage.getItem(SEARCH_MODE_KEY)
        } catch (_e) {
            // localStorage may be unavailable (private mode / blocked); fall back.
        }
        if (saved === "account") saved = MODE_PERSON_MANAGE
        return this.isEnabledMode(saved) ? saved : MODE_PERSON_MANAGE
    }

    isEnabledMode(mode) {
        const enabled = this.enabledModesValue
        if (!Array.isArray(enabled) || enabled.length === 0) {
            // No explicit set provided: only the default is considered safe.
            return mode === this.defaultModeValue
        }
        return enabled.includes(mode)
    }

    // Validate, persist (optionally), reflect in the controls, push the live mode
    // into the autocomplete, and swap the mode hint label.
    applyMode(mode, {persist}) {
        const next = this.isEnabledMode(mode) ? mode : MODE_PERSON_MANAGE

        if (persist) {
            try {
                window.localStorage.setItem(SEARCH_MODE_KEY, next)
            } catch (_e) {
                // Best-effort persistence only.
            }
        }

        this.syncModeControls(next)
        this.updateAutocompleteMode(next)
        this.updateModeHint(next)
    }

    syncModeControls(mode) {
        this.modeInputTargets.forEach((input) => {
            input.checked = input.value === mode
        })
        if (this.hasModeSelectTarget) {
            this.modeSelectTarget.value = mode
        }
    }

    // The autocomplete controller reads data-autocomplete-mode-value per fetch
    // (buildURL), so updating the attribute live changes the mode for the next
    // query without a reconnect.
    updateAutocompleteMode(mode) {
        const ac = this.element.querySelector("[data-controller~='autocomplete']")
        if (ac) {
            ac.setAttribute("data-autocomplete-mode-value", mode)
        }
    }

    updateModeHint(mode) {
        const text = this.labelsValue[mode]
        if (text && this.hasModeHintTarget) {
            this.modeHintTarget.textContent = text
        }
    }
}
