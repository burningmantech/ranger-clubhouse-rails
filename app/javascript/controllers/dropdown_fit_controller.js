import {Controller} from "@hotwired/stimulus"

// Connects to data-controller="dropdown-fit", on a row of <details> dropdowns
// whose panels carry the `left-(--dropdown-fit-shift)` utility; each <details>
// takes data-action="toggle->dropdown-fit#fit".
//
// daisyUI hangs a panel off its trigger's left edge, so a trigger near the
// right of the row pushed the panel past the content's edge and scrolled the
// page sideways -- 90px on a phone. On opening, the panel moves left by just
// what it would overflow, so its right edge meets the row's. daisyUI's
// dropdown-end moves it further, to the trigger's right edge, which on a
// 320px phone would push the third letter's panel off the left of the screen.
//
// offsetWidth, not the panel's rect: toggle fires while daisyUI's scale-in is
// running, and the rect is 5% short.
export default class extends Controller {
    fit({target}) {
        if (!target.open) return

        const panel = target.querySelector(".dropdown-content")
        const overflow = target.getBoundingClientRect().left + panel.offsetWidth - this.element.getBoundingClientRect().right

        panel.style.setProperty("--dropdown-fit-shift", `${-Math.max(overflow, 0)}px`)
    }
}
