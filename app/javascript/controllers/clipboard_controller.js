import { Controller } from "@hotwired/stimulus"

// Copies a value (e.g. an invite link) to the clipboard and briefly confirms
// on the clicked button. Falls back to execCommand for non-secure/older contexts.
export default class extends Controller {
  static values = { text: String, confirm: { type: String, default: "Copied!" } }

  async copy(event) {
    event.preventDefault()
    try {
      await navigator.clipboard.writeText(this.textValue)
    } catch {
      this.legacyCopy()
    }
    this.flash(event.currentTarget)
  }

  flash(btn) {
    if (!btn) return
    const original = btn.dataset.originalLabel || btn.textContent
    btn.dataset.originalLabel = original
    btn.textContent = this.confirmValue
    clearTimeout(this.timer)
    this.timer = setTimeout(() => { btn.textContent = original }, 1500)
  }

  legacyCopy() {
    const ta = document.createElement("textarea")
    ta.value = this.textValue
    ta.setAttribute("readonly", "")
    ta.style.position = "absolute"
    ta.style.left = "-9999px"
    document.body.appendChild(ta)
    ta.select()
    document.execCommand("copy")
    document.body.removeChild(ta)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
