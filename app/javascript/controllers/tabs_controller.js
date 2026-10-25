import {Controller} from "@hotwired/stimulus"
import {get} from "@rails/request.js"

// Connects to data-controller="tabs"
// Hybrid DaisyUI/Stimulus tabs implementation
export default class extends Controller {
    static targets = ["tab", "panel"]
    static values = {
        activeClasses: {type: String, default: ""},
        inactiveClasses: {type: String, default: ""}
    }

    connect() {
        // Set initial ARIA states
        this.updateARIA()
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
