import { Controller } from "@hotwired/stimulus"
import { driver } from "driver.js"
import { patch } from "@rails/request.js"
import { scrollParent } from "controllers/scrolling"

// The first-sign-in tour (me/dashboard/_onboarding). Each step is a <template>
// target: data-element names what it points at (none: a centered popover),
// data-title and data-side the popover, and its content is the description.
// A selector resolves to its first visible match -- the hamburger below lg,
// the open sidebar above it; a selector list for the two Menu buttons -- and
// a step whose selector has no visible element is dropped, so one list serves
// every layout and a dashboard without a Links & Things section.
//
// Next and Back scroll the coming step's element to the middle of the pane
// themselves, smoothly, then move once the scroll ends. driver's own scroll is
// instant unless its smoothScroll option is on, and with it on the popover
// would land where the element was mid-glide: driver places the popover once
// and re-places it only on window scroll or resize, never on a scroll of the
// pane everything on /me scrolls in. One wait at a time: a click while one is
// pending is ignored, and finish cancels it.
//
// Every way the tour ends in the page (Done, the close button, Escape, a Turbo
// visit away) reports it once to the url value, so a dismissed tour does not
// come back at each sign-in; a full-page reload mid-tour records nothing. A
// replay (/me?tour=1) carries no url and writes nothing. The hook is
// onDestroyStarted, not onDestroyed: driver.js skips the latter when the tour
// is destroyed before the current step's highlight has settled (a quick ×),
// and with the former set it leaves the destroying to the caller. finish is
// also the turbo:before-cache action: a tour still open then would be cached,
// overlay and all, and shown again on Back.
export default class extends Controller {
  static targets = ["step", "toast"]
  static values = { url: String }

  connect() {
    // The smooth scrolls are the tour's only motion; driver's own fade and
    // cutout glide stay off, as the design guide keeps motion to its approved
    // set.
    this.smooth = !matchMedia("(prefers-reduced-motion: reduce)").matches
    this.driver = driver({
      steps: this.stepTargets.flatMap((template) => this.step(template)),
      showProgress: true,
      disableActiveInteraction: true,
      animate: false,
      // A click on the dimmed page closes nothing: the second click of a
      // double-click lands there while driver swaps popovers. The × and Escape
      // still close.
      overlayClickBehavior: "none",
      prevBtnText: "Back",
      closeBtnLabel: "Skip the tour",
      onPopoverRender: (popover) => this.dress(popover),
      // On the last step driver's own moveNext ends the tour with reason "done".
      onNextClick: () => this.toward(this.driver.getNextStep(), () => this.driver.moveNext()),
      onPrevClick: () => this.toward(this.previousStep(), () => this.driver.movePrevious()),
      onDestroyStarted: (_element, _step, { reason }) => this.finish(reason)
    })
    this.driver.drive()
  }

  disconnect() {
    this.finish()
  }

  step(template) {
    const { element: selector, title, side } = template.dataset
    const element = selector && this.visible(selector)
    if (selector && !element) return []
    // driver writes the title as HTML, and the callsign in it is text.
    return [{ element, popover: { title: this.escape(title), description: template.innerHTML, side } }]
  }

  escape(text) {
    const p = document.createElement("p")
    p.textContent = text
    return p.innerHTML
  }

  // driver's getPreviousStep is the step last left, not the one before.
  previousStep() {
    return this.driver.getConfig("steps")[this.driver.getActiveIndex() - 1]
  }

  // Scroll the step's element to the middle of the pane, then move. In view
  // already (or no element: a centered popover) means moving at once.
  toward(step, move) {
    if (this.pending) return

    const target = step?.element
    if (!target || this.inView(target)) return move()

    target.scrollIntoView({ behavior: this.smooth ? "smooth" : "auto", block: "center" })
    this.afterScroll(() => { if (this.driver) move() })
  }

  inView(element) {
    const { top, bottom } = element.getBoundingClientRect()
    return top >= 0 && bottom <= innerHeight
  }

  // scrollend, where the browser has it, else a beat longer than the scroll.
  // One wait at a time; this.pending cancels it.
  afterScroll(callback) {
    const pane = this.scroller()
    const settle = () => {
      this.cancelWait()
      callback()
    }
    const timer = setTimeout(settle, this.smooth ? 700 : 0)
    pane.addEventListener("scrollend", settle)
    this.pending = () => {
      clearTimeout(timer)
      pane.removeEventListener("scrollend", settle)
      this.pending = null
    }
  }

  cancelWait() {
    this.pending?.()
  }

  // driver builds a fresh popover for every step and focuses its first
  // control, the ×. The footer buttons get the daisyUI classes
  // (components/driver.css says why), and Next takes the focus, so Enter
  // continues rather than skips; the focus moves after driver's own, which
  // comes right after this hook.
  dress(popover) {
    popover.previousButton.classList.add("btn", "btn-sm", "btn-ghost")
    popover.nextButton.classList.add("btn", "btn-sm", "btn-primary")
    queueMicrotask(() => popover.nextButton.focus({ preventScroll: true }))
  }

  // The first visible match. daisyUI parks the phone drawer with visibility
  // and opacity, not display, so both have to count: checkVisibility with the
  // option names of Chrome 121+ and the earlier ones, where the browser has
  // it (Safari from 17.4), else offsetParent and the visibility property.
  visible(selector) {
    return [...document.querySelectorAll(selector)].find((el) => (el.checkVisibility
      ? el.checkVisibility({ visibilityProperty: true, opacityProperty: true, checkVisibilityCSS: true, checkOpacity: true })
      : el.offsetParent !== null && getComputedStyle(el).visibility !== "hidden"))
  }

  // reason is driver's: "done" from moveNext past the last step, else a
  // dismissal (or an Event, from the before-cache action). Done leaves the
  // page scrolled down to Links & Things, so it goes back to the top, and says
  // so with the toast the partial rendered (the layout's toast-container,
  // where every toast goes; the toast controller connects to it there).
  finish(reason) {
    if (!this.driver) return

    this.cancelWait()
    this.driver.destroy()
    this.driver = null
    if (reason === "done") {
      this.scroller().scrollTo({ top: 0, behavior: this.smooth ? "smooth" : "auto" })
      document.getElementById("toast-container")?.append(this.toastTarget.content.cloneNode(true))
    }
    // driver would hand focus back to a popover button that is gone.
    this.visible("#menu-open, #menu-open-phone")?.focus({ preventScroll: true })
    this.element.remove()
    if (this.urlValue) patch(this.urlValue)
  }

  // The nearest ancestor that scrolls. On /me that is the drawer's content
  // pane, not the window: the document there is viewport-high.
  scroller() {
    return scrollParent(this.element) || document.scrollingElement
  }
}
