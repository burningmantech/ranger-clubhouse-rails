import {Controller} from "@hotwired/stimulus"
import {get} from "@rails/request.js"

// Connects to data-controller="tabs"
// Hybrid DaisyUI/Stimulus tabs implementation
export default class extends Controller {
    static values = {
        activeClasses: {type: String, default: ""},
        inactiveClasses: {type: String, default: ""}
    }

    connect() {
        // Set initial ARIA states
        this.updateARIA()

        this.handleKeydown = this.handleKeydown.bind(this)
        this.element.addEventListener("keydown", this.handleKeydown)
    }

    disconnect() {
        this.element.removeEventListener("keydown", this.handleKeydown)
    }

    // The tablist keys: only the selected tab is in the Tab order (roving
    // tabindex), and the arrows, Home and End move along the list, selecting
    // the tab they land on as a click would.
    handleKeydown(event) {
        // A tablist nested in this one has answered already.
        if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return

        const tab = event.target.closest("[role=\"tab\"]")
        const list = tab?.closest("[role=\"tablist\"]")
        if (!list) return

        const next = tablistKeyTarget(event.key, tab, list)
        if (!next) return

        event.preventDefault()
        next.focus()
        next.click()
    }

    get activeClassList() {
        return this.activeClassesValue.split(" ").filter(c => c.length > 0)
    }

    get inactiveClassList() {
        return this.inactiveClassesValue.split(" ").filter(c => c.length > 0)
    }

    async show(event) {
        const clickedTab = event.currentTarget
        // Support DaisyUI convention: data-tabs-target="#panel-id"
        const tabsTarget = clickedTab.dataset.tabsTarget
        // Strip leading # if present (DaisyUI convention)
        const panelId = tabsTarget?.startsWith("#") ? tabsTarget.slice(1) : tabsTarget

        // Find the target panel
        const targetPanel = document.getElementById(panelId)
        if (!targetPanel) return

        // Update all tabs and panels
        this.deactivateAll()
        this.activateTab(clickedTab)
        this.activatePanel(targetPanel)

        // Update ARIA states
        this.updateARIA()

        // The controller owns the click: a static tab has nothing to fetch,
        // and a remote one must not also be followed as a link.
        event.preventDefault()
        if (!clickedTab.dataset.remoteTab) return

        // A remote tab answers with a turbo stream, which renders itself.
        const response = await get(clickedTab.getAttribute("href"), {responseKind: "turbo-stream"})
        if (!response.ok) {
            console.error("Request failed")
        }
    }

    deactivateAll() {
        // Deactivate all tabs
        const tabs = this.element.querySelectorAll("[role=\"tab\"]")
        tabs.forEach(tab => {
            tab.classList.remove(...this.activeClassList)
            tab.classList.add(...this.inactiveClassList)
            tab.setAttribute("aria-selected", "false")
            tab.setAttribute("tabindex", "-1")
        })

        // Hide all panels
        const panels = this.element.querySelectorAll("[role=\"tabpanel\"]")
        panels.forEach(panel => {
            panel.classList.add("hidden")
        })
    }

    activateTab(tab) {
        tab.classList.remove(...this.inactiveClassList)
        tab.classList.add(...this.activeClassList)
        tab.setAttribute("aria-selected", "true")
        tab.setAttribute("tabindex", "0")
    }

    activatePanel(panel) {
        panel.classList.remove("hidden")
    }

    updateARIA() {
        const activeTabs = this.element.querySelectorAll("[role=\"tab\"][aria-selected=\"true\"]")
        activeTabs.forEach(tab => {
            tab.setAttribute("tabindex", "0")
        })

        const inactiveTabs = this.element.querySelectorAll("[role=\"tab\"][aria-selected=\"false\"]")
        inactiveTabs.forEach(tab => {
            tab.setAttribute("tabindex", "-1")
        })
    }
}

// The tab a tablist key moves to from +tab+, or null for any other key.
// Left and Right wrap around the ends.
export function tablistKeyTarget(key, tab, list) {
    const tabs = [...list.querySelectorAll("[role=\"tab\"]")].filter((each) => each.closest("[role=\"tablist\"]") === list)
    const index = tabs.indexOf(tab)

    switch (key) {
        case "ArrowLeft": return tabs[(index - 1 + tabs.length) % tabs.length]
        case "ArrowRight": return tabs[(index + 1) % tabs.length]
        case "Home": return tabs[0]
        case "End": return tabs[tabs.length - 1]
        default: return null
    }
}
