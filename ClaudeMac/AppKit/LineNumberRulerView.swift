import AppKit

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    override var isOpaque: Bool { true }

    private let backgroundColor = NSColor.white
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor(calibratedRed: 0.52, green: 0.57, blue: 0.66, alpha: 0.82)
    ]

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 68
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let text = textView.string as NSString
        var lineNumber = 1
        var index = 0

        while index < glyphRange.location, index < text.length {
            if text.character(at: index) == 10 { lineNumber += 1 }
            index += 1
        }

        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphLineRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
            let y = rect.minY + textView.textContainerInset.height - visibleRect.minY + 2
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 18, y: y), withAttributes: attributes)
            glyphIndex = NSMaxRange(glyphLineRange)
            lineNumber += 1
        }
    }
}
