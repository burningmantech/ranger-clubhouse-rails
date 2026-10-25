import { Controller } from "@hotwired/stimulus"

// How long the tip stays up.
const TIP_MS = 2000

// Whether the browser can pin a popover to the control that opened it.
const ANCHORED = CSS.supports("anchor-scope", "--copy-tip")

export default class extends Controller {
    static values = { content: String }
    static classes = [ "success" ]

    connect() {
        this.iconElement = this.element.querySelector("i")
    }

    disconnect() {
        this.#hideTip()
    }

    async copy(event) {
        event.preventDefault()
        this.reset()

        try {
            await navigator.clipboard.writeText(this.contentValue)
            this.iconElement.classList.add(this.successClass)
            this.#showTip()
        } catch {}
    }

    reset() {
        this.#hideTip()
        this.iconElement.classList.remove(this.successClass)
        this.#forceReflow()
    }

    // The tip goes inside the control. buttons.css places it, and says why it
    // is a popover where the browser can anchor one.
    //
    // Inside the control it would be read out as part of the control's name, so
    // it is hidden from screen readers, and they are told by a line added to
    // the layout's live region. A line of its own, so that a second copy is
    // announced while the first is still up.
    //
    // Whatever is up comes down first. Two presses can both be waiting on the
    // clipboard, and the second would otherwise leave the first one's tip on
    // the page for good.
    #showTip() {
        this.#hideTip()

        const tip = document.createElement("span")
        tip.className = "copy-tip"
        tip.textContent = "Copied"
        tip.setAttribute("aria-hidden", "true")

        const line = document.createElement("div")
        line.textContent = tip.textContent

        this.shown = [ tip, line ]
        this.timer = setTimeout(() => this.#hideTip(), TIP_MS)

        document.getElementById("live-region")?.append(line)
        this.element.append(tip)
        if (ANCHORED) {
            tip.setAttribute("popover", "manual")
            tip.showPopover()
        }
    }

    #hideTip() {
        clearTimeout(this.timer)
        this.shown?.forEach((node) => node.remove())
    }

    #forceReflow() {
        this.iconElement.offsetWidth
    }
}
