import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  focus(event) {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return
    if (["INPUT", "TEXTAREA", "SELECT"].includes(event.target.tagName) || event.target.isContentEditable) return
    if (!this.hasInputTarget) return

    event.preventDefault()
    this.inputTarget.focus()
  }
}
