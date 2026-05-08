import AppKit
import SwiftUI

struct TextEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    var fileName: String = ""
    var onTextChange: (String) -> Void
    var onCursorChange: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = SyntaxHighlighter.baseColor
        textView.insertionPointColor = .controlAccentColor
        textView.selectedTextAttributes = [
            .backgroundColor: SyntaxHighlighter.selectionColor,
            .foregroundColor: SyntaxHighlighter.baseColor
        ]
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        configureTextLayout(textView)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        context.coordinator.textView = textView
        context.coordinator.rulerView = ruler
        context.coordinator.applyHighlighting()
        DispatchQueue.main.async {
            resetHorizontalOrigin(in: scrollView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let previousFileName = context.coordinator.parent.fileName
        context.coordinator.parent = self
        if textView.string != text {
            configureTextLayout(textView)
            context.coordinator.rulerView?.ruleThickness = 68
            textView.string = text
            context.coordinator.applyHighlighting()
            DispatchQueue.main.async {
                configureTextLayout(textView)
                resetHorizontalOrigin(in: scrollView)
            }
            context.coordinator.rulerView?.needsDisplay = true
        } else if previousFileName != fileName {
            configureTextLayout(textView)
            context.coordinator.rulerView?.ruleThickness = 68
            context.coordinator.applyHighlighting()
            DispatchQueue.main.async {
                configureTextLayout(textView)
                resetHorizontalOrigin(in: scrollView)
            }
            context.coordinator.rulerView?.needsDisplay = true
        }
    }

    private func configureTextLayout(_ textView: NSTextView) {
        textView.textContainerInset = NSSize(width: 26, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }
    }

    private func resetHorizontalOrigin(in scrollView: NSScrollView) {
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: 0, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextEditorRepresentable
        weak var textView: NSTextView?
        weak var rulerView: LineNumberRulerView?
        private var isApplyingHighlighting = false

        init(parent: TextEditorRepresentable) {
            self.parent = parent
        }

        func applyHighlighting() {
            guard let textView, !isApplyingHighlighting else { return }
            isApplyingHighlighting = true
            defer { isApplyingHighlighting = false }
            SyntaxHighlighter.apply(to: textView, fileName: parent.fileName)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            applyHighlighting()
            let newText = textView.string
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                parent.text = newText
                parent.onTextChange(newText)
                rulerView?.needsDisplay = true
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let location = textView.selectedRange().location
            let nsString = textView.string as NSString
            let prefix = nsString.substring(to: min(location, nsString.length))
            let lines = prefix.components(separatedBy: .newlines)
            let line = lines.count
            let column = (lines.last?.count ?? 0) + 1
            DispatchQueue.main.async { [weak self] in
                self?.parent.onCursorChange(line, column)
            }
        }
    }
}

private enum SyntaxHighlighter {
    static let baseColor = NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.20, alpha: 1)
    static let selectionColor = NSColor(calibratedRed: 0.74, green: 0.84, blue: 1.00, alpha: 0.55)

    private static let keywordColor = NSColor(calibratedRed: 0.11, green: 0.31, blue: 0.85, alpha: 1)
    private static let stringColor = NSColor(calibratedRed: 0.08, green: 0.50, blue: 0.24, alpha: 1)
    private static let commentColor = NSColor(calibratedRed: 0.42, green: 0.45, blue: 0.50, alpha: 1)
    private static let typeColor = NSColor(calibratedRed: 0.49, green: 0.23, blue: 0.93, alpha: 1)
    private static let numberColor = NSColor(calibratedRed: 0.71, green: 0.33, blue: 0.04, alpha: 1)
    private static let functionColor = NSColor(calibratedRed: 0.05, green: 0.46, blue: 0.44, alpha: 1)
    private static let attributeColor = NSColor(calibratedRed: 0.76, green: 0.25, blue: 0.05, alpha: 1)
    private static let keyColor = NSColor(calibratedRed: 0.04, green: 0.45, blue: 0.55, alpha: 1)

    static func apply(to textView: NSTextView, fileName: String) {
        guard let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        let selectedRange = textView.selectedRange()
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .light)
        let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)

        storage.beginEditing()
        storage.setAttributes([
            .font: font,
            .foregroundColor: baseColor
        ], range: fullRange)

        guard fullRange.length > 0 else {
            storage.endEditing()
            return
        }

        let language = SyntaxLanguage(fileName: fileName)
        let stringRanges = ranges(pattern: stringPattern(for: language), storage: storage, range: fullRange)
        let commentRanges = ranges(pattern: commentPattern(for: language), storage: storage, range: fullRange)
            .filter { !intersects($0, stringRanges) }
        let protectedRanges = stringRanges + commentRanges

        if language == .markdown {
            apply(pattern: #"(?m)^\s{0,3}#{1,6}\s+.+$"#, attributes: [.foregroundColor: keywordColor], storage: storage, range: fullRange)
            apply(pattern: #"(?m)^\s*(?:[-*+]|\d+\.)\s+"#, attributes: [.foregroundColor: attributeColor], storage: storage, range: fullRange)
            apply(pattern: #"\[[^\]\n]+\]\([^\)\n]+\)"#, attributes: [.foregroundColor: keyColor], storage: storage, range: fullRange)
        }

        if language == .json || language == .yaml {
            apply(pattern: #"(?m)(^|[,\{]\s*)(\"?[A-Za-z_][A-Za-z0-9_ .-]*\"?)(\s*:)"#, captureGroup: 2, attributes: [.foregroundColor: keyColor], storage: storage, range: fullRange, excluding: protectedRanges)
            apply(pattern: #"(?m)^\s*([A-Za-z_][A-Za-z0-9_ .-]*)(?=\s*:)"#, captureGroup: 1, attributes: [.foregroundColor: keyColor], storage: storage, range: fullRange, excluding: protectedRanges)
        }

        apply(pattern: keywordPattern(for: language), attributes: [.foregroundColor: keywordColor], storage: storage, range: fullRange, excluding: protectedRanges)
        apply(pattern: #"\b([A-Z][A-Za-z0-9_]*|String|Int|Double|Float|Bool|Array|Dictionary|Set|URL|UUID|Date|Data|View|Color|Text|Button|Image|Result|Task|DateFormatter|URLRequest|JSONDecoder|JSONEncoder)\b"#, attributes: [.foregroundColor: typeColor], storage: storage, range: fullRange, excluding: protectedRanges)
        apply(pattern: #"\b(?:0x[0-9A-Fa-f_]+|\d[\d_]*(?:\.\d[\d_]*)?)(?:[eE][+-]?\d+)?\b"#, attributes: [.foregroundColor: numberColor], storage: storage, range: fullRange, excluding: protectedRanges)
        apply(pattern: #"\b(?:func|function|def|fn)\s+([A-Za-z_][A-Za-z0-9_]*)"#, captureGroup: 1, attributes: [.foregroundColor: functionColor], storage: storage, range: fullRange, excluding: protectedRanges)
        apply(pattern: #"\b(?!if\b|for\b|while\b|switch\b|catch\b|guard\b|return\b|func\b|function\b|def\b|fn\b|try\b|await\b)([a-z_][A-Za-z0-9_]*)\s*(?=\()"#, captureGroup: 1, attributes: [.foregroundColor: functionColor], storage: storage, range: fullRange, excluding: protectedRanges)
        apply(pattern: #"@[A-Za-z_][A-Za-z0-9_]*|#(?:if|else|elseif|endif|available|selector|keyPath|file|line|warning|error)\b"#, attributes: [.foregroundColor: attributeColor], storage: storage, range: fullRange, excluding: stringRanges)
        apply(ranges: stringRanges, attributes: [.foregroundColor: stringColor], storage: storage)
        apply(ranges: commentRanges, attributes: [.foregroundColor: commentColor, .font: italicFont], storage: storage)

        storage.endEditing()
        textView.setSelectedRange(NSRange(location: min(selectedRange.location, text.length), length: min(selectedRange.length, max(0, text.length - min(selectedRange.location, text.length)))))
    }

    private static func apply(pattern: String, captureGroup: Int = 0, attributes: [NSAttributedString.Key: Any], storage: NSTextStorage, range: NSRange, excluding excludedRanges: [NSRange] = []) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        regex.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let match, captureGroup < match.numberOfRanges else { return }
            let matchRange = match.range(at: captureGroup)
            guard matchRange.location != NSNotFound, !intersects(matchRange, excludedRanges) else { return }
            storage.addAttributes(attributes, range: matchRange)
        }
    }

    private static func apply(ranges: [NSRange], attributes: [NSAttributedString.Key: Any], storage: NSTextStorage) {
        ranges.forEach { storage.addAttributes(attributes, range: $0) }
    }

    private static func ranges(pattern: String, storage: NSTextStorage, range: NSRange) -> [NSRange] {
        guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        var result: [NSRange] = []
        regex.enumerateMatches(in: storage.string, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            result.append(matchRange)
        }
        return result
    }

    private static func intersects(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange(range, $0).length > 0 }
    }

    private static func stringPattern(for language: SyntaxLanguage) -> String {
        if language == .markdown { return #"`[^`\n]+`"# }
        return ###"("""[\s\S]*?"""|#{0,3}"(?:\\.|[^"\\])*"#{0,3}|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)"###
    }

    private static func commentPattern(for language: SyntaxLanguage) -> String {
        switch language {
        case .json, .markdown, .plain:
            return ""
        case .python, .shell, .yaml:
            return #"#[^\n]*"#
        default:
            return #"//[^\n]*|/\*[\s\S]*?\*/"#
        }
    }

    private static func keywordPattern(for language: SyntaxLanguage) -> String {
        switch language {
        case .json, .yaml:
            return #"\b(true|false|null|yes|no|on|off)\b"#
        case .markdown, .plain:
            return #"\b(TODO|FIXME|NOTE|IMPORTANT)\b"#
        default:
            return #"\b(import|from|export|package|struct|class|enum|protocol|extension|func|function|def|fn|var|let|const|if|else|elif|guard|return|switch|case|default|for|while|do|try|catch|throw|throws|async|await|private|public|internal|static|final|weak|self|this|super|nil|null|true|false|in|where|as|is|new|interface|type|defer|select|go|range|yield|actor|mutating|nonmutating)\b"#
        }
    }
}

private enum SyntaxLanguage: Equatable {
    case swiftLike
    case javaScript
    case python
    case go
    case json
    case yaml
    case markdown
    case shell
    case plain

    init(fileName: String) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "m", "mm", "h", "java", "kt", "kts", "rs", "cpp", "cc", "cxx", "c", "hpp":
            self = .swiftLike
        case "js", "jsx", "ts", "tsx", "vue", "svelte":
            self = .javaScript
        case "py":
            self = .python
        case "go":
            self = .go
        case "json", "jsonl":
            self = .json
        case "yml", "yaml", "toml":
            self = .yaml
        case "md", "markdown", "mdx":
            self = .markdown
        case "sh", "bash", "zsh", "fish":
            self = .shell
        default:
            self = .plain
        }
    }
}
