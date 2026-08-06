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

  // How many direct uploads run at once. A browser only opens ~6 connections
  // per host anyway, and firing one per file at real batch sizes (150+) times
  // them out against R2.
  static CONCURRENCY = 4

  // Intercept submit: upload the image files directly to storage, replace them
  // with their signed ids, and let the form submit (with any zips) afterwards.
  //
  // Each file succeeds or fails on its own. The previous version awaited a
  // single Promise.all over every file, so the first failure abandoned the rest
  // and fell back to pushing EVERY file's bytes through the web process.
  async submit(event) {
    const files = Array.from(this.inputTarget.files || [])
    // Carry each file's original position so its preview card can be updated.
    const images = files.map((file, index) => ({ file, index })).filter(({ file }) => this.isImage(file))
    if (images.length === 0) return // zips-only or nothing — normal submit

    event.preventDefault()
    const others = files.filter((f) => !this.isImage(f))
    const queue = [...images]
    const failed = []
    let done = 0
    this.setBusy(0, images.length)

    const worker = async () => {
      while (queue.length) {
        const { file, index } = queue.shift()
        try {
          this.addSignedId(await this.uploadFile(file))
          this.markCard(index, "done")
        } catch (e) {
          failed.push(file)
          this.markCard(index, "failed")
        }
        this.setBusy(++done, images.length)
      }
    }

    await Promise.all(
      Array.from({ length: Math.min(this.constructor.CONCURRENCY, queue.length) }, worker)
    )

    // Only the files that actually failed fall back to a multipart submit.
    const dt = new DataTransfer()
    others.forEach((f) => dt.items.add(f))
    failed.forEach((f) => dt.items.add(f))
    this.inputTarget.files = dt.files
    this.setBusy(null)
    this.element.requestSubmit()
  }

  // Some browsers report an empty MIME type for .heic, which would route the
  // file to the server as if it were a zip. Fall back to the extension.
  isImage(file) {
    return file.type.startsWith("image/") ||
      /\.(jpe?g|png|webp|gif|heic|heif)$/i.test(file.name)
  }

  markCard(index, state) {
    if (!this.hasPreviewTarget) return
    const card = this.previewTarget.querySelector(`[data-file-index="${index}"]`)
    if (!card) return
    card.dataset.uploadState = state
    const badge = card.querySelector("[data-role=upload-state]")
    if (badge) badge.textContent = state === "done" ? "✓ Uploaded" : "✕ Failed — will retry"
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

    files.forEach((file, index) => {
      const isZip = file.type.includes("zip") || file.name.toLowerCase().endsWith(".zip")
      if (!this.isImage(file) && !isZip) return

      const card = document.createElement("div")
      card.className = "photo-card"
      // Position in the input's file list, so per-file upload status can find
      // this card even though unsupported files are skipped here.
      card.dataset.fileIndex = index
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
      body.innerHTML =
        `<span class="photo-card__name"></span>` +
        `<span class="photo-card__meta" data-role="upload-state"></span>`
      body.querySelector(".photo-card__name").textContent = label
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
