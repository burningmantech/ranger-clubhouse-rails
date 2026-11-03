// StimulusJS controller for dynamic country-based state/province selection

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ["state", "country"]
    static values = {
        states: Object,
        initial: String,
    }

    // State/province options loaded from server via data attribute
    // Format: { states: {...}, labels: {...}, prompts: {...} }
    get stateOptions() {
        return this.statesValue?.states || {}
    }

    get labels() {
        return this.statesValue?.labels || {}
    }

    connect() {
        this.labelElement = this.element.querySelector(`label[for="${this.stateTarget.id}"]`);
        this.buildStateField(this.countryTarget.value, this.initialValue);
    }

    /**
     * Updates the state field based on selected country - call when country field changes
     */
    updateStateField(event) {
        this.buildStateField(this.countryTarget.value, this.stateTarget.value);
    }

    buildStateField(countryCode, currentValue) {
        // Check if country has state/province options
        if (this.stateOptions[countryCode]) {
            this.enableStateField(countryCode, currentValue);
        } else {
            this.disableStateField()
        }

    }

    /**
     * Enable and populate the state field with options for the selected country
     */
    enableStateField(countryCode, currentValue = "") {
        const stateField = this.stateTarget

        // Enable the field
        stateField.disabled = false
        this.removeClearedStateField()

        // The blank option first, then the country's
        stateField.replaceChildren(new Option("-", ""))

        if (this.labelElement) {
            this.renameLabel(this.labels[countryCode] || "State")
            this.labelElement.classList.remove("opacity-60")
        }

        // The previous selection is kept where it exists among the new options
        const options = this.stateOptions[countryCode] || []
        options.forEach(option => {
            stateField.appendChild(new Option(option.label, option.value, false, option.value === currentValue))
        })

        // If the current value wasn't found in the new options, reset to first option
        if (currentValue && !options.find(opt => opt.value === currentValue)) {
            stateField.value = ""
        }
    }

    /**
     * Disable the state field for countries without defined states/provinces
     */
    disableStateField() {
        const stateField = this.stateTarget

        this.labelElement?.classList.add("opacity-60")

        // Disable the field
        stateField.disabled = true

        // Only the blank option
        stateField.replaceChildren(new Option("-", ""))

        // Reset value
        stateField.value = ""

        this.addClearedStateField()
    }

    /**
     * A greyed-out field sends nothing when the form is saved, so a state picked
     * for an earlier country would stay on file for a country that has none.
     * This sends an empty state in its place, which clears it.
     */
    addClearedStateField() {
        if (this.clearedStateField) return

        this.clearedStateField = document.createElement("input")
        this.clearedStateField.type = "hidden"
        this.clearedStateField.name = this.stateTarget.name
        this.clearedStateField.value = ""
        this.stateTarget.after(this.clearedStateField)
    }

    removeClearedStateField() {
        this.clearedStateField?.remove()
        this.clearedStateField = null
    }

    disconnect() {
        this.removeClearedStateField()
    }

    /**
     * Renames the field for the country without disturbing anything else its
     * label carries. The marker saying the field has to be answered sits inside
     * the label beside the name, and writing the whole label as text throws it
     * away -- so only the name itself is rewritten.
     */
    renameLabel(text) {
        const name = this.labelElement.firstChild

        if (name && name.nodeType === Node.TEXT_NODE) {
            name.nodeValue = text
        } else {
            this.labelElement.prepend(text)
        }
    }
}

