import { Controller } from "@hotwired/stimulus"

// Drives the photo processing screen: live SKU search, the selected-SKU list
// (with hidden form inputs Rails parses into photo[skus][]), community→floorplan
// filtering, and click-to-pin location tagging on the photo.
export default class extends Controller {
  static targets = [
    "stage", "image", "markers", "community", "floorplan", "room", "scopeToggle",
    "search", "results", "selected", "selectedItem", "selectedCount", "emptyHint"
  ]
  static values = { skuSearchUrl: String }

  connect() {
    this.pinningId = null
    this.searchTimer = null
    this.filterFloorplans()
    this.filterRooms()
    this.renderMarkers()
    this.updateMeta()
  }

  // Community changed: re-narrow both the plan and room selects.
  contextChanged() {
    this.filterFloorplans()
    this.filterRooms()
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
    if (this.hasScopeToggleTarget && this.scopeToggleTarget.checked) {
      url.searchParams.set("scoped", "1")
    }
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

    // Append to the END so existing pin numbers don't shift around.
    this.selectedTarget.insertAdjacentHTML("beforeend",
      this.rowHtml(id, el.dataset.code, el.dataset.desc))

    // Hide the results and clear the search so the user can type the next item.
    this.resultsTarget.innerHTML = ""
    this.searchTarget.value = ""
    this.searchTarget.focus()

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
  // The pin button toggles: start placing when unpinned, remove the pin when
  // already pinned (so a mis-placed SKU can be re-pinned somewhere else).
  togglePin(event) {
    const row = event.currentTarget.closest(".selected-sku")
    if (row.classList.contains("is-pinned")) {
      this.unpin(row)
    } else {
      this.startPin(row)
    }
  }

  startPin(row) {
    const id = row.dataset.skuId
    if (this.pinningId === id) { this.stopPinning(); return }
    this.pinningId = id
    this.stageTarget.classList.add("is-pinning")
  }

  unpin(row) {
    row.querySelector('[data-role="pos_x"]').value = ""
    row.querySelector('[data-role="pos_y"]').value = ""
    row.classList.remove("is-pinned")
    const label = row.querySelector('[data-role="pin-label"]')
    if (label) label.textContent = "Pin"
    if (this.pinningId === row.dataset.skuId) this.stopPinning()
    this.removeMarker(row.dataset.skuId)
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
    if (label) label.textContent = "Unpin"

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

  // ---- Community → Room filtering ----
  filterRooms() {
    if (!this.hasCommunityTarget || !this.hasRoomTarget) return
    const communityId = this.communityTarget.value
    let cleared = false

    Array.from(this.roomTarget.options).forEach((opt) => {
      if (!opt.value) return
      // With no community chosen, show every room (same rule as floorplans
      // above). Requiring a community here hid all of them, which is what made
      // the room picker look broken.
      const matches = !communityId || opt.dataset.communityId === communityId
      opt.hidden = !matches
      if (!matches && opt.selected) { opt.selected = false; cleared = true }
    })
    if (cleared) this.roomTarget.value = ""
    // Deliberately NOT disabled when no community is set: a disabled select is
    // not submitted, so saving a photo that had a room but no community erased
    // the stored room_id. Photo#context_is_consistent already rejects a genuine
    // mismatch, and SaveSelections back-fills the community from a lone room.
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
        <button type="button" class="btn btn--ghost btn--sm" data-action="processing#togglePin" data-role="pin">📍 <span data-role="pin-label">Pin</span></button>
        <button type="button" class="chip__remove" data-action="processing#removeSku" aria-label="Remove">×</button>
      </div>`
  }
}
