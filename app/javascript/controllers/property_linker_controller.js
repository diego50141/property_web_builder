import { Controller } from "@hotwired/stimulus"

// Enlaza inmuebles al cliente: agrega/quita filas con un input oculto
// (linked_property_ids[]) que se envía con el formulario.
export default class extends Controller {
  static targets = ["select", "list", "empty"]

  add(event) {
    event.preventDefault()
    const option = this.selectTarget.selectedOptions[0]
    if (!option || !option.value) return

    const id = option.value
    if (this.listTarget.querySelector(`[data-asset-id="${id}"]`)) return
    if (this.hasEmptyTarget) this.emptyTarget.remove()

    const row = document.createElement("tr")
    row.dataset.assetId = id
    row.className = "border-t border-gray-100"
    row.innerHTML =
      `<td class="px-4 py-2 text-sm">${option.text}` +
      `<input type="hidden" name="linked_property_ids[]" value="${id}"></td>` +
      `<td class="px-4 py-2 text-right"><button type="button" data-action="property-linker#remove" ` +
      `class="text-red-600 hover:text-red-800 text-xs font-medium">Quitar</button></td>`
    this.listTarget.appendChild(row)
    this.selectTarget.selectedIndex = 0
  }

  remove(event) {
    event.preventDefault()
    event.currentTarget.closest("tr").remove()
  }
}
