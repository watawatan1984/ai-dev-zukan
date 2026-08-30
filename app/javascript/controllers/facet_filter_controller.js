import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "panel",
    "openButton",
    "sourceFilter",
    "sourceInput",
    "contentType",
    "tagSearch",
    "selectionCount",
    "initialFocus",
  ]

  connect() {
    this.boundEscape = this.handleEscape.bind(this)
    this.mediaQuery = window.matchMedia("(min-width: 881px)")
    this.boundSyncPanelMode = this.syncPanelMode.bind(this)
    this.mediaQuery.addEventListener("change", this.boundSyncPanelMode)
    this.updateSourceVisibility()
    this.updateSelectionCount()
    this.syncPanelMode()
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundEscape)
    this.mediaQuery?.removeEventListener("change", this.boundSyncPanelMode)
    document.body.classList.remove("filter-sheet-open")
  }

  open(event) {
    event.preventDefault()
    this.lastFocusedElement = document.activeElement
    this.panelTarget.classList.add("is-open")
    this.panelTarget.setAttribute("role", "dialog")
    this.panelTarget.setAttribute("aria-modal", "true")
    this.panelTarget.setAttribute("aria-labelledby", "filters-title")
    this.panelTarget.setAttribute("aria-hidden", "false")
    document.body.classList.add("filter-sheet-open")
    document.addEventListener("keydown", this.boundEscape)

    requestAnimationFrame(() => {
      this.initialFocusTarget.focus()
    })
  }

  close(event) {
    event?.preventDefault()
    this.panelTarget.classList.remove("is-open")
    this.deactivateDialog()
    document.body.classList.remove("filter-sheet-open")
    document.removeEventListener("keydown", this.boundEscape)
    this.lastFocusedElement?.focus()
  }

  contentTypeChanged() {
    this.updateSourceVisibility()
    this.updateSelectionCount()
  }

  selectionChanged() {
    this.updateSelectionCount()
  }

  filterTags() {
    const query = this.tagSearchTarget.value.trim().toLowerCase()

    this.panelTarget.querySelectorAll("[data-tag-option]").forEach((option) => {
      const haystack = option.dataset.tagName || ""
      option.hidden = query.length > 0 && !haystack.includes(query)
    })
  }

  handleEscape(event) {
    if (event.key === "Escape" && this.panelTarget.classList.contains("is-open")) {
      this.close(event)
    }
  }

  updateSourceVisibility() {
    const blogSelected = this.contentTypeTargets.some((input) => input.value === "blog" && input.checked)
    this.sourceFilterTarget.hidden = !blogSelected
    this.sourceInputTargets.forEach((input) => {
      input.disabled = !blogSelected
    })
  }

  updateSelectionCount() {
    const checkedCount = this.panelTarget.querySelectorAll("input[type='checkbox']:checked:not(:disabled)").length
    const periodSelected = this.panelTarget.querySelector("select[name='period']")?.value
    const sortSelected = this.panelTarget.querySelector("select[name='sort']")?.value
    let count = checkedCount

    if (periodSelected) count += 1
    if (sortSelected && sortSelected !== "relevance") count += 1

    this.selectionCountTarget.textContent = `${count}件選択中`
  }

  syncPanelMode() {
    if (this.mediaQuery.matches) {
      this.panelTarget.classList.remove("is-open")
      this.deactivateDialog({ visible: true })
      document.body.classList.remove("filter-sheet-open")
      document.removeEventListener("keydown", this.boundEscape)
    } else if (!this.panelTarget.classList.contains("is-open")) {
      this.deactivateDialog()
    }
  }

  deactivateDialog({ visible = false } = {}) {
    this.panelTarget.removeAttribute("role")
    this.panelTarget.removeAttribute("aria-modal")
    this.panelTarget.removeAttribute("aria-labelledby")
    this.panelTarget.setAttribute("aria-hidden", visible ? "false" : "true")
  }
}
