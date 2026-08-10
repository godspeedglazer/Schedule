import AppKit

final class ClockCalendarMenuView: NSView {
    private var displayedDate: Date
    private let calendar: Calendar

    init(date: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        self.displayedDate = date
        self.calendar = calendar
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
            rect: NSRect(x: 16, y: 10, width: bounds.width - 32, height: 24),
            font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            color: .labelColor,
            alignment: .left
        )

        drawText(
            "‹",
            rect: previousMonthRect,
            font: NSFont.systemFont(ofSize: 20, weight: .regular),
            color: .secondaryLabelColor,
            alignment: .center
        )
        drawText(
            "›",
            rect: nextMonthRect,
            font: NSFont.systemFont(ofSize: 20, weight: .regular),
            color: .secondaryLabelColor,
            alignment: .center
        )

        let symbols = reorderedWeekdaySymbols()
        let gridX: CGFloat = 14
        let gridWidth = bounds.width - 28
        let columnWidth = gridWidth / 7
        let weekdayY: CGFloat = 42
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
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let today = Date()
        let cellHeight: CGFloat = 20
        let gridY: CGFloat = 62

        for day in dayRange {
            let index = leading + day - 1
            let row = index / 7
            let column = index % 7
            let cell = NSRect(
                x: gridX + CGFloat(column) * columnWidth,
                y: gridY + CGFloat(row) * cellHeight,
                width: columnWidth,
                height: cellHeight
            )
            let dayDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
            let isToday = calendar.isDate(dayDate, inSameDayAs: today)

            if isToday {
                let diameter: CGFloat = 21
                let pill = NSRect(
                    x: cell.midX - diameter / 2,
                    y: cell.midY - diameter / 2,
                    width: diameter,
                    height: diameter
                )
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

    private var previousMonthRect: NSRect {
        NSRect(x: bounds.width - 62, y: 8, width: 24, height: 28)
    }

    private var nextMonthRect: NSRect {
        NSRect(x: bounds.width - 34, y: 8, width: 24, height: 28)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let delta: Int
        if previousMonthRect.contains(point) {
            delta = -1
        } else if nextMonthRect.contains(point) {
            delta = 1
        } else {
            super.mouseDown(with: event)
            return
        }

        if let next = calendar.date(byAdding: .month, value: delta, to: displayedDate) {
            displayedDate = next
            needsDisplay = true
        }
    }

    private func reorderedWeekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        let source = formatter.veryShortStandaloneWeekdaySymbols ?? formatter.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        guard source.count == 7 else { return source }
        let offset = max(0, min(6, calendar.firstWeekday - 1))
        return Array(source[offset...]) + Array(source[..<offset])
    }

    private func drawText(
        _ text: String,
        rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
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
