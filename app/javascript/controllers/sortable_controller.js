import { Controller } from "@hotwired/stimulus"

// Drag-to-reorder for a list of rows. Uses native HTML5 drag and drop rather
// than a library so nothing extra is pinned in importmap.
//
// The row order in the DOM is the source of truth while dragging; on drop the
// resulting id sequence is posted once and the server assigns the ordering.
export default class extends Controller {
  static targets = ["list"]
  static values = { url: String }

  connect() {
    this.dragging = null
  }

  start(event) {
    this.dragging = event.currentTarget.closest("[data-sortable-id]")
    if (!this.dragging) return
    this.dragging.classList.add("is-dragging")
    // Firefox won't start a drag without data on the transfer.
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragging.dataset.sortableId)
  }

  over(event) {
    if (!this.dragging) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"

    const target = event.target.closest("[data-sortable-id]")
    if (!target || target === this.dragging) return

    // Insert above or below depending on which half of the row we're over, so
    // the row lands where the pointer is rather than always before it.
    const box = target.getBoundingClientRect()
    const after = event.clientY > box.top + box.height / 2
    target.parentNode.insertBefore(this.dragging, after ? target.nextSibling : target)
  }

  end() {
    if (!this.dragging) return
    this.dragging.classList.remove("is-dragging")
    this.dragging = null
    this.persist()
  }

  drop(event) {
    event.preventDefault()
  }

  async persist() {
    const ids = Array.from(this.listTarget.querySelectorAll("[data-sortable-id]"))
      .map((row) => row.dataset.sortableId)

    const body = new FormData()
    ids.forEach((id) => body.append("ids[]", id))

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content,
          Accept: "text/vnd.turbo-stream.html, text/html"
        },
        body
      })
      if (!response.ok) throw new Error(response.status)
      this.flash("Order saved")
    } catch (e) {
      // Reload rather than leave the screen showing an order that wasn't saved.
      this.flash("Couldn’t save the new order — reloading", true)
      setTimeout(() => window.location.reload(), 1200)
    }
  }

  flash(message, isError = false) {
    const el = this.element.querySelector("[data-sortable-status]")
    if (!el) return

    el.textContent = message
    el.style.color = isError ? "var(--error)" : "var(--muted)"
    clearTimeout(this.flashTimer)
    this.flashTimer = setTimeout(() => { el.textContent = "" }, 2000)
  }
}
