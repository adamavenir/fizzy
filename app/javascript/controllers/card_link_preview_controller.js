import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String
  }

  connect() {
    this.tooltip = null
    this.timeoutId = null
    this.isLoading = false
  }

  disconnect() {
    this.removeTooltip()
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
    }
  }

  mouseEnter(event) {
    // Delay 300ms before showing
    this.timeoutId = setTimeout(() => {
      this.showTooltip(event.target)
    }, 300)
  }

  mouseLeave() {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
      this.timeoutId = null
    }
    this.removeTooltip()
  }

  async showTooltip(anchor) {
    if (this.isLoading || this.tooltip) return

    this.isLoading = true

    try {
      const response = await fetch(this.urlValue)
      if (!response.ok) {
        this.isLoading = false
        return
      }

      const html = await response.text()

      // Create tooltip div
      this.tooltip = document.createElement('div')
      this.tooltip.className = 'card-preview-tooltip'
      this.tooltip.innerHTML = html

      // Position near link
      this.positionTooltip(this.tooltip, anchor)

      document.body.appendChild(this.tooltip)
    } catch (error) {
      console.error("Failed to load preview:", error)
    } finally {
      this.isLoading = false
    }
  }

  removeTooltip() {
    if (this.tooltip) {
      this.tooltip.remove()
      this.tooltip = null
    }
  }

  positionTooltip(tooltip, anchor) {
    const rect = anchor.getBoundingClientRect()
    const tooltipHeight = 250 // Approximate height
    const space = {
      above: rect.top,
      below: window.innerHeight - rect.bottom
    }

    // Position tooltip below or above depending on space
    if (space.below > tooltipHeight || space.below > space.above) {
      // Show below
      tooltip.style.top = `${rect.bottom + window.scrollY + 10}px`
    } else {
      // Show above
      tooltip.style.top = `${rect.top + window.scrollY - tooltipHeight - 10}px`
    }

    // Horizontal positioning
    const left = rect.left + window.scrollX
    const maxLeft = window.innerWidth - 320 // tooltip width + padding
    tooltip.style.left = `${Math.min(left, maxLeft)}px`
  }
}
