import {Controller} from "@hotwired/stimulus"
import {post} from "@rails/request.js"

/*
  The owner's open thread on /me (ruling D6 of the messaging rework,
  .scratch/messaging-rework/PRD.md): a reply that lands live while the page is
  on screen has been seen, so it is marked read the way opening the thread marks
  it. Only a card the server rendered unread for the owner -- someone else's --
  counts, and only one added after the page loaded; a hidden tab leaves it New.

  The answer is turbo-streams: the navbar envelope, the Unread tab's count, the
  thread's row and the cards, as MessagesConcern#mark_read sends them. It posts
  what the list beside the pane shows now -- the folder and search fields the
  tab row keeps for the pane's toggles (common/messages/_folder_selector) -- so
  the row comes back as that list draws it, not as the list stood when the
  thread was opened.
 */
export default class extends Controller {
    static values = {url: String}

    connect() {
        this.observer = new MutationObserver((records) => {
            const unread = records.some((record) =>
                [...record.addedNodes].some((node) => node.matches?.("[data-unread]")))
            if (unread && document.visibilityState === "visible") {
                post(this.urlValue, {responseKind: "turbo-stream", body: this.listState()})
            }
        })
        this.observer.observe(this.element, {childList: true})
    }

    disconnect() {
        this.observer.disconnect()
    }

    listState() {
        const body = new FormData()
        document.querySelectorAll("input[form='messages-toggle-read']").forEach((field) => {
            body.append(field.name, field.value)
        })
        return body
    }
}
