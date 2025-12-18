import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    text: String
  }

  copy(event) {
    event.preventDefault()

    navigator.clipboard.writeText(this.textValue).then(() => {
      this.showCopiedFeedback()
    }).catch(err => {
      console.error("Failed to copy:", err)
    })
  }

  showCopiedFeedback() {
    const originalText = this.element.textContent
    const originalClasses = this.element.className

    this.element.textContent = "Copied!"
    this.element.classList.add("txt-positive")

    setTimeout(() => {
      this.element.textContent = originalText
      this.element.className = originalClasses
    }, 1500)
  }
}
