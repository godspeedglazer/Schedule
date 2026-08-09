import AppKit

@MainActor
final class TimerQuickStartMenuView: NSView {
    private let minutesField = NSTextField()
    private let stepper = NSStepper()
    private let onStart: (Int) -> Void

    init(onStart: @escaping (Int) -> Void) {
        self.onStart = onStart
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 98))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 250).isActive = true
        heightAnchor.constraint(equalToConstant: 98).isActive = true

        let heading = NSTextField(labelWithString: "Start timer")
        heading.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let presets = NSSegmentedControl(labels: ["5m", "25m", "50m"], trackingMode: .momentary, target: self, action: #selector(presetTapped(_:)))
        presets.segmentStyle = .rounded
        presets.translatesAutoresizingMaskIntoConstraints = false

        minutesField.integerValue = 25
        minutesField.alignment = .right
        minutesField.formatter = Self.numberFormatter()
        minutesField.translatesAutoresizingMaskIntoConstraints = false
        minutesField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        minutesField.target = self
        minutesField.action = #selector(fieldCommitted)

        stepper.minValue = 1
        stepper.maxValue = 720
        stepper.increment = 1
        stepper.integerValue = 25
        stepper.target = self
        stepper.action = #selector(stepperChanged)

        let suffix = NSTextField(labelWithString: "min")
        suffix.textColor = .secondaryLabelColor
        let start = NSButton(title: "Start", target: self, action: #selector(startCustom))
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let custom = NSStackView(views: [minutesField, stepper, suffix, spacer, start])
        custom.orientation = .horizontal
        custom.alignment = .centerY
        custom.spacing = 6

        let stack = NSStackView(views: [heading, presets, custom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -9),
            presets.widthAnchor.constraint(equalTo: stack.widthAnchor),
            custom.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    @objc private func presetTapped(_ sender: NSSegmentedControl) {
        let values = [5, 25, 50]
        let index = sender.selectedSegment
        guard values.indices.contains(index) else { return }
        begin(values[index])
    }

    @objc private func stepperChanged() {
        minutesField.integerValue = stepper.integerValue
    }

    @objc private func fieldCommitted() {
        let value = clampedMinutes(minutesField.integerValue)
        minutesField.integerValue = value
        stepper.integerValue = value
    }

    @objc private func startCustom() {
        begin(minutesField.integerValue)
    }

    private func begin(_ rawMinutes: Int) {
        let minutes = clampedMinutes(rawMinutes)
        minutesField.integerValue = minutes
        stepper.integerValue = minutes
        onStart(minutes)
    }

    private func clampedMinutes(_ value: Int) -> Int { min(720, max(1, value)) }

    private static func numberFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 720
        formatter.allowsFloats = false
        return formatter
    }
}
