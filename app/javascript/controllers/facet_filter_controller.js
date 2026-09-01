import { Controller } from "@hotwired/stimulus"

const INTERACTION_KEY = "facet-filter:interaction"
let interactionTriggered = false

export default class extends Controller {
  static targets = [
    "panel", "openButton", "sourceFilter", "sourceInput", "contentType",
    "tagSearch", "selectionCount", "initialFocus", "results", "resultsHeading"
  ]

  connect() {
    this.boundEscape = this.handleKeydown.bind(this)
    this.boundTurboLoad = this.handleTurboLoad.bind(this)
    this.boundBeforeCache = this.resetTransientState.bind(this)
    this.boundSyncPanelMode = this.syncPanelMode.bind(this)
    this.mediaQuery = window.matchMedia("(min-width: 881px)")
    this.mediaQuery.addEventListener("change", this.boundSyncPanelMode)
    document.addEventListener("turbo:load", this.boundTurboLoad)
    document.addEventListener("turbo:before-cache", this.boundBeforeCache)
    this.openButtonTarget.disabled = false
    this.updateSourceVisibility()
    this.updateSelectionCount()
    this.syncPanelMode()
  }

  disconnect() {
    this.resetTransientState()
    document.removeEventListener("keydown", this.boundEscape)
    document.removeEventListener("turbo:load", this.boundTurboLoad)
    document.removeEventListener("turbo:before-cache", this.boundBeforeCache)
    this.mediaQuery?.removeEventListener("change", this.boundSyncPanelMode)
  }

  open(event) {
    event.preventDefault()
    this.lastFocusedElement = document.activeElement
    this.panelTarget.classList.add("is-open")
    this.panelTarget.setAttribute("role", "dialog")
    this.panelTarget.setAttribute("aria-modal", "true")
    this.panelTarget.setAttribute("aria-labelledby", "filters-title")
    this.panelTarget.setAttribute("aria-hidden", "false")
    this.setBackgroundInert(true)
    document.body.classList.add("filter-sheet-open")
    document.addEventListener("keydown", this.boundEscape)
    requestAnimationFrame(() => this.initialFocusTarget.focus({ preventScroll: true }))
  }

  close(event) {
    event?.preventDefault()
    this.panelTarget.classList.remove("is-open")
    this.deactivateDialog()
    this.setBackgroundInert(false)
    document.body.classList.remove("filter-sheet-open")
    document.removeEventListener("keydown", this.boundEscape)
    this.lastFocusedElement?.focus({ preventScroll: true })
  }

  submit(event) {
    if (this.submitting) {
      event.preventDefault()
      return
    }
    this.submitting = true
    interactionTriggered = true
    sessionStorage.setItem(INTERACTION_KEY, "true")
    this.setBusy(true)
    this.setSubmittingControls(event.submitter)
    this.close()
  }

  contentTypeChanged() {
    this.updateSourceVisibility()
    this.updateSelectionCount()
  }

  selectionChanged() { this.updateSelectionCount() }

  filterTags() {
    const query = this.tagSearchTarget.value.trim().toLowerCase()
    this.panelTarget.querySelectorAll("[data-tag-option]").forEach((option) => {
      option.hidden = query.length > 0 && !(option.dataset.tagName || "").includes(query)
    })
  }

  handleKeydown(event) {
    if (!this.panelTarget.classList.contains("is-open")) return
    if (event.key === "Escape") {
      this.close(event)
      return
    }
    if (event.key !== "Tab") return
    const focusable = this.focusableDialogElements()
    if (focusable.length === 0) return
    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  updateSourceVisibility() {
    const blogSelected = this.contentTypeTargets.some((input) => input.value === "blog" && input.checked)
    this.sourceFilterTarget.hidden = !blogSelected
    this.sourceInputTargets.forEach((input) => { input.disabled = !blogSelected })
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
      this.close()
      this.deactivateDialog({ visible: true })
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

  setBackgroundInert(inert) {
    const catalogContent = Array.from(this.element.querySelectorAll("*"))
      .filter((element) => element !== this.panelTarget &&
        !this.panelTarget.contains(element) &&
        !element.contains(this.panelTarget))
    const siblings = [
      ...Array.from(document.body.children).filter((element) => !element.contains(this.element)),
      ...catalogContent
    ]
    this.inertElements = [...new Set(siblings)]
    this.inertElements.forEach((element) => { element.inert = inert })
  }

  setBusy(busy) {
    if (this.hasResultsTarget) this.resultsTarget.setAttribute("aria-busy", busy ? "true" : "false")
  }

  setSubmittingControls(submitter) {
    this.element.querySelectorAll("button[type='submit'], input[type='submit']").forEach((control) => {
      control.dataset.originalLabel ||= control.value || control.textContent
      control.disabled = true
      const progress = control === submitter && control.classList.contains("resource-search-submit") ? "検索中…" : "反映中…"
      if (control.tagName === "INPUT") control.value = progress
      else control.textContent = progress
    })
  }

  focusableDialogElements() {
    return Array.from(this.panelTarget.querySelectorAll("a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"))
      .filter((element) => element.offsetParent !== null)
  }

  handleTurboLoad() {
    this.submitting = false
    this.setBusy(false)
    if (sessionStorage.getItem(INTERACTION_KEY) !== "true" && !interactionTriggered) return
    sessionStorage.removeItem(INTERACTION_KEY)
    interactionTriggered = false
    if (!this.hasResultsHeadingTarget) return
    this.resultsHeadingTarget.focus({ preventScroll: true })
    this.resultsHeadingTarget.scrollIntoView({ block: "start", behavior: "smooth" })
  }

  resetTransientState() {
    this.submitting = false
    this.setBusy(false)
    this.setBackgroundInert(false)
    this.panelTarget?.classList.remove("is-open")
    if (this.panelTarget) this.deactivateDialog()
    document.body.classList.remove("filter-sheet-open")
    document.removeEventListener("keydown", this.boundEscape)
    sessionStorage.removeItem(INTERACTION_KEY)
    this.element?.querySelectorAll("button[type='submit'], input[type='submit']").forEach((control) => {
      control.disabled = false
      if (!control.dataset.originalLabel) return
      if (control.tagName === "INPUT") control.value = control.dataset.originalLabel
      else control.textContent = control.dataset.originalLabel
    })
  }
}
