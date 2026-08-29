import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select"]

  connect() {
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.preference = localStorage.getItem("appearance") || "system"
    if (this.hasSelectTarget) this.selectTarget.value = this.preference
    this.apply()
    this.media.addEventListener("change", this.systemChanged)
  }

  disconnect() {
    this.media?.removeEventListener("change", this.systemChanged)
  }

  change(event) {
    this.preference = event.target.value
    localStorage.setItem("appearance", this.preference)
    this.apply()
  }

  systemChanged = () => {
    if (this.preference === "system") this.apply()
  }

  apply() {
    const dark = this.preference === "dark" || (this.preference === "system" && this.media.matches)
    document.documentElement.dataset.theme = dark ? "dark" : "light"
  }
}
