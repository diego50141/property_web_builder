import { Controller } from "@hotwired/stimulus"

// Kanban de prospectos: arrastra tarjetas entre columnas (etapas) y persiste el
// cambio con un PATCH a /site_admin/pipeline/:id. UI optimista: la tarjeta se
// mueve en el DOM de inmediato; si el guardado falla, se revierte.
export default class extends Controller {
  static values = { urlTemplate: String }

  connect() {
    this.dragged = null
  }

  dragStart(event) {
    this.dragged = event.target.closest("[data-contact-id]")
    if (this.dragged) {
      event.dataTransfer.effectAllowed = "move"
      this.dragged.classList.add("opacity-50")
    }
  }

  dragEnd() {
    if (this.dragged) this.dragged.classList.remove("opacity-50")
    this.dragged = null
  }

  dragOver(event) {
    event.preventDefault()
    event.currentTarget.classList.add("ring-2", "ring-blue-400", "bg-blue-50")
  }

  dragLeave(event) {
    event.currentTarget.classList.remove("ring-2", "ring-blue-400", "bg-blue-50")
  }

  drop(event) {
    event.preventDefault()
    const zone = event.currentTarget
    zone.classList.remove("ring-2", "ring-blue-400", "bg-blue-50")
    const card = this.dragged
    if (!card) return

    const fromZone = card.parentElement
    const stage = zone.dataset.stage
    if (fromZone === zone) return

    const placeholder = zone.querySelector("[data-empty-hint]")
    if (placeholder) placeholder.remove()

    zone.appendChild(card)
    this.refreshCounts()

    this.persist(card.dataset.contactId, stage).catch(() => {
      fromZone.appendChild(card) // revertir si falla
      this.refreshCounts()
    })
  }

  async persist(id, stage) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const url = this.urlTemplateValue.replace(":id", id)
    const res = await fetch(url, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": token || "",
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
      },
      body: `stage=${encodeURIComponent(stage)}`,
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
  }

  refreshCounts() {
    this.element.querySelectorAll("[data-stage]").forEach((zone) => {
      const count = zone.querySelectorAll("[data-contact-id]").length
      const badge = zone.closest("[data-column]")?.querySelector("[data-count]")
      if (badge) badge.textContent = count
    })
  }
}
