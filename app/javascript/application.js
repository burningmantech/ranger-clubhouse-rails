// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers";

// Some controls build themselves in the page rather than arriving with the HTML
// the server sent: the rich text editor writes its own toolbar and holds the
// text being edited, and the state list is filled in to match the country
// picked. Pages here are updated by morphing, which compares the page against
// that server HTML, so it would throw all of that away — emptying the editor and
// the state list along with whatever had been chosen or typed. Anything marked
// data-morph-skip is left out of the comparison and kept as it stands; the rest
// of the page still morphs normally.
//
// One thing a skipped control still takes from the server is its classes. A
// field that comes back from a rejected form has to show that it is in error,
// and that is a class on the field. The classes the server gave it last time are
// remembered, so that those are what is taken off again; the ones the control
// put on itself are never touched. They are remembered on the element, because
// the page the Back button returns to is a copy, and a copy keeps its
// attributes and nothing else.
document.addEventListener("turbo:before-morph-element", (event) => {
    const element = event.target;
    if (!element.matches?.("[data-morph-skip]")) return;

    event.preventDefault();

    // No new element when the page is taking this one out; it stays as it is.
    const incoming = event.detail.newElement;
    if (!incoming) return;

    const remembered = element.dataset.serverClass;
    if (remembered) element.classList.remove(...remembered.split(" "));
    element.classList.add(...incoming.classList);
    element.dataset.serverClass = [...incoming.classList].join(" ");
});


history.scrollRestoration = "manual"; // Disable Chrome maintaining scroll position on page refresh

Turbo.StreamActions.page_redirect = function () {
    Turbo.visit(this.getAttribute("url"), {frame: "_top", action: "advance"});
};

// Preserve messages list scroll position when opening and returning from a conversation
const MESSAGES_SCROLL_KEY = "messages-list-scroll";
document.addEventListener("turbo:before-visit", (event) => {
    if (/\/me\/messages\/\d+/.test(event.detail.url)) {
        const container = document.querySelector(".drawer-content");
        if (container) sessionStorage.setItem(MESSAGES_SCROLL_KEY, container.scrollTop);
    }
});

document.addEventListener("turbo:load", () => {
    if (window.location.pathname === "/me/messages") {
        const saved = sessionStorage.getItem(MESSAGES_SCROLL_KEY);
        if (saved !== null) {
            sessionStorage.removeItem(MESSAGES_SCROLL_KEY);
            requestAnimationFrame(() => {
                const container = document.querySelector(".drawer-content");
                if (container) container.scrollTop = parseInt(saved, 10);
            });
        }
    }

    if (typeof gtag === 'function') {
        gtag('event', 'page_view', {
            page_location: window.location.href,
            page_path: window.location.pathname,
            page_title: document.title
        });
    }
});

// An answer without the frame is a whole page the server sent instead: the
// sign-in page once a session has ended, the dashboard saying this page is not
// allowed, or an error page. Show that page, the way a link that fails shows it.
document.addEventListener("turbo:frame-missing", (event) => {
    // A frame that handles its own missing answer has already said so.
    if (event.defaultPrevented) return;

    event.preventDefault();
    event.detail.visit(event.detail.response);
});

// The message is the dialog itself (ModalHelper#confirm_modal_dialog). It is
// wired and shown in one turn, so a press can never land on a dialog that is not
// listening yet. None of this waits on the modal controller: that is
// lazy-loaded, and on a slow connection it can arrive after the answer.
Turbo.config.forms.confirm = (message, element, submitter) => {
    const template = document.createElement("template");
    template.innerHTML = message;
    const dialog = template.content.querySelector("dialog");

    // A plain-string message carries no dialog: ask with the browser's own.
    if (!dialog) {
        return Promise.resolve(window.confirm(message));
    }

    document.getElementById("turbo-confirm-modal").replaceChildren(dialog);

    return new Promise((resolve) => {
        // Every button in the dialog closes it, and only Confirm closes it as a
        // yes. The answer is read when it closes, so Escape counts as a no too
        // instead of leaving the submission hanging.
        dialog.addEventListener("click", (event) => {
            const button = event.target.closest("button");
            if (button) dialog.close(button.id === "turbo-confirm-button" ? "confirm" : "");
        });
        dialog.addEventListener("close", () => resolve(dialog.returnValue === "confirm"), {once: true});
        dialog.showModal();
    });
};
