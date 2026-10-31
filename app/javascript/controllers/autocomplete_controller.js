/*
 * Autocomplete Controller (Stimulus)
 *
 * Supports two modes:
 *   - JSON mode: fetches unified JSON response with grouped/flat results
 *   - HTML mode (legacy): fetches HTML partials directly
 *
 * JSON response format:
 *   { request_id, query, mode, empty_text, filters[], groups[], flat_item_ids[], items[], meta }
 *
 * Usage:
 *   <div data-controller="autocomplete"
 *        data-autocomplete-url-value="/autocomplete/search"
 *        data-autocomplete-mode-value="person_manage"
 *        data-autocomplete-response-type-value="json">
 *     <input data-autocomplete-target="input" />
 *     <div data-autocomplete-target="results" hidden></div>
 *   </div>
 */

import {Controller} from "@hotwired/stimulus"

const optionSelector = "[role='option']:not([aria-disabled])"
const activeSelector = "[aria-selected='true']"

// How long a search may run before its "Searching..." row calls the connection slow
const SLOW_SEARCH_MS = 10_000

// A floating list's height at most (.ac-results' 20rem), the gap it keeps from
// its field and from the edge of what is on screen, the least it is cut to
// where there is room for it (a row and a group's header), and its margin from
// the box it hangs from (.ac-results' 0.25rem).
const LIST_MAX = 320
const LIST_GAP = 16
const LIST_FLOOR = 96
const LIST_MARGIN = 4

// A TypeError is what fetch, and a read of the body after it, reject with when
// the network fails: no answer at all, or one cut off. Invalid JSON is a
// SyntaxError, and stays a "failed" answer from the server.
const connectionLost = (error) => {
    if (error.name === "TypeError") error.kind = "offline"
    throw error
}

const debounce = (fn, delay = 10) => {
    let timeoutId = null
    const debounced = (...args) => {
        clearTimeout(timeoutId)
        timeoutId = setTimeout(fn, delay)
    }
    debounced.cancel = () => clearTimeout(timeoutId)
    return debounced
}

export default class Autocomplete extends Controller {
    static targets = ["input", "hidden", "results", "empty", "loading", "filterBar", "keyboardHelp"]
    static classes = ["selected"]
    static values = {
        ready: Boolean,
        submitOnSelect: Boolean,
        formField: Boolean,
        inline: Boolean,
        selectOnBlur: Boolean,
        // The text is itself a choice (the mailbox search): the first row of a
        // search's results stands for it (this.lead) and arrives highlighted,
        // and Enter sends the form with the text unless the reader picked
        // another row (onEnterKeydown). Tab and select-on-blur never take it.
        freeText: Boolean,
        url: String,
        minLength: {type: Number, default: 2},
        delay: {type: Number, default: 300},
        queryParam: {type: String, default: "q"},
        mode: {type: String, default: ""},
        responseType: {type: String, default: "html"},
        metaMapping: {type: String, default: ""},
        limit: {type: Number, default: 5},
        recentsKey: {type: String, default: ""},
        maxRecents: {type: Number, default: 5},
    }
    static uniqOptionId = 0

    connect() {
        this.close()
        this.abortController = null
        this.currentRequestId = null
        this.activeFilters = {}
        this.searching = false
        this.pendingEnter = false
        this.lead = null

        if (!this.inputTarget.hasAttribute("autocomplete")) this.inputTarget.setAttribute("autocomplete", "off")
        this.inputTarget.setAttribute("spellcheck", "false")

        this.mouseDown = false
        // Under a name of its own, so that each connect wraps the handler itself.
        // The same instance connects again when its element is moved, and a
        // wrapper put around the last wrapper added one more delay every time.
        this.debouncedInputChange = debounce(this.onInputChange, this.delayValue)

        this.inputTarget.addEventListener("keydown", this.onKeydown)
        this.inputTarget.addEventListener("focus", this.onInputFocus)
        // On the element, not the input: focus can also leave from a filter chip.
        this.element.addEventListener("focusout", this.onFocusOut)
        // At once, then debounced: see onInputMark.
        this.inputTarget.addEventListener("input", this.onInputMark)
        this.inputTarget.addEventListener("input", this.debouncedInputChange)
        this.resultsTarget.addEventListener("mousedown", this.onResultsMouseDown)
        this.resultsTarget.addEventListener("click", this.onResultsClick)

        if (this.inputTarget.hasAttribute("autofocus")) {
            this.inputTarget.focus()
        }

        // A wired keyboard-help footer is a persistent hint (e.g. the search
        // modal): show it immediately rather than waiting for the first results,
        // and the controller will reuse it instead of injecting a duplicate.
        if (this.hasKeyboardHelpTarget) {
            this.keyboardHelpTarget.hidden = false
        }

        this.readyValue = true
    }

    disconnect() {
        // Nothing is opened once the controller is gone, and nothing searched
        // for: the request aborted here does not spend a queued Enter, and the
        // search still in its debounce never starts.
        this.pendingEnter = false
        this.cancelPendingRequest()
        this.debouncedInputChange?.cancel()
        this.element.removeEventListener("focusout", this.onFocusOut)

        if (this.hasInputTarget) {
            this.inputTarget.removeEventListener("keydown", this.onKeydown)
            this.inputTarget.removeEventListener("focus", this.onInputFocus)
            this.inputTarget.removeEventListener("input", this.onInputMark)
            this.inputTarget.removeEventListener("input", this.debouncedInputChange)
        }

        if (this.hasResultsTarget) {
            this.resultsTarget.removeEventListener("mousedown", this.onResultsMouseDown)
            this.resultsTarget.removeEventListener("click", this.onResultsClick)
        }
    }

    // =========================================================================
    // Request Management
    // =========================================================================

    cancelPendingRequest() {
        if (this.abortController) {
            this.abortController.abort()
            this.abortController = null
        }
    }

    // =========================================================================
    // Navigation
    // =========================================================================

    sibling(next) {
        const options = this.options
        const selected = this.selectedOption
        const index = options.indexOf(selected)
        const sibling = next ? options[index + 1] : options[index - 1]
        const def = next ? options[0] : options[options.length - 1]
        return sibling || def
    }

    // scroll: false leaves the list and the page where they are (a row
    // highlighted as the list arrives, renderJsonResults).
    select(target, {scroll = true} = {}) {
        const previouslySelected = this.selectedOption
        if (previouslySelected) {
            previouslySelected.removeAttribute("aria-selected")
            previouslySelected.classList.remove(...this.selectedClassesOrDefault)
        }

        target.setAttribute("aria-selected", "true")
        target.classList.add(...this.selectedClassesOrDefault)
        this.inputTarget.setAttribute("aria-activedescendant", target.id)
        if (!scroll) return

        // The filter bar is sticky inside the scrolling list, so "nearest" alone
        // parks a row arriving from above underneath it. Reserve the bar's height,
        // read now because it wraps to more rows on a narrow screen and some lists
        // have no bar at all.
        const bar = this.resultsTarget.querySelector(".ac-filter-bar")
        this.resultsTarget.style.scrollPaddingTop = bar ? `${bar.offsetHeight}px` : ""

        const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
        target.scrollIntoView({behavior: prefersReducedMotion ? "auto" : "smooth", block: "nearest"})
    }

    // =========================================================================
    // Keyboard Handling
    // =========================================================================

    onKeydown = (event) => {
        // A key an input method keeps for itself, such as the Enter that confirms
        // a composition, arrives with keyCode 229. It is not for the list. Not
        // event.isComposing: Safari ends the composition before this keydown
        // (WebKit bug 165004), and a phone keyboard composes each word as it is
        // typed, so its Enter, a plain 13, would be dropped mid-word.
        if (event.keyCode === 229) return

        const handler = this[`on${event.key}Keydown`]
        if (handler) handler(event)
    }

    onEscapeKeydown = (event) => {
        // The key is taken from the page only when it closes a list. Before the
        // list is up it is left alone (a dialog closes on it), but the search
        // still to come, and an Enter waiting for it, are called off all the same.
        if (this.resultsShown) {
            event.stopPropagation()
            event.preventDefault()
        }
        this.hideAndRemoveOptions()
    }

    onArrowDownKeydown = (event) => {
        const item = this.sibling(true)
        if (item) this.select(item)
        event.preventDefault()
    }

    onArrowUpKeydown = (event) => {
        const item = this.sibling(false)
        if (item) this.select(item)
        event.preventDefault()
    }

    onTabKeydown = (event) => {
        // Only a form field's row is taken, on the way to the next field. In the
        // search dialog a row is left to Enter and a click: Tab is the only key
        // that reaches the filter chips, and a lone result arrives highlighted,
        // so there Tab only moves the focus. A free-text field's first row is
        // its text, highlighted as it arrives, so Tab leaves it as it leaves the
        // text, and takes a row the reader moved to. Nor is a row taken before
        // the list has caught up with the text: see onEnterKeydown.
        const selected = this.selectedOption
        if (selected && !this.searching && this.formField && selected !== this.lead) this.commit(selected)
    }

    onEnterKeydown = (event) => {
        const selected = this.selectedOption
        // A free-text field sends its text at once, as a plain field would,
        // without waiting for the list: the list is emptied and the key left to
        // the form. Only a row the reader picked other than the text's own
        // (this.lead) is taken, and only from a list that has caught up with
        // the text.
        if (this.freeTextValue && (this.searching || !selected || selected === this.lead)) {
            this.hideAndRemoveOptions()
            return
        }
        if (this.searching) {
            // The list has not caught up with the text. Checked first, because the
            // rows still on screen, and any highlight among them, belong to the
            // previous query: none of them is opened. When a search for this text
            // is on its way, remember the Enter, so that a sole result is opened
            // as it lands. Text too short to search has none coming.
            if (this.inputTarget.value.trim().length >= this.minLengthValue) {
                this.pendingEnter = true
                event.preventDefault()
            }
        } else if (selected && this.resultsShown) {
            this.commit(selected)
            event.preventDefault()
        } else if (this.resultsShown && this.options.length === 1) {
            this.commit(this.options[0])
            event.preventDefault()
        }
    }

    // =========================================================================
    // Focus / Blur
    // =========================================================================

    onInputFocus = () => {
        const query = this.inputTarget.value.trim()
        if (!query && this.recentsKeyValue) {
            this.showRecents()
        }
    }

    onFocusOut = (event) => {
        if (this.mouseDown) return

        // Still inside the component: Tab from the input onto a filter chip, or
        // focus handed back to the input once a chip is picked.
        if (this.element.contains(event.relatedTarget)) return

        // Switching windows fires this too, though focus has not moved.
        if (document.activeElement === event.target) return

        // Select-on-blur: commit the highlighted result when focus leaves the
        // component, or the sole result when nothing is highlighted. Several
        // results with none highlighted are not a choice, so nothing commits.
        // Nor while the list has not caught up with the text: see onEnterKeydown.
        // Opt-in so other autocomplete usages keep their plain blur-to-close
        // behavior.
        if (this.selectOnBlurValue && this.resultsShown && !this.searching) {
            const options = this.options
            const target = this.selectedOption || (options.length === 1 ? options[0] : null)
            if (target && target !== this.lead) this.commit(target)
        }

        // Empty the list, as Escape does, and drop a search still in flight. A
        // list that is only hidden keeps its rows and its highlight, and the next
        // search would show them again until its own results land. After a
        // commit as well: a row that was not taken leaves the list up.
        this.hideAndRemoveOptions()
    }

    // =========================================================================
    // Selection / Commit
    // =========================================================================

    commit(selected) {
        if (selected.getAttribute("aria-disabled") === "true") return

        // Navigate to the result's server-supplied destination, if any (person ->
        // person manage, asset -> ops asset, owned vehicle -> owner vehicle list).
        // Only for navigational pickers (the search modal): form-field autocompletes
        // (hidden target or submit-on-select) fill/submit the value instead.
        const url = selected.getAttribute("data-autocomplete-url")
        if (url && !this.formField) {
            // Emptied, not just closed: a search still out, or an Enter waiting
            // for it, would open a second result on top of this one.
            this.hideAndRemoveOptions()
            if (window.Turbo) {
                window.Turbo.visit(url)
            } else {
                window.location.assign(url)
            }
            return
        }

        if (selected instanceof HTMLAnchorElement) {
            selected.click()
            this.close()
            return
        }

        // The search modal has no field to fill, so a row with no page to open
        // (a fleet vehicle has no owner) is not taken: the list and the text
        // typed stay as they are. The row is highlighted, which a lone row
        // already is unless an Enter was waiting for it (see renderJsonResults).
        if (!this.formField) {
            this.select(selected)
            return
        }

        const textValue = selected.getAttribute("data-autocomplete-label") || selected.textContent.trim()
        const value = selected.getAttribute("data-autocomplete-value") || textValue
        this.inputTarget.value = textValue

        if (this.hasHiddenTarget) {
            this.hiddenTarget.value = value
            this.hiddenTarget.dispatchEvent(new Event("input"))
            this.hiddenTarget.dispatchEvent(new Event("change"))
        } else {
            this.inputTarget.value = value
        }

        // Metadata writeback for JSON mode
        const meta = this.metaOf(selected)
        if (this.responseTypeValue === "json") {
            this.writebackMetadata(meta)
        }

        // Save to recents
        if (this.recentsKeyValue) {
            this.saveRecent({value, label: textValue})
        }

        this.hideAndRemoveOptions()

        if (this.submitOnSelectValue) {
            const form = this.inputTarget.closest("form")
            if (form) {
                Turbo.navigator.submitForm(form)
            }
        } else {
            this.inputTarget.focus()
            this.element.dispatchEvent(
                new CustomEvent("autocomplete.change", {
                    bubbles: true,
                    detail: {value, textValue, selected, meta}
                })
            )
        }
    }

    // A row's meta, as its JSON result gave it (data-autocomplete-meta), or
    // null: the change event carries it, for a host that acts on a row's kind.
    metaOf(selected) {
        try {
            return JSON.parse(selected.getAttribute("data-autocomplete-meta"))
        } catch {
            return null
        }
    }

    writebackMetadata(meta) {
        if (!this.metaMappingValue || !meta) return

        let mapping
        try {
            mapping = JSON.parse(this.metaMappingValue)
        } catch {
            return
        }

        for (const [metaKey, fieldId] of Object.entries(mapping)) {
            if (meta[metaKey] !== undefined) {
                const field = document.getElementById(fieldId)
                if (field) {
                    field.value = meta[metaKey]
                    field.dispatchEvent(new Event("input"))
                    field.dispatchEvent(new Event("change"))
                }
            }
        }
    }

    clear() {
        this.inputTarget.value = ""
        if (this.hasHiddenTarget) this.hiddenTarget.value = ""
    }

    // =========================================================================
    // Mouse Handling
    // =========================================================================

    onResultsClick = (event) => {
        if (!(event.target instanceof Element)) return

        // Handle filter chip clicks
        const filterChip = event.target.closest("[data-autocomplete-filter]")
        if (filterChip) {
            this.handleFilterClick(filterChip)
            return
        }

        const selected = event.target.closest(optionSelector)
        if (selected) this.commit(selected)

        // The list is still up: the bar, a header or a message was clicked, or a
        // row that was not taken. The click took the focus off the input while
        // onFocusOut was looking away (mouseDown). Give it back, so the keys
        // still drive the list and leaving is still seen.
        if (this.resultsShown) this.inputTarget.focus()
    }

    onResultsMouseDown = () => {
        this.mouseDown = true
        // On the document: the button may be let go anywhere. Heard only on the
        // list, a release outside it left the flag up, and onFocusOut looked
        // away from then on.
        document.addEventListener("mouseup", () => {
            this.mouseDown = false
        }, {once: true})
    }

    // =========================================================================
    // Input Change
    // =========================================================================

    // Runs immediately on every keystroke (not debounced). The text has changed,
    // so the rows on screen, and any search still in flight, belong to the previous
    // query. Flag that at once, so Enter is queued and Tab takes nothing until the
    // list has been rendered or emptied for the new text. And disown the search in
    // flight: landing late, it would settle the flag, and spend a queued Enter, on
    // rows that are not for what is typed.
    //
    // The chosen value is cleared here too, not in the debounced handler: the text
    // no longer names it, and a form submitted before the debounce ran would still
    // send it.
    onInputMark = () => {
        this.searching = true
        this.currentRequestId = null
        if (this.hasHiddenTarget) this.hiddenTarget.value = ""
    }

    onInputChange = () => {
        const query = this.inputTarget.value.trim()
        if (query && query.length >= this.minLengthValue) {
            // Typing a new search term is a refresh: drop any active filter chip so
            // the query runs unfiltered. (Chip clicks set filters via handleFilterClick,
            // which fetches directly without going through here.)
            this.activeFilters = {}
            this.fetchResults(query)
        } else {
            // Nothing to search for: empty the list, which settles the flag
            // onInputMark raised and drops a queued Enter. Before the recents,
            // because with none saved showRecents leaves whatever was there.
            this.hideAndRemoveOptions()
            if (!query && this.recentsKeyValue) this.showRecents()
        }
    }

    // =========================================================================
    // Filter Handling
    // =========================================================================

    handleFilterClick(chip) {
        // The fetch below rebuilds the bar and this chip with it, which would drop
        // focus onto the page. Hand it to the input so typing and the arrow keys
        // carry on.
        this.inputTarget.focus()

        const filterKey = chip.getAttribute("data-autocomplete-filter")
        const filterValue = chip.getAttribute("data-autocomplete-filter-value")

        if (this.activeFilters[filterKey] === filterValue) {
            delete this.activeFilters[filterKey]
            chip.classList.remove("ac-filter-chip-active")
        } else {
            // Deactivate siblings
            const siblings = this.resultsTarget.querySelectorAll(`[data-autocomplete-filter="${filterKey}"]`)
            siblings.forEach(s => s.classList.remove("ac-filter-chip-active"))
            this.activeFilters[filterKey] = filterValue
            chip.classList.add("ac-filter-chip-active")
        }

        // Re-fetch with filters
        const query = this.inputTarget.value.trim()
        if (query && query.length >= this.minLengthValue) {
            this.fetchResults(query)
        }
    }

    // =========================================================================
    // Fetching
    // =========================================================================

    identifyOptions() {
        const prefix = this.resultsTarget.id || "autocomplete"
        const optionsWithoutId = this.resultsTarget.querySelectorAll(`${optionSelector}:not([id])`)
        optionsWithoutId.forEach(el => el.id = `${prefix}-option-${Autocomplete.uniqOptionId++}`)
    }

    // The last search again, filter chips and all: a host's Try Again.
    // Replaying a keystroke would drop the chips (onInputChange).
    refetch() {
        const query = this.inputTarget.value.trim()
        if (query.length >= this.minLengthValue) this.fetchResults(query)
    }

    hideAndRemoveOptions() {
        // Abort the search in flight, so its late response cannot show the list
        // again (e.g. Escape pressed while the searching indicator is up), and call
        // off the one still in its debounce, which would show it again as well.
        // Forget a queued Enter, so a sole result of that search is not committed.
        this.cancelPendingRequest()
        this.debouncedInputChange.cancel()
        this.searching = false
        this.pendingEnter = false
        this.lead = null
        this.close()
        this.resultsTarget.innerHTML = ""
    }

    fetchResults = async (query) => {
        if (!this.hasUrlValue) return

        this.cancelPendingRequest()
        this.abortController = new AbortController()

        const url = this.buildURL(query)
        const requestId = crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`
        this.currentRequestId = requestId

        this.searching = true

        try {
            this.element.dispatchEvent(new CustomEvent("autocomplete.loadstart", {bubbles: true}))
            this.showLoading()

            const response = await fetch(url, {
                ...this.optionsForFetch(),
                signal: this.abortController.signal
            }).catch(connectionLost)

            // Stale response guard
            if (this.currentRequestId !== requestId) return

            if (!response.ok) {
                const error = new Error(`Server responded with status ${response.status}`)
                // 401 is a sign-in that has expired (AutocompleteController#request_authentication)
                error.kind = response.status === 401 ? "expired" : "failed"
                throw error
            }

            if (this.responseTypeValue === "json") {
                const data = await response.json().catch(connectionLost)
                if (this.currentRequestId !== requestId) return
                this.renderJsonResults(data)
            } else {
                const html = await response.text().catch(connectionLost)
                if (this.currentRequestId !== requestId) return
                this.replaceResults(html)
            }

            this.element.dispatchEvent(new CustomEvent("autocomplete.load", {bubbles: true}))
        } catch (error) {
            // Aborted, or no longer the search for the text typed (disowned by a
            // keystroke): its failure is not shown over the search to come.
            if (error.name === "AbortError" || this.currentRequestId !== requestId) return

            // kind is "offline", "expired" or "failed" (anything else, an
            // unreadable answer included). A host that says so itself (the
            // search bar) cancels the event, and the list just goes.
            const shown = this.element.dispatchEvent(new CustomEvent("autocomplete.error", {
                bubbles: true, cancelable: true, detail: {error, kind: error.kind || "failed"}
            }))
            if (shown) {
                this.showError()
            } else {
                this.close()
                this.resultsTarget.innerHTML = ""
            }
        } finally {
            // Only the request still owned settles the in-flight state; one that
            // was superseded, or disowned by a keystroke, must not clear the flags
            // out from under the search for the text now typed.
            if (this.currentRequestId === requestId) {
                this.searching = false
                this.consumePendingEnter()
            }
            this.hideLoading()
            this.element.dispatchEvent(new CustomEvent("autocomplete.loadend", {bubbles: true}))
        }
    }

    // If Enter was pressed while the fetch was in flight, auto-select the sole
    // result now that it has rendered, then clear the pending flag.
    consumePendingEnter() {
        if (!this.pendingEnter) return
        this.pendingEnter = false
        if (this.resultsShown && this.options.length === 1) {
            this.commit(this.options[0])
        }
    }

    buildURL(query) {
        const url = new URL(this.urlValue, window.location.href)
        const params = new URLSearchParams(url.search.slice(1))
        params.append(this.queryParamValue, query)

        if (this.modeValue) {
            params.append("mode", this.modeValue)
        }

        if (this.limitValue) {
            params.append("limit", this.limitValue.toString())
        }

        if (Object.keys(this.activeFilters).length > 0) {
            params.append("filters", JSON.stringify(this.activeFilters))
        }

        url.search = params.toString()
        return url.toString()
    }

    // =========================================================================
    // HTML Mode Rendering (legacy)
    // =========================================================================

    replaceResults(html) {
        this.resultsTarget.innerHTML = html
        this.identifyOptions()
        if (this.options.length) {
            this.open()
        } else {
            this.close()
        }
    }

    // =========================================================================
    // JSON Mode Rendering
    // =========================================================================

    renderJsonResults(data) {
        this.resultsTarget.innerHTML = ""

        const {items, groups, filters, empty_text, flat_item_ids} = data

        // Sync activeFilters with server-provided filter state.
        // Only reset when server provides filter definitions. When server returns
        // empty filters but client has active filters, preserve client state
        // (the server may be returning flat results for a filtered query).
        if (filters && filters.length > 0) {
            const serverActive = {}
            filters.forEach(f => {
                const active = f.options.find(o => o.active)
                if (active) serverActive[f.key] = active.value
            })
            this.activeFilters = serverActive
        } else if (Object.keys(this.activeFilters).length === 0) {
            this.activeFilters = {}
        }

        if (!items || items.length === 0) {
            this.showEmpty(empty_text || "No results found")
            this.open()
            return
        }

        const itemMap = new Map(items.map(item => [item.id, item]))
        const fragment = document.createDocumentFragment()

        // Render filter chips
        if (filters && filters.length > 0) {
            fragment.appendChild(this.renderFilters(filters))
        }

        // Render grouped or flat results
        if (groups && groups.length > 0) {
            groups.forEach(group => {
                fragment.appendChild(this.renderGroup(group, itemMap))
            })
        } else if (flat_item_ids) {
            const list = document.createElement("div")
            list.setAttribute("role", "listbox")
            flat_item_ids.forEach(id => {
                const item = itemMap.get(id)
                if (item) list.appendChild(this.renderItem(item))
            })
            fragment.appendChild(list)
        }

        // Keyboard help footer
        if (this.hasKeyboardHelpTarget) {
            this.keyboardHelpTarget.hidden = false
        } else {
            fragment.appendChild(this.renderKeyboardHelp())
        }

        this.resultsTarget.appendChild(fragment)
        this.identifyOptions()
        this.open()

        // A lone result is pre-highlighted (selected, not navigated) so the user can
        // confirm it and press Enter to open it, and a free-text field's first row,
        // the text itself. Skip if an Enter was queued mid-fetch (consumePendingEnter
        // will commit it) to avoid a flash of selection. Nothing is scrolled into
        // view for it: the row is the list's first, at its top, and a list placed
        // above the field can reach past the top of the page's scroller, which
        // scrollIntoView would move.
        const opts = this.options
        this.lead = this.freeTextValue ? opts[0] : null
        if (opts.length && (opts.length === 1 || this.freeTextValue) && !this.pendingEnter) {
            this.select(opts[0], {scroll: false})
            this.resultsTarget.scrollTop = 0
        }

        // Announce result count to screen readers
        this.announceResults(items.length)
    }

    renderFilters(filters) {
        const container = document.createElement("div")
        container.className = "ac-filter-bar"
        container.setAttribute("role", "toolbar")
        container.setAttribute("aria-label", "Filter results")

        filters.forEach(filter => {
            filter.options.forEach(option => {
                const chip = document.createElement("button")
                chip.type = "button"
                // Whole class names only, never glued to a ${} placeholder: Tailwind
                // compiles an @utility only when it reads the name as a complete word.
                chip.className = option.active ? "ac-filter-chip ac-filter-chip-active" : "ac-filter-chip"
                chip.setAttribute("data-autocomplete-filter", filter.key)
                chip.setAttribute("data-autocomplete-filter-value", option.value)
                chip.textContent = option.label
                if (option.count !== undefined) {
                    const count = document.createElement("span")
                    count.className = "ac-filter-count"
                    count.textContent = option.count
                    chip.appendChild(count)
                }
                container.appendChild(chip)

                if (option.active) {
                    this.activeFilters[filter.key] = option.value
                }
            })
        })

        return container
    }

    // A group with no title has no header and is no group, only rows of the
    // list: the mailbox search's own row, which stands for the text.
    renderGroup(group, itemMap) {
        const container = document.createElement("div")
        container.className = "ac-group"

        if (group.title) {
            const header = document.createElement("div")
            header.className = "ac-group-header"
            header.setAttribute("role", "presentation")
            header.textContent = group.title
            container.appendChild(header)
        }

        const list = document.createElement("div")
        if (group.title) {
            list.setAttribute("role", "group")
            list.setAttribute("aria-label", group.title)
        }

        group.item_ids.forEach(id => {
            const item = itemMap.get(id)
            if (item) list.appendChild(this.renderItem(item))
        })

        container.appendChild(list)
        return container
    }

    renderItem(item) {
        const option = document.createElement("div")
        option.setAttribute("role", "option")
        option.setAttribute("data-autocomplete-value", item.value)
        option.setAttribute("data-autocomplete-label", item.label)
        option.className = "ac-option"

        if (item.meta) {
            option.setAttribute("data-autocomplete-meta", JSON.stringify(item.meta))
        }

        if (item.url) {
            option.setAttribute("data-autocomplete-url", item.url)
        }

        if (item.html) {
            option.innerHTML = item.html
        } else {
            option.textContent = item.label
        }

        return option
    }

    renderKeyboardHelp() {
        const footer = document.createElement("div")
        footer.className = "ac-keyboard-help"
        footer.setAttribute("aria-hidden", "true")
        footer.innerHTML = `<span><kbd>\u2191</kbd><kbd>\u2193</kbd> navigate</span>` +
            `<span><kbd>\u21B5</kbd> select</span>` +
            `<span><kbd>esc</kbd> close</span>`
        return footer
    }

    // =========================================================================
    // State indicators
    // =========================================================================

    showLoading() {
        // Inline (modal) variant: the searching indicator takes over the chip-row
        // slot rather than appearing as a separate row, so the chips area doesn't
        // jitter. Other variants keep the standalone loading row.
        if (this.inlineValue) {
            this.showSearchingBar()
            return
        }
        if (this.hasLoadingTarget) {
            this.loadingTarget.hidden = false
        }
    }

    // Render the "Searching..." indicator in the filter-bar slot at the top of the
    // result list. When chips are already shown, replace them in place and freeze the
    // row to their exact height so the swap to/from the indicator can't jitter. The
    // next render (renderJsonResults / showEmpty / showError) clears it and rebuilds
    // the chips.
    showSearchingBar() {
        const existing = this.resultsTarget.querySelector(".ac-filter-bar")

        const bar = document.createElement("div")
        bar.className = "ac-filter-bar"
        bar.setAttribute("role", "status")
        bar.innerHTML = `<span class="ac-searching">` +
            `<i class="fa-solid fa-spinner animate-spin me-1" aria-hidden="true"></i>Searching…</span>`

        // Still up after SLOW_SEARCH_MS, the row says why. It goes with the next
        // render, or the list emptied, and its timer then finds it gone.
        setTimeout(() => {
            if (bar.isConnected) {
                bar.querySelector(".ac-searching").lastChild.nodeValue =
                    "Still searching. Your connection may be slow."
            }
        }, SLOW_SEARCH_MS)

        if (existing) {
            // A chip holding the focus goes with the old bar, and the browser
            // reports that as focus leaving the component. Hand it to the input.
            if (existing.contains(document.activeElement)) this.inputTarget.focus()

            bar.style.minHeight = `${existing.offsetHeight}px`
            existing.replaceWith(bar)
        } else {
            this.resultsTarget.prepend(bar)
            this.open()
        }
    }

    hideLoading() {
        if (this.hasLoadingTarget) {
            this.loadingTarget.hidden = true
        }
    }

    showEmpty(text) {
        const emptyEl = document.createElement("div")
        emptyEl.className = "ac-empty"
        emptyEl.setAttribute("role", "status")
        emptyEl.textContent = text
        this.resultsTarget.appendChild(emptyEl)
    }

    showError() {
        this.resultsTarget.innerHTML = ""
        const errorEl = document.createElement("div")
        errorEl.className = "ac-error"
        errorEl.setAttribute("role", "alert")
        errorEl.textContent = "Search failed. Please try again."
        this.resultsTarget.appendChild(errorEl)
        this.open()
    }

    announceResults(count) {
        let announcer = document.getElementById("ac-live-region")
        if (!announcer) {
            announcer = document.createElement("div")
            announcer.id = "ac-live-region"
            announcer.setAttribute("role", "status")
            announcer.setAttribute("aria-live", "polite")
            announcer.setAttribute("aria-atomic", "true")
            announcer.className = "sr-only"
            document.body.appendChild(announcer)
        }
        announcer.textContent = `${count} result${count === 1 ? "" : "s"} available`
    }

    // =========================================================================
    // Recents (localStorage)
    // =========================================================================

    // A recent is no search's result, so a free-text field's lead row is none
    // of them.
    showRecents() {
        const recents = this.getRecents()
        if (recents.length === 0) return

        this.lead = null
        this.resultsTarget.innerHTML = ""
        const fragment = document.createDocumentFragment()

        const header = document.createElement("div")
        header.className = "ac-group-header"
        header.setAttribute("role", "presentation")
        header.textContent = "Recent"
        fragment.appendChild(header)

        const list = document.createElement("div")
        list.setAttribute("role", "listbox")

        recents.forEach(recent => {
            const option = document.createElement("div")
            option.setAttribute("role", "option")
            option.setAttribute("data-autocomplete-value", recent.value)
            option.setAttribute("data-autocomplete-label", recent.label)
            option.className = "ac-option"
            option.textContent = recent.label
            list.appendChild(option)
        })

        fragment.appendChild(list)
        this.resultsTarget.appendChild(fragment)
        this.identifyOptions()
        this.open()
    }

    getRecents() {
        if (!this.recentsKeyValue) return []
        try {
            return JSON.parse(localStorage.getItem(`ac-recents-${this.recentsKeyValue}`)) || []
        } catch {
            return []
        }
    }

    saveRecent(item) {
        if (!this.recentsKeyValue) return
        const key = `ac-recents-${this.recentsKeyValue}`
        let recents = this.getRecents()
        recents = recents.filter(r => r.value !== item.value)
        recents.unshift(item)
        recents = recents.slice(0, this.maxRecentsValue)
        try {
            localStorage.setItem(key, JSON.stringify(recents))
        } catch {
            // localStorage full or unavailable
        }
    }

    // =========================================================================
    // Open / Close
    // =========================================================================

    open() {
        if (this.resultsShown) {
            // New rows in a list already open, maybe more of them than the side
            // it was placed on has room for: placed again for their height.
            if (!this.inlineValue) this.updatePlacement()
            return
        }

        // Shown before it is placed, so the placement reads the list's own height.
        this.resultsShown = true
        // Inline (embedded) results render in normal flow inside their container
        // (e.g. the search modal body), so skip the floating above/below flip.
        if (!this.inlineValue) {
            this.updatePlacement()
        }
        this.element.setAttribute("aria-expanded", "true")
        this.element.dispatchEvent(
            new CustomEvent("autocomplete.open", {
                bubbles: true,
                detail: {inputTarget: this.inputTarget, resultsTarget: this.resultsTarget}
            })
        )
    }

    // Below the field, unless the list does not fit there and there is more room
    // above, and cut to the room on its side, where it scrolls. The room is the
    // part of the page on screen (visibleBounds), so an on-screen keyboard never
    // hides the list. It is measured from the box the list hangs from, whose
    // edges .ac-results and .ac-results-above take: its offsetParent, the
    // component itself, or the chips box around it (shared/_autocomplete's
    // positioned: false), where chips can wrap the text to a lower line.
    updatePlacement() {
        const results = this.resultsTarget
        const box = results.offsetParent ?? this.inputTarget
        const rect = box.getBoundingClientRect()
        const {top, bottom} = this.visibleBounds()
        // The room is measured as drawn, after any CSS zoom around the field (the
        // HQ shell's), and the list is sized in its own pixels, which the zoom
        // draws larger: the room is divided by it.
        const zoom = box.offsetHeight ? rect.height / box.offsetHeight : 1
        const spaceBelow = (bottom - rect.bottom) / zoom
        const spaceAbove = (rect.top - top) / zoom
        const above = spaceBelow < Math.min(results.scrollHeight, LIST_MAX) && spaceAbove > spaceBelow

        results.classList.toggle("ac-results-above", above)
        // The floor only where it fits: the list never runs past what is on screen.
        const space = above ? spaceAbove : spaceBelow
        const room = Math.max(space - LIST_GAP, Math.min(LIST_FLOOR, space - LIST_MARGIN))
        results.style.maxHeight = `${Math.max(Math.min(room, LIST_MAX), 0)}px`
    }

    // What of the page is on screen, top and bottom, in the field's coordinates:
    // the visual viewport, which an on-screen keyboard shrinks (iPad Safari's
    // window.innerHeight does not follow it), less what the nearest box
    // around the field that clips its overflow cuts off, such as the page's
    // scroller under the sticky navbar. Its top is pageTop less scrollY, not
    // offsetTop: once iPad Safari scrolls the page for the keyboard (landscape),
    // offsetTop counts from the top of the page, where the rects count from the
    // top of the screen.
    visibleBounds() {
        const viewport = window.visualViewport
        const top = viewport ? viewport.pageTop - window.scrollY : 0
        const bottom = viewport ? top + viewport.height : window.innerHeight
        for (let box = this.element.parentElement; box; box = box.parentElement) {
            if (getComputedStyle(box).overflowY !== "visible") {
                const clip = box.getBoundingClientRect()
                return {top: Math.max(top, clip.top), bottom: Math.min(bottom, clip.bottom)}
            }
        }
        return {top, bottom}
    }

    close() {
        if (!this.resultsShown) return

        this.resultsShown = false
        this.inputTarget.removeAttribute("aria-activedescendant")
        this.element.setAttribute("aria-expanded", "false")
        this.element.dispatchEvent(
            new CustomEvent("autocomplete.close", {
                bubbles: true,
                detail: {inputTarget: this.inputTarget, resultsTarget: this.resultsTarget}
            })
        )
    }

    get resultsShown() {
        return !this.resultsTarget.hidden
    }

    set resultsShown(value) {
        this.resultsTarget.hidden = !value
    }

    get options() {
        return Array.from(this.resultsTarget.querySelectorAll(optionSelector))
    }

    get selectedOption() {
        return this.resultsTarget.querySelector(activeSelector)
    }

    // A form-field autocomplete has a hidden target to put the chosen value in,
    // a form to submit on select, or says it is one (form-field value: the
    // callsign chips, which take the value from autocomplete.change). The one
    // picker with none is the search modal, which opens the chosen row's page.
    get formField() {
        return this.hasHiddenTarget || this.submitOnSelectValue || this.formFieldValue
    }

    get selectedClassesOrDefault() {
        return this.hasSelectedClass ? this.selectedClasses : ["ac-option-active"]
    }

    optionsForFetch() {
        return {
            headers: {
                "X-Requested-With": "XMLHttpRequest",
                "Accept": this.responseTypeValue === "json" ? "application/json" : "text/html"
            }
        }
    }
}
