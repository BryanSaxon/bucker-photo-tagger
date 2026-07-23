import { Controller } from "@hotwired/stimulus"

// While a SKU sync is running, poll by reloading the page so the status card
// updates to "Synced" (or "Failed") once the background job finishes.
export default class extends Controller {
  static values = { running: Boolean }

  connect() {
    if (this.runningValue) {
      this.timer = setTimeout(() => Turbo.visit(window.location.href, { action: "replace" }), 3000)
    }
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
