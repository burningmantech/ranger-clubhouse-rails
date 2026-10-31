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
// pixels inside its top edge. getBoundingClientRect measures what is drawn,
// after any CSS zoom on the way up (the HQ shell's, components/hq-window.css),
// but scrollTop counts the scroller's own pixels.
export function scrollWithin(scroller, target, {offset = 0, behavior = "auto"} = {}) {
    const box = scroller.getBoundingClientRect()
    const zoom = scroller.offsetHeight ? box.height / scroller.offsetHeight : 1
    const top = scroller.scrollTop + (target.getBoundingClientRect().top - box.top) / zoom - scroller.clientTop - offset
    scroller.scrollTo({top, behavior})
}

// Brings +target+ into view, unless it is wholly on screen already, where a
// scroll would only hide what sits above it.
//
// +container+ names, as a selector, an ancestor that scrolls itself in some
// layouts: the mailbox's pane. While it does, it moves first, at once, putting
// the target at its top less the target's scroll-margin-top; scrollIntoView
// would move every container around the target too -- the page under the
// pane, carrying the list beside it away from the row the reader chose -- and
// its option to stop at the nearest (container: "nearest") is Chrome's alone.
// The page then moves only if the target is still off screen, as little as it
// can: when the container itself is -- stacked under the list in the HQ
// window, or starting too low for its foot to show. Elsewhere the page
// scrolls the target to its top.
export function reveal(target, container) {
    if (onScreen(target)) {
        return
    }

    const behavior = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
    const scroller = container && target.closest(container)
    if (scroller && scrolls(scroller)) {
        scrollWithin(scroller, target, {offset: parseFloat(getComputedStyle(target).scrollMarginTop)})
        if (!onScreen(target)) {
            target.scrollIntoView({behavior, block: "nearest"})
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
