import { Controller } from "@hotwired/stimulus"
import { normalizeFilteredText } from "helpers/text_helpers"

export default class extends Controller {
  static targets = [ "input", "tagButton", "createButton" ]

  connect() {
    this.checkForExactMatch()
  }

  checkForExactMatch() {
    if (!this.hasInputTarget || !this.hasCreateButtonTarget) return

    const inputValue = normalizeFilteredText((this.inputTarget.value || "").trim())

    if (inputValue.length === 0) {
      this.createButtonTarget.disabled = true
      return
    }

    const hasExactMatch = this.tagButtonTargets.some(button => {
      const tagTitle = normalizeFilteredText(button.dataset.tagTitle || "")
      return tagTitle === inputValue
    })

    this.createButtonTarget.disabled = hasExactMatch
  }
}
