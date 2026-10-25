import {Controller} from "@hotwired/stimulus"
import {Turbo} from "@hotwired/turbo-rails"

/*
  Turbo Streams does not handle updating the browser history and only doing a partial update using a navigation
   link.

  This controller allows navigation links to be used to update the main content (primarily) and to update the
  browser history without causing a full page reload to happen. This better simulates the SPA experience, and
  causes less HTML to flow through the wires.

  The history entry is handed to Turbo rather than pushed by hand, so back and
  forward restore it the way they restore every other page. A bare pushState
  leaves an entry Turbo can only guess at, and it guesses the wrong snapshot.
 */

const afterRenderEvent = new CustomEvent("turbo:after-stream-nav-render", {bubbles: true});
export default class extends Controller {
    async follow(event) {
        const link = event.currentTarget

        // Allow modified-clicks to behave normally
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || link.target === "_blank") return;

        event.preventDefault()
        const url = link.href

        try {
            await this.renderStream(url)

            const location = new URL(url)
            Turbo.session.history.push(location)
            Turbo.session.view.lastRenderedLocation = location
            document.dispatchEvent(afterRenderEvent);
        } catch (e) {
            console.error(e);
            // As a fallback, do a normal Turbo visit
            Turbo.visit(url);
        }
    }

    // Asks for the address as a turbo stream and nothing else: a page with no
    // stream to give answers 406, and a redirect is not followed here. Both
    // land in the catch above, and the visit deals with them.
    async renderStream(url) {
        const response = await fetch(url, {
            headers: {"Accept": "text/vnd.turbo-stream.html"},
            credentials: "same-origin",
            redirect: "manual"
        })
        const type = response.headers.get("Content-Type") || ""
        if (!response.ok || !type.startsWith("text/vnd.turbo-stream.html")) {
            throw new Error(`HTTP ${response.status}`)
        }
        Turbo.renderStreamMessage(await response.text())
    }
}
