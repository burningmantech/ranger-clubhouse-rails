import {Controller} from "@hotwired/stimulus"
import {Turbo, cable} from "@hotwired/turbo-rails"

/*
  The edge of a sign-in, on every page (layouts/application).

  A signed-in page names the sign-in it was drawn under, and goes to the sign-in
  page once that sign-in has ended somewhere else: a sign-out in another window,
  a revoke at Person › Login Sessions, or a locked account's next request. The
  server closes that sign-in's sockets for good (Session#close_cable_connections)
  and refuses one that reopens under it, so the subscription hears
  willAttemptReconnect: false; a socket that reopens under a newer sign-in of
  this browser rejects the subscription instead (SessionChannel). A socket that
  merely dropped hears true and reconnects by itself.

  A signed-out page clears what an ended sign-in left in this window: Turbo's
  cached pages, which Back shows without asking the server, and the socket,
  which would carry the next sign-in's pages under the old one's name.
 */

// Whether a socket of this window has been accepted. One closed for good before
// that (refused from the start, or a proxy that drops the subprotocol) says
// nothing about the sign-in, and leaving on it would bounce between / and /me.
let accepted = false

export default class extends Controller {
    static values = {session: Number}

    connect() {
        if (this.hasSessionValue) {
            this.watch()
        } else {
            this.clear()
        }
    }

    // subscribeTo resolves after an await, so a page left at once still lets
    // go of the subscription it made.
    async disconnect() {
        (await this.subscribing)?.unsubscribe()
    }

    watch() {
        const page = this.element
        this.subscribing = cable.subscribeTo({channel: "SessionChannel", session: this.sessionValue}, {
            connected() {
                accepted = true
            },
            rejected() {
                leave(page)
            },
            disconnected({willAttemptReconnect}) {
                if (!willAttemptReconnect && accepted) leave(page)
            }
        })
    }

    clear() {
        accepted = false
        // A tick on: Turbo stores the page it left a tick into rendering this one.
        setTimeout(() => Turbo.cache.clear())
        cable.getConsumer().then((consumer) => consumer.disconnect())
    }
}

function leave(page) {
    if (!page.isConnected) return
    // Turbo is on its way somewhere in this window (its own sign-out, a locked
    // account's redirect): let that land, flash and all, and look again after.
    if (document.querySelector("html[aria-busy], form[aria-busy]:not(turbo-frame form)")) {
        setTimeout(() => leave(page), 100)
        return
    }

    accepted = false
    // To the sign-in page rather than this page again: this address may answer
    // only a form post, and remembering it would send the next person to sign in
    // on this browser to where the last one was. Turbo's cache goes first, this
    // page included, so Back brings none of it up.
    Turbo.cache.clear()
    Turbo.cache.exemptPageFromCache()
    // Nothing on the page can be saved once its sign-in has ended, so the leave
    // guards (unsaved_changes_controller.js) let it go without asking.
    const root = document.documentElement
    root.toggleAttribute("data-signed-out", true)
    try {
        Turbo.visit("/", {action: "replace"})
    } finally {
        root.removeAttribute("data-signed-out")
    }
}
