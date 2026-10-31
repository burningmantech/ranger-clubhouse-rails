// Bringing an element into view where something other than the window scrolls
// it. Here that is most of the time: body is h-dvh and the page scrolls in
// div.drawer-content (layouts/application), and the mailbox's pane scrolls
// itself from lg up (components/review-pane.css). Shared by the controllers
// that scroll to something: scroll_to_element, search_matches, hq_shift and
// onboarding.

// The nearest ancestor that scrolls: overflow-y auto or scroll, with more in it
// than shows. Found by behaviour, not by selector: the layout nests a plain
// <main> inside the drawer's scroller, and a table's overflow-x wrapper
// computes overflow-y auto too, with nothing to scroll down.
export function scrollParent(element) {
    for (let node = element.parentElement; node; node = node.parentElement) {
        if (scrolls(node) && node.scrollHeight > node.clientHeight) {
            return node
        }
    }
    return null
}

// Whether +element+ is a scroller as its CSS stands now: the mailbox's pane is
// one from lg up only.
export function scrolls(element) {
    return ["auto", "scroll"].includes(getComputedStyle(element).overflowY)
}

// Scrolls +scroller+ until +target+'s top sits +offset+ of the scroller's own
// pixels inside its top edge.
export function scrollWithin(scroller, target, {offset = 0, behavior = "auto"} = {}) {
    scroller.scrollTo({top: scroller.scrollTop + below(scroller, target) - offset, behavior})
}

// How far +target+'s top sits inside +scroller+'s top edge, in the scroller's
// own pixels. getBoundingClientRect measures what is drawn, after any CSS zoom
// on the way up (the HQ shell's, components/hq-window.css), but scrollTop
// counts the scroller's own pixels.
function below(scroller, target) {
    const box = scroller.getBoundingClientRect()
    const zoom = scroller.offsetHeight ? box.height / scroller.offsetHeight : 1
    return (target.getBoundingClientRect().top - box.top) / zoom - scroller.clientTop
}

// Brings +target+ into view, unless it is in view already, where a scroll
// would only hide what sits above it: wholly on screen, and at least its
// scroll-margin-top inside the top of what scrolls it -- the room it keeps
// there for what is pinned over it, as a mailbox card keeps for the stepper
// (_message_card). A pixel short is the scroll's rounding.
//
// +container+ names, as a selector, an ancestor that scrolls itself in some
// layouts: the mailbox's pane. While it does, it moves first, at once, putting
// the target at its top less the target's scroll-margin-top; scrollIntoView
// would move every container around the target too -- the page under the
// pane, carrying the list beside it away from the row the reader chose -- and
// its option to stop at the nearest (container: "nearest") is Chrome's alone.
// If the target is still off screen, the page then brings the container on
// screen, as little as it can: stacked under the list in the HQ window, or
// starting too low for its foot to show. A container wholly on screen stays
// put, so a target taller than it, never wholly on screen, never drags the
// page. Elsewhere the page scrolls the target to its top.
//
// +behavior+ is how the page moves: smoothly, unless the reader asks for less
// motion. A step from one match to the next moves at once ("auto"): a second
// step taken while a smooth scroll still ran would find its target passing
// through the screen and stay put, leaving it wherever that scroll ended.
export function reveal(target, container, {behavior} = {}) {
    const margin = parseFloat(getComputedStyle(target).scrollMarginTop)
    const scroller = container && target.closest(container)
    const inside = Boolean(scroller && scrolls(scroller))
    const around = inside ? scroller : scrollParent(target)
    if (onScreen(target) && (!around || below(around, target) > margin - 1)) {
        return
    }

    behavior ??= window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
    if (inside) {
        scrollWithin(scroller, target, {offset: margin})
        if (!onScreen(target)) {
            scroller.scrollIntoView({behavior, block: "nearest"})
        }
    } else {
        target.scrollIntoView({behavior, block: "start"})
    }
}

// Wholly on screen: the middle of its top and of its bottom edge hit-test to
// it, so it is neither clipped by a scroller, past the window's edge, nor
// under something drawn over it.
export function onScreen(element) {
    const {left, right, top, bottom} = element.getBoundingClientRect()
    const x = (left + right) / 2
    return [top + 2, bottom - 2].every((y) => element.contains(document.elementFromPoint(x, y)))
}
