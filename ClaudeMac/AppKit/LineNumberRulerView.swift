import AppKit

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    override var isOpaque: Bool { false }

    private let backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 0.82)
    private let dividerColor = NSColor.white.withAlphaComponent(0.92)
    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .light),
        .foregroundColor: NSColor(calibratedRed: 0.46, green: 0.50, blue: 0.56, alpha: 1)
    ]

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 42
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        dividerColor.setStroke()
        NSBezierPath.strokeLine(from: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY), to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
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
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y), withAttributes: attributes)
            glyphIndex = NSMaxRange(glyphLineRange)
            lineNumber += 1
        }
    }
}
