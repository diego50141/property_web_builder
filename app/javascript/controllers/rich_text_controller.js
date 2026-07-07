import { Controller } from "@hotwired/stimulus"

// Editor de texto simple con formato (negrita, cursiva, subrayado, listas,
// tamaño). Guarda el HTML en un input oculto para enviarlo con el formulario.
export default class extends Controller {
  static targets = ["editor", "input"]

  connect() {
    if (this.hasInputTarget && this.inputTarget.value) {
      this.editorTarget.innerHTML = this.inputTarget.value
    }
    this.sync()
  }

  cmd(event) {
    event.preventDefault()
    const command = event.currentTarget.dataset.command
    document.execCommand(command, false, null)
    this.editorTarget.focus()
    this.sync()
  }

  size(event) {
    const value = event.currentTarget.value
    if (value) document.execCommand("fontSize", false, value)
    event.currentTarget.selectedIndex = 0
    this.editorTarget.focus()
    this.sync()
  }

  sync() {
    if (this.hasInputTarget) this.inputTarget.value = this.editorTarget.innerHTML
  }
}
