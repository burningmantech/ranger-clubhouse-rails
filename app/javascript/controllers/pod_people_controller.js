// Drag a Ranger from one pod to another.
//
// The package controller only reports drags WITHIN one list: SortableJS fires
// onUpdate there, and onAdd on the receiving list when an item crosses between
// two. Cross-pod is the only move this page has, so onAdd is wired to the same
// handler and sorting inside a list is switched off -- a shift pod lists its
// members in callsign order, which is not the reader's to rearrange.
//
// The move is sent as the person's own update, the same request the edit
// dialog's relocate select sends: the receiving pod's id off the list it was
// dropped into, and the pod it left already named in the URL.
//
// Values worth setting in markup:
//   data-pod-people-handle-value  CSS selector for the grip. The callsign next
//                                 to it opens the edit dialog, so the two
//                                 gestures need separate targets.
// Wanted on the list element: data-pod-id.
// Wanted on each member: data-sortable-update-url.
import Sortable from "@stimulus-components/sortable"
import { patch } from "@rails/request.js"

export default class extends Sortable {
  // This list sits inside a card that is itself dragged. SortableJS moves the
  // card in the DOM as it passes its neighbours, and Stimulus reports a moved
  // element as a disconnect followed by a connect. The package's disconnect
  // destroys the Sortable, and SortableJS keeps the drag in flight in state
  // shared by every instance -- destroy() ends whatever drag that is, its own
  // or not. So the CARD's drag died at its first swap and the drop never
  // reached the server. A list that only moved is therefore left alone: not
  // torn down, and not given a second Sortable -- and a second set of
  // listeners -- on top of the one it kept.
  connect() {
    if (!this.sortable) super.connect()
  }

  disconnect() {
    if (!this.element.isConnected) super.disconnect()
  }

  get defaultOptions() {
    return {
      group: "cruise-direction-people",
      sort: false,
      onAdd: this.onUpdate
    }
  }

  async onUpdate({ item, to }) {
    const url = item.dataset.sortableUpdateUrl
    const podId = to.dataset.podId
    if (!url || !podId) return

    const body = new FormData()
    body.append("new_pod_id", podId)

    return await patch(url, { body, responseKind: "turbo-stream" })
  }
}
