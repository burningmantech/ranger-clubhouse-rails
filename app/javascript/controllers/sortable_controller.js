// Drag a list into a new order and tell the server where the item landed.
//
// The package controller does the whole job already: it PATCHes the dragged
// item's data-sortable-update-url with position=<1-based place>, and with
// data-sortable-response-kind-value="turbo-stream" it hands the answer to
// Turbo. Re-exported rather than wrapped so it registers as `sortable`
// alongside the app's own controllers -- lazyLoadControllersFrom only looks in
// this directory, and the package lives in the import map.
//
// Values worth setting in markup:
//   data-sortable-handle-value        CSS selector for the grip. Without it the
//                                     whole item drags, which swallows the
//                                     clicks and taps inside it.
//   data-sortable-response-kind-value "turbo-stream" to render the response.
import Sortable from "@stimulus-components/sortable"

export default Sortable
