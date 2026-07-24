import { Controller } from "@hotwired/stimulus"

// Dismissable flash message. Auto-dismisses after `dismissAfter` ms when > 0
// (notices), or stays until the user closes it (alerts).
export default class extends Controller {
  static values = { dismissAfter: { type: Number, default: 0 } }

  connect() {
    if (this.dismissAfterValue > 0) {
      this.timer = setTimeout(() => this.dismiss(), this.dismissAfterValue)
    }
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    this.element.style.transition = "opacity .2s ease"
    this.element.style.opacity = "0"
    setTimeout(() => this.element.remove(), 200)
  }
}
