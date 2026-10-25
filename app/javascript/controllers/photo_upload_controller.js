// app/javascript/controllers/photo_upload_controller.js
// Handles photo upload with client-side validation and error handling,
// drag-and-drop, and the selfie the camera controller hands over.
// Redirects to the crop page after a successful upload.

import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { post } from "@rails/request.js"

export default class extends Controller {
  static targets = ["submitForm", "fileInput", "submitButton", "errorMessage", "error", "loading", "uploadForm", "dropzone", "fileInfo", "fileName", "fileSize", "preview", "previewFallback", "previewNote"]
  static values = {
    createUrl: String,
    maxFileSize: Number,
    typeError: String,
  }

  connect() {
    this.handleUpload = this.handleUpload.bind(this)
    this.submitFormTarget.addEventListener("submit", this.handleUpload)
  }

  disconnect() {
    this.submitFormTarget.removeEventListener("submit", this.handleUpload)
    this.revokePreview()
  }

  // A selfie from the camera tab, delivered on the camera:captured event. It
  // becomes the chosen file, so the preview, the checks and the upload are the
  // ones a picked file gets.
  capture({ detail: { file } }) {
    const transfer = new DataTransfer()
    transfer.items.add(file)
    this.fileInputTarget.files = transfer.files
    this.fileSelected()
    this.submitFormTarget.requestSubmit()
  }

  // A capture that failed on the camera tab, delivered on the camera:failed
  // event with the message for the error box.
  failed({ detail: { message } }) {
    this.showError(message)
  }

  /**
   * Handle form submission: check the file's type and size, show the loading
   * state, upload, then go to the crop page.
   */
  async handleUpload(event) {
    event.preventDefault()

    const file = this.fileInputTarget.files[0]

    if (!file) {
      this.showError("Please select an image")
      return
    }

    if (!this.acceptedType(file)) {
      this.showError(this.typeErrorValue)
      return
    }

    if (file.size > this.maxFileSizeValue) {
      const maxSizeMB = Math.floor(this.maxFileSizeValue / (1024 * 1024))
      this.showError(`File must be less than ${maxSizeMB} MB`)
      return
    }

    this.hideError()
    this.setBusy(true)

    try {
      const body = new FormData()
      body.append("photo", file)

      // The server converts to JPEG and stores it; the answer names the crop page.
      const response = await post(this.createUrlValue, { body, responseKind: "json" })

      // A session that has run out answers with the sign-in page: go there.
      if (response.redirected) {
        Turbo.visit(response.response.url)
        return
      }
      if (!response.ok) {
        const data = await response.json.catch(() => ({}))
        throw new Error(data.error || "Upload failed")
      }

      const data = await response.json
      Turbo.visit(data.crop_url)
    } catch (error) {
      this.setBusy(false)
      this.showError(error.message)
    }
  }

  // A dropped file skips the picker's accept filter, and a browser that can't decode
  // HEIC reports an empty type, so the extension counts too. The server checks again.
  acceptedType(file) {
    const accepted = this.fileInputTarget.accept.split(",")
    const extension = `.${file.name.split(".").pop().toLowerCase()}`
    return accepted.includes(file.type) || accepted.includes(extension)
  }

  showError(message) {
    this.errorMessageTarget.textContent = message
    this.errorTarget.hidden = false
  }

  hideError() {
    this.errorTarget.hidden = true
  }

  // Uploading: the spinner replaces the form, and the submit is locked.
  setBusy(busy) {
    this.loadingTarget.hidden = !busy
    this.uploadFormTarget.hidden = busy
    this.submitButtonTarget.disabled = busy
  }

  /**
   * Handle dragover event - highlight dropzone
   */
  dragover(event) {
    event.preventDefault()
    event.stopPropagation()
    this.highlightDropzone(true)
  }

  /**
   * Handle dragleave event - remove highlight
   */
  dragleave(event) {
    event.preventDefault()
    event.stopPropagation()
    this.highlightDropzone(false)
  }

  /**
   * Handle drop event - process dropped file
   */
  drop(event) {
    event.preventDefault()
    event.stopPropagation()
    this.highlightDropzone(false)

    const files = event.dataTransfer.files
    if (files.length > 0) {
      this.fileInputTarget.files = files
      this.fileSelected()
    }
  }

  // The dropzone lights up while a file is held over it.
  highlightDropzone(on) {
    this.dropzoneTarget.classList.toggle("border-primary", on)
    this.dropzoneTarget.classList.toggle("bg-primary/5", on)
    this.dropzoneTarget.classList.toggle("border-base-300", !on)
  }

  /**
   * Handle file selection - show preview and file info
   */
  fileSelected() {
    const file = this.fileInputTarget.files[0]

    if (!file) {
      this.hideFileInfo()
      return
    }

    this.fileNameTarget.textContent = file.name
    this.fileSizeTarget.textContent = this.formatFileSize(file.size)
    this.fileInfoTarget.hidden = false
    this.generateThumbnail(file)
  }

  hideFileInfo() {
    this.fileInfoTarget.hidden = true
    this.previewTarget.innerHTML = ""
    this.revokePreview()
  }

  // An object URL, not a data: URL -- no FileReader pass and no base64 copy of
  // a file that may be 20 MB. Revoked when replaced, cleared, or on disconnect;
  // Turbo keeps the document alive across visits.
  generateThumbnail(file) {
    this.revokePreview()
    this.previewUrl = URL.createObjectURL(file)
    this.previewTarget.innerHTML = `
      <img src="${this.previewUrl}"
           alt="Preview"
           class="w-16 h-16 object-cover rounded-lg border border-line shadow-xs" />
    `
    this.showPreviewFallback(false)
    // A format the browser can't decode (HEIC outside Safari) fires error
    // instead of load: the placeholder takes the broken image's place.
    this.previewTarget.querySelector("img").onerror = () => this.showPreviewFallback(true)
  }

  // The thumbnail slot, or the placeholder icon with its explanation.
  showPreviewFallback(on) {
    this.previewTarget.hidden = on
    this.previewFallbackTarget.hidden = !on
    this.previewNoteTarget.hidden = !on
  }

  revokePreview() {
    if (!this.previewUrl) return
    URL.revokeObjectURL(this.previewUrl)
    this.previewUrl = null
  }

  /**
   * Format file size in human-readable format
   */
  formatFileSize(bytes) {
    if (bytes === 0) return "0 Bytes"

    const k = 1024
    const sizes = ["Bytes", "KB", "MB", "GB"]
    const i = Math.floor(Math.log(bytes) / Math.log(k))

    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + " " + sizes[i]
  }
}
