import { Controller } from "@hotwired/stimulus"
import { debounce } from "helpers/timing_helpers"

export default class extends Controller {
  static targets = ["title", "description"]
  static values = { key: String }

  initialize() {
    this.save = debounce(this.save.bind(this), 300)
  }

  connect() {
    this.restoreContent()
  }

  save() {
    const draft = {
      title: this.titleTarget.value,
      description: this.descriptionTarget.value
    }

    if (draft.title || draft.description) {
      localStorage.setItem(this.keyValue, JSON.stringify(draft))
    } else {
      this.clear()
    }
  }

  submit({ detail: { success } }) {
    if (success) {
      this.clear()
    }
  }

  clear() {
    localStorage.removeItem(this.keyValue)
  }

  restoreContent() {
    const savedDraft = localStorage.getItem(this.keyValue)

    if (savedDraft) {
      try {
        const draft = JSON.parse(savedDraft)

        if (draft.title && this.titleTarget) {
          this.titleTarget.value = draft.title
          this.titleTarget.dispatchEvent(new Event('input', { bubbles: true }))
        }

        if (draft.description && this.descriptionTarget) {
          this.descriptionTarget.value = draft.description
        }
      } catch (e) {
        console.error('Failed to restore draft:', e)
        this.clear()
      }
    }
  }
}
