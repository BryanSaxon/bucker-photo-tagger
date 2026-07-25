import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

// Multi-photo upload form: drag-and-drop, a thumbnail preview, and — on submit —
// direct-to-storage uploads for images (they never pass through the web server),
// while any .zip archives still submit normally for server-side extraction.
export default class extends Controller {
  static targets = ["input", "dropzone", "preview", "count", "submit"]
  static values = { directUploadUrl: String }

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

  // Intercept submit: upload the image files directly to storage, replace them
  // with their signed ids, and let the form submit (with any zips) afterwards.
  async submit(event) {
    const files = Array.from(this.inputTarget.files || [])
    const images = files.filter((f) => f.type.startsWith("image/"))
    if (images.length === 0) return // zips-only or nothing — normal submit

    event.preventDefault()
    const others = files.filter((f) => !f.type.startsWith("image/"))
    this.setBusy(0, images.length)

    try {
      let done = 0
      const signedIds = await Promise.all(
        images.map((file) =>
          this.uploadFile(file).then((id) => {
            this.setBusy(++done, images.length)
            return id
          })
        )
      )
      signedIds.forEach((id) => this.addSignedId(id))

      // Leave only the non-image files (zips) in the input, then submit for real.
      const dt = new DataTransfer()
      others.forEach((f) => dt.items.add(f))
      this.inputTarget.files = dt.files
      this.element.requestSubmit()
    } catch (e) {
      // Direct upload failed (e.g. storage CORS not yet configured). Fall back
      // to a normal multipart submit — slower, but uploads still work. The files
      // are still in the input and no signed_ids were added, so .submit() (which
      // doesn't re-fire this handler) sends the bytes through the server.
      this.setBusy(null)
      this.element.submit()
    }
  }

  uploadFile(file) {
    return new Promise((resolve, reject) => {
      new DirectUpload(file, this.directUploadUrlValue).create((error, blob) =>
        error ? reject(error) : resolve(blob.signed_id)
      )
    })
  }

  addSignedId(signedId) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = "photo[signed_ids][]"
    input.value = signedId
    this.element.appendChild(input)
  }

  setBusy(done, total) {
    if (this.hasSubmitTarget) this.submitTarget.disabled = done !== null && done < total
    if (!this.hasCountTarget) return
    this.countTarget.textContent = done === null ? "" : `Uploading ${done}/${total}…`
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
