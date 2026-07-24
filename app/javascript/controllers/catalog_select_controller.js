import { Controller } from "@hotwired/stimulus"

// Cascading Community / Plan / Room selects for the upload form. Any select can
// be used first; choosing one narrows the others:
//   - community  -> filters plans and rooms to that community
//   - plan       -> back-fills its community, then filters rooms
//   - room       -> back-fills its community, then filters plans
// Plans and rooms are provided as compact JSON ({ i: id, l: label, c: community_id }).
export default class extends Controller {
  static targets = ["community", "plan", "room"]
  static values = { plans: Array, rooms: Array }

  connect() {
    this.populatePlans()
    this.populateRooms()
  }

  communityChanged() {
    this.populatePlans()
    this.populateRooms()
  }

  planChanged() {
    const plan = this.plansValue.find((p) => String(p.i) === this.planTarget.value)
    if (plan) {
      this.communityTarget.value = String(plan.c)
      this.populatePlans()
      this.planTarget.value = String(plan.i)
      this.populateRooms()
    }
  }

  roomChanged() {
    const room = this.roomsValue.find((r) => String(r.i) === this.roomTarget.value)
    if (room) {
      this.communityTarget.value = String(room.c)
      this.populatePlans()
      this.populateRooms()
      this.roomTarget.value = String(room.i)
    }
  }

  populatePlans() {
    const cid = this.communityTarget.value
    const items = this.plansValue.filter((p) => !cid || String(p.c) === cid)
    this.fill(this.planTarget, items, "Any plan", this.planTarget.value)
  }

  populateRooms() {
    const cid = this.communityTarget.value
    if (!cid) {
      this.roomTarget.innerHTML = ""
      this.roomTarget.appendChild(new Option("Choose a community or plan first", ""))
      this.roomTarget.disabled = true
      return
    }
    const items = this.roomsValue.filter((r) => String(r.c) === cid)
    this.fill(this.roomTarget, items, "Any room", this.roomTarget.value)
    this.roomTarget.disabled = false
  }

  // Rebuild a select from items, keeping the current value if still valid.
  fill(select, items, placeholder, keep) {
    const keepValid = items.some((i) => String(i.i) === String(keep))
    select.innerHTML = ""
    select.appendChild(new Option(placeholder, ""))
    items.forEach((i) => select.appendChild(new Option(i.l, i.i)))
    select.value = keepValid ? String(keep) : ""
  }
}
