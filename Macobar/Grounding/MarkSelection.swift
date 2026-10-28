import CoreGraphics

/// Turns the targets found on screen into the numbered marks shown to the model.
enum MarkSelection {
    /// Most marks on one screen, so the image stays readable and the list short.
    static let limit = 150
    /// Overlap (intersection over union) above which recognized text is the same thing as an Accessibility target.
    static let duplicateOverlap = 0.5
    /// Share of a piece of text inside a control with the same label above which it is that control's own title.
    static let containedShare = 0.9
    /// Smallest visible width or height worth a mark, in points.
    static let minimumSide: CGFloat = 4

    /// Marks for the targets visible in `visibleArea`, without duplicates, keeping the best `limit` (actionable, then
    /// labelled, then larger first) and numbering them in reading order.
    static func marks(accessibility: [ScreenTarget], recognizedText: [ScreenTarget], visibleArea: CGRect, limit: Int = limit) -> [ScreenMark] {
        let visible = (accessibility + recognizedText).compactMap { clipped($0, to: visibleArea) }
        let distinct = visible.filter { target in !visible.contains { isCovered(target, by: $0) } }
        return distinct.sorted(by: isPreferred).prefix(limit)
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            .enumerated().map { ScreenMark(number: $0.offset + 1, target: $0.element) }
    }

    /// Intersection over union of two rectangles: 0 when apart, 1 when identical.
    static func intersectionOverUnion(_ first: CGRect, _ second: CGRect) -> Double {
        let intersection = area(of: first.intersection(second))
        let union = area(of: first) + area(of: second) - intersection
        return union > 0 ? intersection / union : 0
    }

    /// `target` cut to the part inside `visibleArea`, or nil when too little of it shows.
    private static func clipped(_ target: ScreenTarget, to visibleArea: CGRect) -> ScreenTarget? {
        let frame = target.frame.intersection(visibleArea)
        guard !frame.isNull, frame.width >= minimumSide, frame.height >= minimumSide else { return nil }
        return ScreenTarget(kind: target.kind, label: target.label, frame: frame, source: target.source)
    }

    /// Whether `target` repeats `other`: recognized text over an Accessibility target, or a control's own title inside it.
    /// Other text inside a control (an editor's lines, a field's contents) keeps its own marks.
    private static func isCovered(_ target: ScreenTarget, by other: ScreenTarget) -> Bool {
        guard target != other else { return false }
        if target.source == .textRecognition, other.source == .accessibility,
           intersectionOverUnion(target.frame, other.frame) > duplicateOverlap {
            return true
        }
        guard target.kind == .text, other.kind.isActionable, !other.label.isEmpty, area(of: target.frame) > 0,
              other.label.localizedCaseInsensitiveContains(target.label) || target.label.localizedCaseInsensitiveContains(other.label)
        else { return false }
        return area(of: target.frame.intersection(other.frame)) / area(of: target.frame) >= containedShare
    }

    /// Whether `first` deserves a mark before `second` when there are too many.
    private static func isPreferred(_ first: ScreenTarget, over second: ScreenTarget) -> Bool {
        if first.kind.isActionable != second.kind.isActionable { return first.kind.isActionable }
        if first.label.isEmpty != second.label.isEmpty { return !first.label.isEmpty }
        return area(of: first.frame) > area(of: second.frame)
    }

    /// The area of `rect`, or 0 for the null rectangle.
    private static func area(of rect: CGRect) -> Double {
        rect.isNull ? 0 : Double(rect.width * rect.height)
    }
}
