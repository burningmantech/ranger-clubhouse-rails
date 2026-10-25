import {Controller} from "@hotwired/stimulus"
import {post} from "@rails/request.js"

/*
  The owner's open thread on /me (ruling D6 of the messaging rework,
  .scratch/messaging-rework/PRD.md): a reply that lands live while the page is
  on screen has been seen, so it is marked read the way opening the thread marks
  it. Only a card the server rendered unread for the owner -- someone else's --
  counts, and only one added after the page loaded; a hidden tab leaves it New.

  The answer is turbo-streams: the navbar envelope, the Unread tab's count, the
  thread's row and the cards, as MessagesConcern#mark_read sends them.
 */
export default class extends Controller {
    static values = {url: String}

    connect() {
        this.observer = new MutationObserver((records) => {
            const unread = records.some((record) =>
                [...record.addedNodes].some((node) => node.matches?.("[data-unread]")))
            if (unread && document.visibilityState === "visible") {
                post(this.urlValue, {responseKind: "turbo-stream"})
            }
        })
        this.observer.observe(this.element, {childList: true})
    }

    disconnect() {
        this.observer.disconnect()
    }
}
