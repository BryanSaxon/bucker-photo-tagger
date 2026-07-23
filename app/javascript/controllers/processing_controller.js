import { Controller } from "@hotwired/stimulus"

// Drives the photo processing screen: live SKU search, the selected-SKU list
// (with hidden form inputs Rails parses into photo[skus][]), community→floorplan
// filtering, and click-to-pin location tagging on the photo.
export default class extends Controller {
  static targets = [
    "stage", "image", "markers", "community", "floorplan",
    "search", "results", "selected", "selectedItem", "selectedCount", "emptyHint"
  ]
  static values = { skuSearchUrl: String }

  connect() {
    this.pinningId = null
    this.searchTimer = null
    this.filterFloorplans()
    this.renderMarkers()
    this.updateMeta()
  }

  // ---- SKU search (debounced fetch into the results container) ----
  search() {
    clearTimeout(this.searchTimer)
    this.searchTimer = setTimeout(() => this.runSearch(), 200)
  }

  async runSearch() {
    const q = this.searchTarget.value.trim()
    const url = new URL(this.skuSearchUrlValue, window.location.origin)
    url.searchParams.set("q", q)
    try {
      const res = await fetch(url, { headers: { "Accept": "text/html" } })
      this.resultsTarget.innerHTML = await res.text()
      this.syncResultDisabledState()
    } catch (e) {
      this.resultsTarget.innerHTML = `<p class="text-mono-sm" style="padding:8px 2px;">Search failed.</p>`
    }
  }

  // Disable results already in the current (client-side) selection.
  syncResultDisabledState() {
    this.resultsTarget.querySelectorAll(".sku-result").forEach((el) => {
      el.disabled = this.isSelected(el.dataset.skuId)
    })
  }

  // ---- Selection ----
  addSku(event) {
    const el = event.currentTarget
    const id = el.dataset.skuId
    if (this.isSelected(id)) return

    this.selectedTarget.insertAdjacentHTML("beforeend",
      this.rowHtml(id, el.dataset.code, el.dataset.desc))
    el.disabled = true
    this.updateMeta()
  }

  removeSku(event) {
    const row = event.currentTarget.closest(".selected-sku")
    const id = row.dataset.skuId
    row.remove()
    this.removeMarker(id)
    // Re-enable the matching search result if it's still shown.
    const result = this.resultsTarget.querySelector(`.sku-result[data-sku-id="${id}"]`)
    if (result) result.disabled = false
    if (this.pinningId === id) this.stopPinning()
    this.updateMeta()
  }

  // ---- Pin placement ----
  startPin(event) {
    const row = event.currentTarget.closest(".selected-sku")
    const id = row.dataset.skuId
    if (this.pinningId === id) { this.stopPinning(); return }
    this.pinningId = id
    this.stageTarget.classList.add("is-pinning")
  }

  stopPinning() {
    this.pinningId = null
    this.stageTarget.classList.remove("is-pinning")
  }

  placePin(event) {
    if (!this.pinningId) return
    const rect = this.imageTarget.getBoundingClientRect()
    const x = (event.clientX - rect.left) / rect.width
    const y = (event.clientY - rect.top) / rect.height
    if (x < 0 || x > 1 || y < 0 || y > 1) return

    const row = this.rowFor(this.pinningId)
    if (!row) return
    row.querySelector('[data-role="pos_x"]').value = x.toFixed(4)
    row.querySelector('[data-role="pos_y"]').value = y.toFixed(4)
    row.classList.add("is-pinned")
    const label = row.querySelector('[data-role="pin-label"]')
    if (label) label.textContent = "Pinned"

    this.stopPinning()
    this.renderMarkers()
  }

  // ---- Community → Floorplan filtering ----
  filterFloorplans() {
    if (!this.hasCommunityTarget || !this.hasFloorplanTarget) return
    const communityId = this.communityTarget.value
    let selectionCleared = false

    Array.from(this.floorplanTarget.options).forEach((opt) => {
      if (!opt.value) return // keep the blank prompt
      const matches = !communityId || opt.dataset.communityId === communityId
      opt.hidden = !matches
      if (!matches && opt.selected) { opt.selected = false; selectionCleared = true }
    })
    if (selectionCleared) this.floorplanTarget.value = ""
  }

  // ---- Markers ----
  renderMarkers() {
    this.markersTarget.innerHTML = ""
    let n = 0
    this.selectedItemTargets.forEach((row) => {
      const x = row.querySelector('[data-role="pos_x"]').value
      const y = row.querySelector('[data-role="pos_y"]').value
      if (x === "" || y === "") return
      n += 1
      const marker = document.createElement("div")
      marker.className = "pin-marker"
      marker.dataset.skuId = row.dataset.skuId
      marker.style.left = `${parseFloat(x) * 100}%`
      marker.style.top = `${parseFloat(y) * 100}%`
      marker.style.pointerEvents = "none"
      marker.textContent = n
      marker.title = row.dataset.code || ""
      this.markersTarget.appendChild(marker)
    })
  }

  removeMarker(id) {
    const marker = this.markersTarget.querySelector(`.pin-marker[data-sku-id="${id}"]`)
    if (marker) marker.remove()
    this.renderMarkers() // renumber
  }

  // ---- Helpers ----
  isSelected(id) {
    return !!this.rowFor(id)
  }

  rowFor(id) {
    return this.selectedTarget.querySelector(`.selected-sku[data-sku-id="${id}"]`)
  }

  updateMeta() {
    const count = this.selectedItemTargets.length
    if (this.hasSelectedCountTarget) this.selectedCountTarget.textContent = count ? `(${count})` : ""
    if (this.hasEmptyHintTarget) this.emptyHintTarget.style.display = count ? "none" : ""
  }

  rowHtml(id, code, desc) {
    const esc = (s) => (s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
    return `
      <div class="selected-sku" data-processing-target="selectedItem" data-sku-id="${esc(id)}" data-code="${esc(code)}" data-desc="${esc(desc)}">
        <input type="hidden" name="photo[skus][][id]" value="${esc(id)}">
        <input type="hidden" name="photo[skus][][pos_x]" value="" data-role="pos_x">
        <input type="hidden" name="photo[skus][][pos_y]" value="" data-role="pos_y">
        <span class="selected-sku__code">${esc(code)}</span>
        <span class="selected-sku__desc">${esc(desc)}</span>
        <button type="button" class="btn btn--ghost btn--sm" data-action="processing#startPin" data-role="pin">📍 <span data-role="pin-label">Pin</span></button>
        <button type="button" class="chip__remove" data-action="processing#removeSku" aria-label="Remove">×</button>
      </div>`
  }
}
