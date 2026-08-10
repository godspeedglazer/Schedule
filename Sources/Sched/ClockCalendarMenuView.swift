import AppKit

final class ClockCalendarMenuView: NSView {
    private var displayedDate: Date
    private let calendar: Calendar
    private let onSelectDate: ((Date) -> Void)?

    init(
        date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        onSelectDate: ((Date) -> Void)? = nil
    ) {
        self.displayedDate = date
        self.calendar = calendar
        self.onSelectDate = onSelectDate
        super.init(frame: NSRect(x: 0, y: 0, width: 292, height: 190))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 292).isActive = true
        heightAnchor.constraint(equalToConstant: 190).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let monthFormatter = DateFormatter()
        monthFormatter.locale = .autoupdatingCurrent
        monthFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        drawText(
            monthFormatter.string(from: displayedDate),
            rect: NSRect(x: 16, y: 10, width: bounds.width - 92, height: 24),
            font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            color: .labelColor,
            alignment: .left
        )

        drawText("‹", rect: previousMonthRect, font: NSFont.systemFont(ofSize: 20), color: .secondaryLabelColor, alignment: .center)
        drawText("›", rect: nextMonthRect, font: NSFont.systemFont(ofSize: 20), color: .secondaryLabelColor, alignment: .center)

        let symbols = reorderedWeekdaySymbols()
        for column in 0..<7 {
            drawText(
                symbols[column],
                rect: NSRect(x: gridX + CGFloat(column) * columnWidth, y: weekdayY, width: columnWidth, height: 18),
                font: NSFont.systemFont(ofSize: 10, weight: .medium),
                color: .secondaryLabelColor,
                alignment: .center
            )
        }

        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedDate),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedDate) else { return }

        let monthStart = monthInterval.start
        let leading = leadingDays(for: monthStart)
        let today = Date()

        for day in dayRange {
            let dayDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
            let cell = cellRect(index: leading + day - 1)
            let isToday = calendar.isDate(dayDate, inSameDayAs: today)

            if isToday {
                let diameter: CGFloat = 21
                let pill = NSRect(x: cell.midX - diameter / 2, y: cell.midY - diameter / 2, width: diameter, height: diameter)
                SchedDesign.accent.setFill()
                NSBezierPath(roundedRect: pill, xRadius: 7, yRadius: 7).fill()
            }

            drawText(
                "\(day)",
                rect: cell,
                font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: isToday ? .semibold : .regular),
                color: isToday ? .white : .labelColor,
                alignment: .center
            )
        }
    }

    private let gridX: CGFloat = 14
    private var gridWidth: CGFloat { bounds.width - 28 }
    private var columnWidth: CGFloat { gridWidth / 7 }
    private let weekdayY: CGFloat = 42
    private let gridY: CGFloat = 62
    private let cellHeight: CGFloat = 20

    private var previousMonthRect: NSRect { NSRect(x: bounds.width - 62, y: 8, width: 24, height: 28) }
    private var nextMonthRect: NSRect { NSRect(x: bounds.width - 34, y: 8, width: 24, height: 28) }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if previousMonthRect.contains(point) {
            moveMonth(-1)
            return
        }
        if nextMonthRect.contains(point) {
            moveMonth(1)
            return
        }

        guard point.y >= gridY,
              let monthStart = calendar.dateInterval(of: .month, for: displayedDate)?.start,
              let dayRange = calendar.range(of: .day, in: .month, for: displayedDate) else {
            super.mouseDown(with: event)
            return
        }

        let column = Int((point.x - gridX) / columnWidth)
        let row = Int((point.y - gridY) / cellHeight)
        guard (0..<7).contains(column), (0..<6).contains(row) else { return }
        let index = row * 7 + column
        let day = index - leadingDays(for: monthStart) + 1
        guard dayRange.contains(day),
              let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { return }
        onSelectDate?(date)
    }

    private func moveMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: displayedDate) {
            displayedDate = next
            needsDisplay = true
        }
    }

    private func leadingDays(for monthStart: Date) -> Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func cellRect(index: Int) -> NSRect {
        let row = index / 7
        let column = index % 7
        return NSRect(
            x: gridX + CGFloat(column) * columnWidth,
            y: gridY + CGFloat(row) * cellHeight,
            width: columnWidth,
            height: cellHeight
        )
    }

    private func reorderedWeekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        let source = formatter.veryShortStandaloneWeekdaySymbols ?? formatter.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        guard source.count == 7 else { return source }
        let offset = max(0, min(6, calendar.firstWeekday - 1))
        return Array(source[offset...]) + Array(source[..<offset])
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
    }
}
