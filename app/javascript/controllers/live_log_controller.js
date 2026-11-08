import {Controller} from "@hotwired/stimulus"

/*
  The Live mode of Admin › Request Log and Admin › Action Logs (their
  _live.html.erb, fed by a LiveLogChannel).

  The feed's <turbo-cable-stream-source> is made here from its template, and
  only while the tab is showing. A hidden tab removes it, which unsubscribes
  and stops the channel's timer; showing the tab again makes a fresh one that
  names where the page stands -- its newest row, and the ids missing among its
  newest rows -- so the first tick back sends only what arrived meanwhile, and
  the channel goes on looking for rows still being saved. A page opened in a
  background tab subscribes when it is first shown. The page is kept out of
  Turbo's cache, so Back never restores a copy of the element that would
  subscribe a second time.

  Those names are fixed into the subscription when the element is made, and
  Action Cable sends the same subscription again when a dropped socket
  reopens. So a stream that was confirmed and then lost its connection is made
  again as well, and the reopened socket names where the page stands now
  rather than where it stood when the tab was last shown.

  Rows stay newest first: one that committed after newer ones were sent
  arrives on top of them and moves down to its place. Rows past the cap drop
  off the bottom as new ones land on top, and the table gives way to the empty
  state while it holds none. A feed without a confirmed subscription for
  longer than a reconnect takes -- refused, or the connection lost -- says so
  rather than looking live.
 */

// Longer than Action Cable waits before it reconnects (six seconds), so a blip
// passes without a word.
const STALL_GRACE_MS = 10_000

// Each row's id ends in its record's id (the _live_rows partials).
const recordId = (row) => Number(row.id.split("-").pop())

export default class extends Controller {
    static targets = ["source", "rows", "table", "empty", "stalled"]
    static values = {cap: {type: Number, default: 200}, lookback: {type: Number, default: 100}}

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
        this.dropStream()
    }

    rowsChanged() {
        this.placeLateRows()
        const rows = this.rowsTarget.children
        while (rows.length > this.capValue) rows[rows.length - 1].remove()

        this.tableTarget.hidden = rows.length === 0
        this.emptyTarget.hidden = rows.length > 0
    }

    // From the bottom up, a row sitting above a newer one moves down past it
    // into the rows below, which are in order by then. Only rows that came late
    // move, so the ones being read stay where they are.
    placeLateRows() {
        for (const row of [...this.rowsTarget.children].reverse()) {
            let next = row.nextElementSibling
            if (!next || recordId(next) < recordId(row)) continue

            while (next && recordId(next) > recordId(row)) next = next.nextElementSibling
            this.rowsTarget.insertBefore(row, next)
        }
    }

    visibilityChanged() {
        if (document.hidden) {
            this.dropStream()
        } else if (!this.stream) {
            this.stream = document.importNode(this.sourceTarget.content.firstElementChild, true)
            this.nameWhereThePageStands(this.stream)
            this.element.append(this.stream)
        }
        this.watchConnection()
    }

    // The newest row the page holds (data-since), and the ids missing among
    // its newest rows (data-gaps): rows still being saved when the page got
    // them, which the channel goes on looking for. At most lookback of each.
    nameWhereThePageStands(stream) {
        const ids = [...this.rowsTarget.children].slice(0, this.lookbackValue).map(recordId)
        if (!ids.length) return

        stream.dataset.since = ids[0]
        const gaps = []
        for (let i = 1; i < ids.length && gaps.length < this.lookbackValue; i++) {
            for (let id = ids[i - 1] - 1; id > ids[i] && gaps.length < this.lookbackValue; id--) gaps.push(id)
        }
        if (gaps.length) stream.dataset.gaps = gaps.join(",")
    }

    watchConnection() {
        if (this.stream?.hasAttribute("connected")) {
            this.confirmed = true
        } else if (this.confirmed) {
            // Confirmed once and now lost: made again, naming where the page stands now.
            this.dropStream()
            this.visibilityChanged()
            return
        }

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

    dropStream() {
        this.stream?.remove()
        this.stream = null
        this.confirmed = false
    }
}
