// app/javascript/controllers/photo_cropper_controller.js
// Stimulus controller for photo cropping using CropperJS 2.0 Web Components,
// with a headshot overlay guide.

import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { patch } from "@rails/request.js"
import "cropperjs"

export default class extends Controller {
  static targets = ["canvas", "image", "selection", "submit"]
  static values = {
    canvasWidth: Number,
    canvasHeight: Number,
    cropping: Object
  }

  // Constants for cropper configuration
  static ZOOM_FACTOR_IN = 1.1
  static ZOOM_FACTOR_OUT = 0.9
  static ROTATION_STEP = 45 // degrees
  static GAP_EPSILON = 2 // canvas px of tolerance for float noise in gap detection

  // Getter methods for canvas dimensions
  get canvasWidth() {
    return this.canvasWidthValue || 350
  }

  get canvasHeight() {
    return this.canvasHeightValue || 450
  }

  connect() {
    if (this.hasImageTarget) {
      // CropperJS calls back once the image has loaded -- which can be after
      // the reader has already left the page, so a detached element is let be.
      this.imageTarget.$ready(() => {
        if (this.element.isConnected) this.initializeCropper()
      })
    }
  }

  disconnect() {
    this._initialTransform = null
    if (this.hasImageTarget) this.imageTarget.removeEventListener("pointerdown", this.onPointerDown)
    document.removeEventListener("pointermove", this.onPointerMove)
    document.removeEventListener("pointerup", this.onPointerUp)
  }

  /**
   * Initialize CropperJS 2.0 with configuration
   * Selection is fixed/centered, only image is movable via manual dragging
   */
  initializeCropper() {
    this.setupManualDragging()

    // Defer a frame: at $ready the layout can still be empty (cached-image
    // loads), which makes CropperJS skip the centering translation. With real
    // geometry, re-running the cover fit is deterministic and idempotent.
    requestAnimationFrame(() => {
      this.imageTarget.$center("cover")

      // CropperJS's own auto-fit transform is the natural state the reset
      // button returns to -- not the identity matrix.
      this._initialTransform = this.imageTarget.$getTransform()

      if (this.hasCroppingValue && this.croppingValue && Object.keys(this.croppingValue).length > 0) {
        this.applyCroppingData(this.croppingValue)
      }
    })
  }

  /**
   * Apply saved cropping data to the image
   * The crop data is a 2D affine transformation matrix
   */
  applyCroppingData(cropData) {
    // Ignore legacy offset-format data (pre-matrix schema): without the
    // translate components the rebuilt matrix would fling the image off-canvas
    if (cropData.translate_x === undefined || cropData.translate_y === undefined) return

    const {
      scale_x = 1,
      skew_x = 0,
      skew_y = 0,
      scale_y = 1,
      translate_x = 0,
      translate_y = 0
    } = cropData

    const matrix = [scale_x, skew_x, skew_y, scale_y, translate_x, translate_y]

    try {
      this.imageTarget.$setTransform(...matrix)
    } catch (error) {
      console.error("applyCroppingData: $setTransform failed, trying $transform", error)
      try {
        this.imageTarget.$transform(...matrix)
      } catch (transformError) {
        console.error("applyCroppingData: Both methods failed", transformError)
      }
    }
  }

  /**
   * Manually implement image dragging using CropperJS $move API
   * This bypasses the cropper-handle element which has rendering issues
   */
  setupManualDragging() {
    if (!this.hasImageTarget) return

    this.imageTarget.addEventListener("pointerdown", this.onPointerDown)
    // Track pointer movement globally; both come off again in disconnect
    document.addEventListener("pointermove", this.onPointerMove)
    document.addEventListener("pointerup", this.onPointerUp)
  }

  onPointerDown = (event) => {
    this.dragging = true
    this.dragX = event.clientX
    this.dragY = event.clientY
    this.dragZoom = this.cssZoom
    event.preventDefault()
  }

  onPointerMove = (event) => {
    if (!this.dragging) return

    // Pointer deltas are visual px; $move expects canvas px
    this.imageTarget.$move((event.clientX - this.dragX) / this.dragZoom, (event.clientY - this.dragY) / this.dragZoom)
    this.dragX = event.clientX
    this.dragY = event.clientY
  }

  onPointerUp = () => {
    this.dragging = false
  }

  /**
   * Effective CSS zoom on the cropper container (mobile scales it below 1).
   * getBoundingClientRect returns post-zoom coordinates, so gBCR-derived math
   * must divide by this to get back to canvas space (350×450). Equals 1 when
   * unzoomed, so this is a no-op on desktop.
   */
  get cssZoom() {
    const width = this.canvasTarget.getBoundingClientRect().width
    return width > 0 ? width / this.canvasWidth : 1
  }

  /**
   * Check if there are gaps in the selection (image doesn't fully cover it)
   *
   * Maps the selection's canvas-space corners through the inverse of the image
   * transform and requires each to land inside the natural image bounds. The
   * transform origin is the center of the naturalWidth×naturalHeight host
   * (same math as CropperJS $toCanvas), so a canvas point q relates to a
   * natural-image point p via q = L·p + T, where L = [[a, c], [b, d]] and
   * T = center + (e, f) − L·center. Exact under rotation and immune to the
   * CSS zoom applied to the container on mobile.
   */
  hasGaps() {
    if (!this.hasImageTarget || !this.hasSelectionTarget) return true

    const { x, y, width, height } = this.selectionTarget
    const [a, b, c, d, e, f] = this.imageTarget.$getTransform()
    const det = a * d - b * c
    if (!det) return true

    // The browser's natural size is what CropperJS sizes its host to on load
    const { naturalWidth: w, naturalHeight: h } = this.imageTarget.$image
    const tx = w / 2 + e - (a * (w / 2) + c * (h / 2))
    const ty = h / 2 + f - (b * (w / 2) + d * (h / 2))
    // Tolerance is in canvas px; divide by the overall scale to get natural px
    const eps = this.constructor.GAP_EPSILON / Math.sqrt(Math.abs(det))

    const corners = [[x, y], [x + width, y], [x, y + height], [x + width, y + height]]
    return corners.some(([qx, qy]) => {
      const px = (d * (qx - tx) - c * (qy - ty)) / det
      const py = (a * (qy - ty) - b * (qx - tx)) / det
      return px < -eps || px > w + eps || py < -eps || py > h + eps
    })
  }

  /**
   * Reset image to its natural/default state, clearing every user transform
   */
  resetToNaturalState() {
    if (!this.hasImageTarget) return

    this.imageTarget.$setTransform(...(this._initialTransform || [1, 0, 0, 1, 0, 0]))
  }

  /**
   * Generic image transform handler
   */
  handleTransform(event, method, ...args) {
    event.preventDefault()
    this.imageTarget?.[method](...args)
  }

  /**
   * Zoom controls
   */
  zoomIn(event) {
    this.handleTransform(event, "$scale", this.constructor.ZOOM_FACTOR_IN)
  }

  zoomOut(event) {
    this.handleTransform(event, "$scale", this.constructor.ZOOM_FACTOR_OUT)
  }

  /**
   * Rotation controls
   */
  rotateLeft(event) {
    // Unitless values are treated as radians by CropperJS — always pass "deg"
    this.handleTransform(event, "$rotate", `-${this.constructor.ROTATION_STEP}deg`)
  }

  rotateRight(event) {
    this.handleTransform(event, "$rotate", `${this.constructor.ROTATION_STEP}deg`)
  }

  reset(event) {
    event.preventDefault()
    this.resetToNaturalState()
  }

  /**
   * Submit form with crop data
   * Validates that selection is fully covered by image (no gaps)
   */
  async beforeSubmit(event) {
    event.preventDefault()

    if (!this.hasSelectionTarget) {
      alert("Cropper not initialized")
      return
    }

    const { width = 0, height = 0 } = this.selectionTarget

    if (width === 0 || height === 0) {
      alert("Please select a crop area before saving")
      return
    }

    // Check for gaps before submitting
    if (this.hasGaps()) {
      alert("The image does not fully cover the selection area. Please adjust the image position, zoom, or selection to eliminate gaps before saving.")
      return
    }

    this.setSubmitState(true, "Saving…")

    try {
      // Send the full CropperJS transform matrix. Keys match applyCroppingData,
      // so the saved crop restores exactly on revisit. The backend renders the
      // same mapping (rotation included) to produce the profile image.
      const [scale_x, skew_x, skew_y, scale_y, translate_x, translate_y] = this.imageTarget.$getTransform()

      const response = await patch(event.target.action, {
        body: { cropping: { scale_x, skew_x, skew_y, scale_y, translate_x, translate_y } },
        responseKind: "json"
      })

      // A session that has run out answers with the sign-in page: go there.
      if (response.redirected) {
        Turbo.visit(response.response.url)
        return
      }
      if (!response.ok) {
        const result = await response.json.catch(() => ({}))
        throw new Error(result.error || "Failed to save")
      }

      const result = await response.json
      Turbo.visit(result.redirect_url)
    } catch (error) {
      alert(`Error: ${error.message}`)
      this.setSubmitState(false, "Save Crop Data")
    }
  }

  /**
   * Set submit button state
   */
  setSubmitState(disabled = false, text = "Save Crop Data") {
    if (!this.hasSubmitTarget) return

    Object.assign(this.submitTarget, { disabled, textContent: text })
  }
}
