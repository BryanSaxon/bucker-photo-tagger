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
      const isZip = file.type.includes("zip") || file.name.toLowerCase().endsWith(".zip")
      if (!file.type.startsWith("image/") && !isZip) return

      const card = document.createElement("div")
      card.className = "photo-card"
      const thumb = document.createElement("span")
      thumb.className = "photo-card__thumb"
      if (isZip) {
        thumb.style.display = "grid"
        thumb.style.placeItems = "center"
        thumb.style.fontSize = "30px"
        thumb.textContent = "🗜️"
      } else {
        const img = document.createElement("img")
        img.src = URL.createObjectURL(file)
        img.onload = () => URL.revokeObjectURL(img.src)
        thumb.appendChild(img)
      }
      const body = document.createElement("div")
      body.className = "photo-card__body"
      const label = isZip ? `${file.name} (archive)` : file.name
      body.innerHTML = `<span class="photo-card__name">${label}</span>`
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
