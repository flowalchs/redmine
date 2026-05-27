import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
  #bulletPattern = /^\s*[*+\-] /
  #orderedPattern = /^\s*\d+[.)] /

  run(event) {
    const format = event.params.textFormatting
    if (format !== 'common_mark') return

    const input = event.currentTarget
    const { selectionStart, selectionEnd, value } = input
    const hasSelection = selectionStart !== selectionEnd
    if (!hasSelection) return
    const start = value.lastIndexOf("\n", selectionStart - 1) + 1
    const end = value.indexOf("\n", selectionEnd)
    const endPos = end === -1 ? value.length : end
    const selectedText = value.slice(start, endPos)
    const lines = selectedText.split("\n")
    const spaces = this.#indentSize(lines.find(l => this.#indentSize(l)) || "")
    if (!spaces) return

    event.preventDefault()

    const newLines = event.shiftKey
      ? lines.map(line => this.#unindentLine(line, spaces))
      : lines.map(line => this.#indentLine(line, spaces))

    const newText = newLines.join("\n")

    input.setRangeText(newText, start, endPos, "preserve")
  }

  #indentSize(line) {
    if (this.#bulletPattern.test(line)) return 2
    if (this.#orderedPattern.test(line)) return 4
    return 0
  }

  #indentLine(line, spaces) {
    if (!this.#indentSize(line)) return line
    return " ".repeat(spaces) + line
  }

  #unindentLine(line, spaces) {
    const currentIndent = line.match(/^(\s*)/)[1].length
    const remove = Math.min(spaces, currentIndent)
    return line.slice(remove)
  }

}
