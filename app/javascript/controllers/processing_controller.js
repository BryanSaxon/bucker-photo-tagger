import { Controller } from "@hotwired/stimulus"

// Drives the photo processing screen: live SKU search, the selected-SKU list
// (with hidden form inputs Rails parses into photo[skus][]), community→floorplan
// filtering, and click-to-pin location tagging on the photo.
export default class extends Controller {
  static targets = [
    "stage", "image", "markers", "community", "floorplan", "room", "scopeToggle",
    "search", "results", "selected", "selectedItem", "selectedCount", "emptyHint"
  ]
  static values = { skuSearchUrl: String, rowUrl: String }

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

  // Grey out results already selected — but only products without variants,
  // since one with finishes can legitimately be added again.
  syncResultDisabledState() {
    this.resultsTarget.querySelectorAll(".sku-result").forEach((el) => {
      el.disabled = el.dataset.hasVariants !== "true" && !!this.rowFor(el.dataset.skuId, "")
    })
  }

  // ---- Selection ----
  async addSku(event) {
    const el = event.currentTarget
    const id = el.dataset.skuId
    const hasVariants = el.dataset.hasVariants === "true"
    // A product with finishes may be added again (a second finish in the same
    // photo); one without can only be tagged once.
    if (!hasVariants && this.rowFor(id, "")) return

    // Rendered server-side so the variant options come from the Sku record and
    // this markup exists in exactly one place.
    const url = new URL(this.rowUrlValue, window.location.origin)
    url.searchParams.set("sku_id", id)
    try {
      const res = await fetch(url, { headers: { Accept: "text/html" } })
      if (!res.ok) throw new Error(res.status)
      // Append to the END so existing pin numbers don't shift around.
      this.selectedTarget.insertAdjacentHTML("beforeend", await res.text())
    } catch (e) {
      this.resultsTarget.innerHTML =
        `<p class="text-mono-sm" style="padding:8px 2px;">Couldn’t add that SKU — try again.</p>`
      return
    }

    // Hide the results and clear the search so the user can type the next item.
    this.resultsTarget.innerHTML = ""
    this.searchTarget.value = ""
    this.searchTarget.focus()

    this.updateMeta()
  }

  removeSku(event) {
    const row = event.currentTarget.closest(".selected-sku")
    const id = row.dataset.skuId
    const rowKey = this.rowKey(row)
    row.remove()
    this.removeMarker(rowKey)
    // Re-enable the matching search result if it's still shown.
    const result = this.resultsTarget.querySelector(`.sku-result[data-sku-id="${id}"]`)
    if (result && !this.rowFor(id, "")) result.disabled = false
    if (this.pinningId === rowKey) this.stopPinning()
    this.updateMeta()
  }

  // ---- Variant picker ----
  // Choosing "Other…" swaps the form field over to the free-text input, so
  // exactly one variant_value per row reaches the server and the "__other__"
  // sentinel never does.
  variantChanged(event) {
    const select = event.currentTarget
    const row = select.closest(".selected-sku")
    const other = row.querySelector('[data-role="variant-other"]')
    const isOther = select.value === "__other__"

    other.style.display = isOther ? "" : "none"
    if (isOther) { other.focus() } else { other.value = "" }
    this.syncVariant(row)
  }

  variantOtherChanged(event) {
    this.syncVariant(event.currentTarget.closest(".selected-sku"))
  }

  syncVariant(row) {
    const select = row.querySelector('[data-role="variant-select"]')
    const other = row.querySelector('[data-role="variant-other"]')
    if (!select) return

    const isOther = select.value === "__other__"
    const value = isOther ? other.value.trim() : select.value

    select.name = isOther ? "" : "photo[skus][][variant_value]"
    other.name = isOther ? "photo[skus][][variant_value]" : ""

    row.dataset.variant = value
    row.dataset.rowKey = `${row.dataset.skuId}::${value}`
    this.renderMarkers()
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

  // Pins are tracked by (sku, variant) so the two finishes of one product can
  // be pinned to different points in the same photo.
  startPin(row) {
    const rowKey = this.rowKey(row)
    if (this.pinningId === rowKey) { this.stopPinning(); return }
    this.pinningId = rowKey
    this.stageTarget.classList.add("is-pinning")
  }

  unpin(row) {
    row.querySelector('[data-role="pos_x"]').value = ""
    row.querySelector('[data-role="pos_y"]').value = ""
    row.classList.remove("is-pinned")
    const label = row.querySelector('[data-role="pin-label"]')
    if (label) label.textContent = "Pin"
    const rowKey = this.rowKey(row)
    if (this.pinningId === rowKey) this.stopPinning()
    this.removeMarker(rowKey)
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

    const row = this.selectedTarget.querySelector(
      `.selected-sku[data-row-key="${CSS.escape(this.pinningId)}"]`
    )
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
      // Keyed by (sku, variant): keying on the sku alone made the two finishes
      // of one product share a marker.
      marker.dataset.rowKey = this.rowKey(row)
      marker.style.left = `${parseFloat(x) * 100}%`
      marker.style.top = `${parseFloat(y) * 100}%`
      marker.style.pointerEvents = "none"
      marker.textContent = n
      marker.title = row.dataset.code || ""
      this.markersTarget.appendChild(marker)
    })
  }

  removeMarker(rowKey) {
    const marker = this.markersTarget.querySelector(`.pin-marker[data-row-key="${CSS.escape(rowKey)}"]`)
    if (marker) marker.remove()
    this.renderMarkers() // renumber
  }

  // ---- Helpers ----
  // A tag is identified by (sku, variant), so a product with finishes can be
  // present more than once and each row is addressed by both.
  rowFor(id, variant = "") {
    return this.selectedTarget.querySelector(
      `.selected-sku[data-sku-id="${id}"][data-variant="${CSS.escape(variant)}"]`
    )
  }

  rowKey(row) {
    return `${row.dataset.skuId}::${row.dataset.variant || ""}`
  }

  updateMeta() {
    const count = this.selectedItemTargets.length
    if (this.hasSelectedCountTarget) this.selectedCountTarget.textContent = count ? `(${count})` : ""
    if (this.hasEmptyHintTarget) this.emptyHintTarget.style.display = count ? "none" : ""
  }

  // (rowHtml removed — rows are rendered by photos#selected_sku_row so
  // _selected_sku.html.erb is the only place this markup lives.)
}
