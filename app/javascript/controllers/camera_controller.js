// app/javascript/controllers/camera_controller.js
// Camera selfie capture for the photo upload page: camera access, preview,
// switching between cameras, and taking the photo.
//
// The photo itself is not uploaded from here. It is handed to the photo-upload
// controller on the same element as a camera:captured event, and from there it
// is the chosen file: the same preview, the same size check, the same upload
// and the same error box a picked file gets. A capture that fails goes the
// same way, as a camera:failed event carrying the message for that box.

import { Controller } from "@hotwired/stimulus"

// getUserMedia failures, by the error box that explains each.
const CAMERA_ERRORS = {
  NotAllowedError: "permission",
  PermissionDeniedError: "permission",
  NotFoundError: "no-camera",
  DevicesNotFoundError: "no-camera",
  NotReadableError: "in-use",
  TrackStartError: "in-use"
}

export default class extends Controller {
  static targets = [
    "uploadPanel", "cameraPanel",
    "tabUpload", "tabCamera",
    "video", "canvas",
    "cameraSelect", "cameraSelectWrapper",
    "previewArea", "loading",
    "unsupportedError", "permissionError", "noCameraError", "cameraInUseError"
  ]

  disconnect() {
    this.stopCamera()
  }

  showUpload(event) {
    event.preventDefault()
    this.stopCamera()
    this.selectTab("upload")
  }

  showCamera(event) {
    event.preventDefault()
    this.selectTab("camera")

    // A second tap while the camera is up, or still coming up, changes nothing.
    if (this.stream || this.starting) return

    this.showError(null)
    this.initCamera()
  }

  // One tab at a time: the tab buttons and their panels move together.
  selectTab(name) {
    const pairs = [
      [this.tabUploadTarget, this.uploadPanelTarget, name === "upload"],
      [this.tabCameraTarget, this.cameraPanelTarget, name === "camera"]
    ]
    for (const [tab, panel, active] of pairs) {
      tab.classList.toggle("tab-active", active)
      tab.setAttribute("aria-selected", String(active))
      tab.tabIndex = active ? 0 : -1
      panel.hidden = !active
    }
  }

  // Asks for the front camera, then lists the others once permission is in.
  async initCamera() {
    if (!navigator.mediaDevices?.getUserMedia) {
      this.showError("unsupported")
      return
    }

    if (await this.startStream({ facingMode: "user" })) await this.enumerateCameras()
  }

  async switchCamera(event) {
    const deviceId = event.target.value
    if (!deviceId || deviceId === this.currentDeviceId) return

    if (await this.startStream({ deviceId: { exact: deviceId } })) this.currentDeviceId = deviceId
  }

  // Opens the camera, or shows the error box that fits; true when it opened.
  // Any camera already running is stopped first, so a stream is never left
  // behind with its light on.
  async startStream(video) {
    this.stopCamera()
    this.starting = true
    this.setBusy(true)

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { ...video, width: { ideal: 1280 }, height: { ideal: 720 } },
        audio: false
      })
      // The preview, and the button in it, wait for the first frame: before
      // that the video is 0×0, and a capture would come out empty.
      this.videoTarget.addEventListener("loadeddata", () => {
        this.setBusy(false)
        this.previewAreaTarget.hidden = false
      }, { once: true })
      this.videoTarget.srcObject = this.stream
      return true
    } catch (error) {
      console.error("Camera error:", error.name, error.message)
      this.setBusy(false)
      this.showError(CAMERA_ERRORS[error.name] || "permission")
      return false
    } finally {
      this.starting = false
    }
  }

  // Lists the cameras in the selector, which only shows when there is a choice.
  async enumerateCameras() {
    try {
      const devices = (await navigator.mediaDevices.enumerateDevices())
        .filter((device) => device.kind === "videoinput")

      const settings = this.stream?.getVideoTracks()[0]?.getSettings()
      this.currentDeviceId = settings?.deviceId || null

      if (devices.length === 0) {
        this.stopCamera()
        this.showError("no-camera")
        return
      }

      this.cameraSelectWrapperTarget.hidden = devices.length < 2
      if (devices.length < 2) return

      this.cameraSelectTarget.innerHTML = ""
      devices.forEach((device, index) => {
        const option = document.createElement("option")
        option.value = device.deviceId
        option.textContent = device.label || `Camera ${index + 1}`
        option.selected = device.deviceId === this.currentDeviceId
        this.cameraSelectTarget.appendChild(option)
      })
    } catch (error) {
      console.error("Failed to enumerate cameras:", error)
    }
  }

  // Draws the current frame to the canvas, mirrored to match the preview, and
  // hands the JPEG to the upload form on the other tab -- where the spinner,
  // and any error, will be seen.
  capturePhoto(event) {
    event.preventDefault()
    if (!this.stream) return

    const video = this.videoTarget
    if (video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) {
      this.failed("The camera is still starting. Please try again in a moment.")
      return
    }

    const canvas = this.canvasTarget
    const context = canvas.getContext("2d")

    canvas.width = video.videoWidth
    canvas.height = video.videoHeight
    context.translate(canvas.width, 0)
    context.scale(-1, 1)
    context.drawImage(video, 0, 0, canvas.width, canvas.height)
    context.setTransform(1, 0, 0, 1, 0, 0)

    canvas.toBlob((blob) => {
      // Nothing came off the canvas: say so, and leave the camera running for
      // another try.
      if (!blob) {
        this.failed("Failed to capture photo. Please try again.")
        return
      }

      this.stopCamera()
      this.selectTab("upload")
      const file = new File([blob], `selfie-${Date.now()}.jpg`, { type: "image/jpeg" })
      this.dispatch("captured", { detail: { file } })
    }, "image/jpeg", 0.92)
  }

  failed(message) {
    this.dispatch("failed", { detail: { message } })
  }

  stopCamera() {
    if (this.stream) {
      this.stream.getTracks().forEach((track) => track.stop())
      this.stream = null
    }
    this.videoTarget.srcObject = null
  }

  setBusy(busy) {
    this.loadingTarget.hidden = !busy
    if (busy) this.previewAreaTarget.hidden = true
  }

  // Shows the one error box for the failure, or none.
  showError(kind) {
    this.unsupportedErrorTarget.hidden = kind !== "unsupported"
    this.permissionErrorTarget.hidden = kind !== "permission"
    this.noCameraErrorTarget.hidden = kind !== "no-camera"
    this.cameraInUseErrorTarget.hidden = kind !== "in-use"
  }
}
