// Stimulus controller for Vanilla Calendar Pro datetime picker
// Documentation: https://vanilla-calendar.pro/docs/learn
// ES6+ features: async/await, object destructuring, optional chaining, class fields

import {Controller} from "@hotwired/stimulus"
import {Calendar} from "vanilla-calendar-pro"

export default class extends Controller {
    static values = {
        options: {type: Object, default: {}}
    }

    /**
     * Initialize calendar on the element when controller connects
     * On mobile devices, switches to native datetime-local input instead
     */
    connect() {
        if (this.isMobileDevice()) {
            this.useNativeDatetimeInput()
            return
        }
        this.initializeCalendar()
    }

    /**
     * Clean up calendar instance when controller disconnects
     * Prevents memory leaks and ensures proper cleanup during Turbo navigation
     */
    disconnect() {
        this.destroyCalendar()
    }

    /**
     * Initialize Vanilla Calendar Pro with merged default and custom options
     */
    initializeCalendar() {
        const defaultOptions = {
            selectionTimeMode: 24,
            inputMode: true,
            positionToInput: "auto",
            selectedTheme: "system",
            firstWeekday: 0, // Sunday
            // Custom layout with close button
            layouts: {
                default: this.buildLayoutWithCloseButton()
            },
            // Format date and time for the input
            onChangeToInput: (calendar, event) => {
                this.updateInputValue(calendar)
            },
            // Attach close button handler after calendar shows
            onShow: (calendar) => {
                this.attachCloseButtonHandler(calendar)
            }
        }

        const selection = this.selectionFromInputValue()
        if (selection.selectedDates) {
            const date = selection.selectedDates[0]
            this.element.value = selection.selectedTime ? `${date} ${selection.selectedTime}` : date
        }

        const mergedOptions = {...defaultOptions, ...this.optionsValue, ...selection}
        this.calendar = new Calendar(this.element, mergedOptions)
        this.calendar.init()
    }

    /**
     * Build the default layout with an added close button at the bottom
     * @returns {string} HTML layout template
     */
    buildLayoutWithCloseButton() {
        return `
            <div class="vc-header" data-vc="header" role="toolbar">
                <#ArrowPrev [month] />
                <div class="vc-header__content" data-vc-header="content">
                    <#Month />
                    <#Year />
                </div>
                <#ArrowNext [month] />
            </div>
            <div class="vc-wrapper" data-vc="wrapper">
                <#WeekNumbers />
                <div class="vc-content" data-vc="content">
                    <#Week />
                    <#Dates />
                    <#DateRangeTooltip />
                </div>
            </div>
            <#ControlTime />
            <div class="vc-footer" data-vc="footer">
                <button type="button" class="vc-close-btn" data-vc-close aria-label="Close calendar">Close</button>
            </div>
        `
    }

    /**
     * Parse the input's existing value so the calendar opens on it
     * Accepts "YYYY-MM-DD", "YYYY-MM-DD HH:MM[:SS ...]", or ISO "T" separator
     * @returns {Object} selectedDates/Month/Year/Time options, or {} if blank/unparseable
     */
    selectionFromInputValue() {
        const match = this.element.value.match(/^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}:\d{2}))?/)
        if (!match) {
            return {}
        }

        const [, year, month, day, time] = match
        const selection = {
            selectedDates: [`${year}-${month}-${day}`],
            selectedMonth: Number(month) - 1,
            selectedYear: Number(year)
        }
        if (time) {
            selection.selectedTime = time
        }
        return selection
    }

    /**
     * Attach click handler to the close button
     * @param {Calendar} calendar - The calendar instance
     */
    attachCloseButtonHandler(calendar) {
        const closeBtn = calendar.context.mainElement?.querySelector("[data-vc-close]")
        if (closeBtn) {
            closeBtn.addEventListener("click", (event) => {
                event.stopPropagation()
                calendar.hide()
            })
        }
    }

    /**
     * Update the input value with selected date and time
     * @param {Calendar} calendar - The calendar instance
     */
    updateInputValue(calendar) {
        const {selectedDates, selectedTime} = calendar.context

        if (!selectedDates?.length) {
            this.element.value = ""
            return
        }

        const selectedDate = selectedDates[0]
        this.element.value = selectedTime ? `${selectedDate} ${selectedTime}` : selectedDate
    }

    /**
     * Destroy calendar instance and clean up resources
     */
    destroyCalendar() {
        if (this.calendar) {
            this.calendar.destroy()
            this.calendar = null
        }
    }

    /**
     * Check if the current device is a mobile device
     * Uses multiple detection methods for reliability
     * @returns {boolean} True if running on a mobile device
     */
    isMobileDevice() {
        // Check for touch capability and screen size
        // const hasTouchScreen = "ontouchstart" in window || navigator.maxTouchPoints > 0
        const isSmallScreen = window.innerWidth <= 768

        // User agent detection for mobile devices
        const mobileUserAgentPattern = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i

        return isSmallScreen || mobileUserAgentPattern.test(navigator.userAgent)
    }

    /**
     * Convert the input to a native datetime-local input for mobile devices
     * This provides a better UX with the native date/time picker
     * The datetime-local type does not include timezone information
     */
    useNativeDatetimeInput() {
        const match = this.element.value.match(/^(\d{4}-\d{2}-\d{2})(?:[T ](\d{2}:\d{2}))?/)
        this.element.type = "datetime-local"
        if (match) {
            this.element.value = `${match[1]}T${match[2] || "00:00"}`
        }
    }

    /**
     * Programmatically show the calendar
     */
    show() {
        this.calendar?.show()
    }

    /**
     * Programmatically hide the calendar
     */
    hide() {
        this.calendar?.hide()
    }

    /**
     * Reinitialize calendar when options value changes
     */
    optionsValueChanged() {
        if (this.calendar && !this.isMobileDevice()) {
            this.destroyCalendar()
            this.initializeCalendar()
        }
    }
}

