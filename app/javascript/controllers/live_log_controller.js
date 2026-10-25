import {Controller} from "@hotwired/stimulus"

/*
  The Live mode of Admin › Request Log (admin/request_logs/_live.html.erb).

  The feed's <turbo-cable-stream-source> is made here from its template, and
  only while the tab is showing. A hidden tab removes it, which unsubscribes
  and stops RequestLogLiveChannel's timer; showing the tab again makes a fresh
  one that names the rows the page already holds, so the first tick back sends
  only what arrived meanwhile. A page opened in a background tab subscribes
  when it is first shown. The page is kept out of Turbo's cache, so Back never
  restores a copy of the element that would subscribe a second time.

  Rows past the cap drop off the bottom as new ones land on top, and the table
  gives way to the empty state while it holds none. A feed without a confirmed
  subscription for longer than a reconnect takes -- refused, or the connection
  lost -- says so rather than looking live.
 */

// Longer than Action Cable waits before it reconnects (six seconds), so a blip
// passes without a word.
const STALL_GRACE_MS = 10_000

export default class extends Controller {
    static targets = ["source", "rows", "table", "empty", "stalled"]
    static values = {cap: {type: Number, default: 200}}

    connect() {
        this.rowsObserver = new MutationObserver(() => this.rowsChanged())
        this.rowsObserver.observe(this.rowsTarget, {childList: true})
        // The stream element marks itself connected once the channel confirms
        // the subscription, and drops the mark when the socket closes.
        this.connectionObserver = new MutationObserver(() => this.watchConnection())
        this.connectionObserver.observe(this.element, {subtree: true, attributeFilter: ["connected"]})
        this.visibilityChanged = this.visibilityChanged.bind(this)
        document.addEventListener("visibilitychange", this.visibilityChanged)

        this.rowsChanged()
        this.visibilityChanged()
    }

    disconnect() {
        document.removeEventListener("visibilitychange", this.visibilityChanged)
        this.rowsObserver.disconnect()
        this.connectionObserver.disconnect()
        clearTimeout(this.stallTimer)
        this.stream?.remove()
    }

    rowsChanged() {
        const rows = this.rowsTarget.children
        while (rows.length > this.capValue) rows[rows.length - 1].remove()

        this.tableTarget.hidden = rows.length === 0
        this.emptyTarget.hidden = rows.length > 0
    }

    visibilityChanged() {
        if (document.hidden) {
            this.stream?.remove()
            this.stream = null
        } else if (!this.stream) {
            this.stream = document.importNode(this.sourceTarget.content.firstElementChild, true)
            // Each row's id ends in its request's id (_live_rows.html.erb).
            const shown = [...this.rowsTarget.children].map((row) => Number(row.id.split("-").pop()))
            if (shown.length) {
                this.stream.dataset.since = Math.max(...shown)
                this.stream.dataset.shown = shown.join(",")
            }
            this.element.append(this.stream)
        }
        this.watchConnection()
    }

    watchConnection() {
        const waiting = this.stream && !this.stream.hasAttribute("connected")

        if (!waiting) {
            clearTimeout(this.stallTimer)
            this.stallTimer = null
            this.stalledTarget.hidden = true
        } else if (!this.stallTimer) {
            this.stallTimer = setTimeout(() => {
                this.stalledTarget.hidden = false
            }, STALL_GRACE_MS)
        }
    }
}
