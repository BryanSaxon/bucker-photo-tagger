import { Controller } from "@hotwired/stimulus"

// Handles the multi-photo upload form: drag-and-drop onto the dropzone, a live
// thumbnail preview of the chosen files, and a selected-count label.
export default class extends Controller {
  static targets = ["input", "dropzone", "preview", "count", "submit"]

  dragover(event) {
    event.preventDefault()
    this.dropzoneTarget.style.borderColor = "var(--gold)"
    this.dropzoneTarget.style.background = "rgba(245,166,35,.05)"
  }

  dragleave(event) {
    event.preventDefault()
    this.resetDropzone()
  }

  drop(event) {
    event.preventDefault()
    this.resetDropzone()
    this.inputTarget.files = event.dataTransfer.files
    this.preview()
  }

  preview() {
    const files = Array.from(this.inputTarget.files || [])
    this.previewTarget.innerHTML = ""

    files.forEach((file) => {
      if (!file.type.startsWith("image/")) return
      const card = document.createElement("div")
      card.className = "photo-card"
      const thumb = document.createElement("span")
      thumb.className = "photo-card__thumb"
      const img = document.createElement("img")
      img.src = URL.createObjectURL(file)
      img.onload = () => URL.revokeObjectURL(img.src)
      thumb.appendChild(img)
      const body = document.createElement("div")
      body.className = "photo-card__body"
      body.innerHTML = `<span class="photo-card__name">${file.name}</span>`
      card.appendChild(thumb)
      card.appendChild(body)
      this.previewTarget.appendChild(card)
    })

    if (this.hasCountTarget) {
      this.countTarget.textContent = files.length
        ? `${files.length} file${files.length === 1 ? "" : "s"} ready`
        : ""
    }
  }

  resetDropzone() {
    this.dropzoneTarget.style.borderColor = "var(--border)"
    this.dropzoneTarget.style.background = "var(--canvas)"
  }
}
