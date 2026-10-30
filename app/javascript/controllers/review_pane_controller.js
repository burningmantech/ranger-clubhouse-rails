import {Controller} from "@hotwired/stimulus"

// Connects to data-controller="review-pane" on a review workspace
// (app/views/common/unified_flagging/_review_workspace.html.erb, and the
// mailbox's app/views/common/messages/_workspace.html.erb).
//
// The pane holds its own turbo frame that advances the URL, and each line is a
// link into it, so selecting a line swaps only the pane: the list, and the link
// the reader just activated (focus included), stay put. This controller keeps
// the list in step with what the pane shows -- the line whose data-review-id
// matches the pane's, marked aria-current, which the review-pane styles key on
// -- and below lg parks the pane under that line, keeping the line in view as
// the pane moves.
//
// park=false is for a workspace whose pane is hidden below lg (the mailbox:
// the index is the list alone, a thread its own page). The pane then stays
// where it is, and its frame -- rendered disabled -- is enabled from lg up
// only: Turbo hands a link to a frame only while the frame is enabled, so below
// lg, and before this controller loads, a line's link is an ordinary page
// visit. When the viewport crosses lg, the two columns are set to what a load
// of the current address would render (#fit).
//
// It re-syncs on connect, which a full load, a redirect back from a note form
// and a Back restore of a cached snapshot all give, and brings the line into
// view there: the layout scrolls an inner element whose position neither a
// page load nor a snapshot restore keeps.
export default class extends Controller {
    static targets = ["pane", "line", "list"]
    static values = {park: {type: Boolean, default: true}}

    connect() {
        if (!this.hasPaneTarget) {
            return
        }

        this.desktop = window.matchMedia("(width >= 64rem)")
        this.place = this.place.bind(this)
        this.beforeRender = this.beforeRender.bind(this)
        this.keepAttribute = this.keepAttribute.bind(this)
        this.keepBody = this.keepBody.bind(this)
        this.desktop.addEventListener("change", this.place)
        this.element.addEventListener("turbo:before-frame-render", this.beforeRender)
        this.element.addEventListener("turbo:before-morph-attribute", this.keepAttribute)
        this.element.addEventListener("turbo:before-morph-element", this.keepBody)
        document.addEventListener("turbo:load", this.place)

        this.select(this.shownId(this.frame))
        this.place()
        this.reveal()
    }

    disconnect() {
        this.desktop?.removeEventListener("change", this.place)
        this.element.removeEventListener("turbo:before-frame-render", this.beforeRender)
        this.element.removeEventListener("turbo:before-morph-attribute", this.keepAttribute)
        this.element.removeEventListener("turbo:before-morph-element", this.keepBody)
        document.removeEventListener("turbo:load", this.place)
    }

    // A line rendered after the pane -- the mailbox's folder switch streams its
    // list anew, and the thread page's list loads lazily -- takes the mark if it
    // is the one the pane shows. Stimulus announces the lines already in the
    // page before connect(), when nothing is selected yet; connect()'s select()
    // marks those. The shown id is kept rather than read from the pane each
    // time, which cost two whole-workspace queries per line.
    lineTargetConnected(line) {
        if (this.currentId === undefined) {
            return
        }

        this.mark(line, this.currentId)
        if (this.revealOnArrival && line.dataset.reviewId === this.currentId) {
            this.revealOnArrival = false
            line.closest("li").scrollIntoView({block: "nearest"})
        }
    }

    // The new record's line is marked as its content replaces the old one.
    // The pane follows it on turbo:load, the page visit Turbo makes of every
    // frame visit that advances the URL, and not before: moving the frame
    // disconnects it, which cancels its request -- before the render that
    // fetches the src again, after it the page visit loses the response (and
    // with it the snapshot a later Back restores).
    //
    // The pane keeps its scroll through the swap, which would open the new
    // record wherever the last was left -- a long way down after the mailbox
    // landed a search's match (scroll_to_element_controller). So it is put back
    // to the top as the content is swapped, before the new content's
    // controllers connect and a landing scrolls it again.
    beforeRender(event) {
        if (event.target === this.frame) {
            this.select(this.shownId(event.detail.newFrame))
            const render = event.detail.render
            event.detail.render = (currentElement, newElement) => {
                const rendered = render(currentElement, newElement)
                this.paneTarget.scrollTop = 0
                return rendered
            }
        }
    }

    // A line or a card morphed in place stays the same node, so
    // lineTargetConnected never sees it, and its new render knows less than
    // the page: the mailbox's row a live reply re-renders has no selection, no
    // folder and no search (common/messages/_list_reply), and a card's
    // read-state morph no search (MessagesConcern#card_streams). So the open
    // line keeps its mark, a line its address -- only a fresh render of the
    // list, never a morph, changes one -- and a card the ring of the search
    // the thread was opened with (data-landing, common/messages/_thread).
    keepAttribute(event) {
        const {attributeName, mutationType} = event.detail
        const line = this.lineTargets.includes(event.target)
        if ((line && attributeName === "aria-current" && mutationType === "remove" &&
                event.target.dataset.reviewId === this.currentId) ||
            (line && attributeName === "href") || attributeName === "data-landing") {
            event.preventDefault()
        }
    }

    // A message's body never changes once sent, so a morph of its card keeps
    // the one the page drew, with the search's marks _thread put in it, and
    // never adds marks to a card that landed live in the log region.
    keepBody(event) {
        if (event.target.matches?.("[data-message-body]")) {
            event.preventDefault()
        }
    }

    select(id) {
        this.currentId = id
        this.lineTargets.forEach((line) => this.mark(line, id))
    }

    mark(line, id) {
        if (line.dataset.reviewId === id) {
            line.setAttribute("aria-current", "true")
        } else {
            line.removeAttribute("aria-current")
        }
    }

    // A review list scrolls its line to the top, where a pane parked under it
    // below lg is on screen too. The mailbox only brings an out-of-view row into
    // view: its hero and folder tabs sit above the list, and a lazily loaded
    // list brings its row in as it arrives.
    reveal() {
        const line = this.selectedLine
        if (this.parkValue) {
            line?.closest("li").scrollIntoView({block: "start"})
        } else if (line) {
            line.closest("li").scrollIntoView({block: "nearest"})
        } else {
            this.revealOnArrival = this.currentId !== undefined
        }
    }

    place(event) {
        if (!this.parkValue) {
            this.frame.disabled = !this.desktop.matches
            if (event?.type === "change") {
                this.fit()
            }
            return
        }

        const line = this.desktop.matches ? null : this.selectedLine
        const home = line ? line.closest("li") : this.element
        if (this.paneTarget.parentElement === home) {
            return
        }

        home.append(this.paneTarget)
        // The pane may have left from above this line, lifting it out of view.
        line?.scrollIntoView({block: "nearest"})
    }

    // Below lg the page is one column: the open record's pane, or the list when
    // none is open. The server decides which as it renders, so a record opened
    // in the frame at lg would be hidden once the viewport narrows; this sets the
    // columns from what the pane shows, as a load of that address would. Only on
    // a crossing: run on every load, it would also rewrite a cached snapshot
    // restored under the list's address.
    fit() {
        const open = this.currentId !== undefined
        this.paneTarget.classList.toggle("hidden", !open)
        this.paneTarget.classList.toggle("lg:block", !open)
        this.listTarget.classList.toggle("hidden", open)
        this.listTarget.classList.toggle("lg:block", open)
    }

    get frame() {
        return this.paneTarget.querySelector("turbo-frame")
    }

    get selectedLine() {
        return this.lineTargets.find((line) => line.getAttribute("aria-current") === "true")
    }

    shownId(frame) {
        return frame?.querySelector("[data-review-id]")?.dataset.reviewId
    }
}
