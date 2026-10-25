import {Controller} from "@hotwired/stimulus"

// Scan through the <a> tags and update the active links. Used when new content is loaded via <turbo_frame> or
// similar.

export default class extends Controller {
    connect() {
        this.boundUpdate = this._update.bind(this);
        // Run when Turbo renders or loads a new page
        document.addEventListener("turbo:after-stream-nav-render", this.boundUpdate);

        // Initial highlight
        this._update();
    }

    disconnect() {
        document.removeEventListener("turbo:after-stream-nav-render", this.boundUpdate);
    }

    _update() {
        const currentPath = this._normalizePath(window.location.pathname)

        this.element
            .querySelectorAll('a[href]')
            .forEach(link => {
                const href = link.href;
                if (href.includes('#')) {
                    return;
                }
                if (link.classList.contains('tab')) {
                    return;
                }
                // A link into a turbo frame on this page is not a menu link, and
                // the page that renders it owns its aria-current (the review
                // list's selected line). Restamping it here from an exact
                // query-string match would contradict the page.
                const frameTarget = link.dataset.turboFrame;
                if (frameTarget && frameTarget !== '_top') {
                    return;
                }
                // One view of the page it is on (Request Log's Search and Live
                // buttons): the page says which view is showing, in the link's
                // name. A link with no query matches every view of its path, so
                // stamping it here would call both views current.
                if (link.hasAttribute('data-active-ignore')) {
                    return;
                }
                const url = new URL(href, window.location.origin)
                const linkPath = this._normalizePath(url.pathname)
                // Links with a query string (e.g. pagination ?page=N) are only active when
                // the query matches too; plain menu links keep matching on pathname alone.
                // data-active-prefix (set by sidebar_item) also lights a link on the paths
                // under its prefix, mirroring menu_item_active? server-side, which asks
                // for the exact page first: a prefix narrower than the link's own path
                // (a training's Sessions, prefix session/) must not unlight its own page.
                const prefix = link.dataset.activePrefix
                const exact = linkPath === currentPath && (url.search === "" || url.search === window.location.search)
                const isActive = exact || (!!prefix && this._matchesPrefix(currentPath, this._normalizePath(prefix)))
                if (isActive) {
                    if (!link.classList.contains('active')) {
                        link.classList.add('active');
                        link.setAttribute("aria-current", "true");
                    }
                } else {
                    link.classList.remove('active');
                    link.setAttribute("aria-current", "false");
                }
            })
    }

    _matchesPrefix(currentPath, prefix) {
        if (prefix === "/") {
            return currentPath === prefix
        }
        return currentPath === prefix || currentPath.startsWith(`${prefix}/`)
    }

    _normalizePath(path) {
        // Remove trailing slash unless root "/"
        if (path.length > 1 && path.endsWith("/")) {
            return path.slice(0, -1)
        }
        return path
    }
}
