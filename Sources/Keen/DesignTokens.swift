import AppKit

@MainActor
enum KeenDesign {
    static let canvas = NSColor(calibratedRed: 0.953, green: 0.941, blue: 0.910, alpha: 1)
    static let canvasDeep = NSColor(calibratedRed: 0.925, green: 0.908, blue: 0.875, alpha: 1)
    static let ink = NSColor(calibratedRed: 0.11, green: 0.105, blue: 0.098, alpha: 1)
    static let inkMuted = NSColor(calibratedRed: 0.48, green: 0.46, blue: 0.43, alpha: 1)
    static let inkFaint = NSColor(calibratedRed: 0.68, green: 0.66, blue: 0.62, alpha: 1)
    static let line = NSColor(calibratedRed: 0.86, green: 0.84, blue: 0.80, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.77, green: 0.36, blue: 0.15, alpha: 1)
    static let accentSoft = NSColor(calibratedRed: 0.77, green: 0.36, blue: 0.15, alpha: 0.12)
    static let now = NSColor(calibratedRed: 0.83, green: 0.63, blue: 0.13, alpha: 1)
    static let scheduled = NSColor(calibratedRed: 0.42, green: 0.56, blue: 0.72, alpha: 1)
    static let focus = NSColor(calibratedRed: 0.42, green: 0.36, blue: 0.58, alpha: 1)
    static let takeover = NSColor(calibratedRed: 0.72, green: 0.29, blue: 0.24, alpha: 1)
    static let overlayDim = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.07, alpha: 0.28)
    static let takeoverDim = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.05, alpha: 0.45)

    static let pad: CGFloat = 24
    static let padTight: CGFloat = 14
    static let railWidth: CGFloat = 60
    static let navItemWidth: CGFloat = 44
    static let navItemHeight: CGFloat = 48
    static let railCorner: CGFloat = 16
    static let contentGap: CGFloat = 14

    static let cardRadius: CGFloat = 16
    static let bubbleTint = NSColor.white.withAlphaComponent(0.28)
    static let bubbleSelected = NSColor.white.withAlphaComponent(0.42)
    static let bubbleAccent = NSColor(calibratedRed: 0.77, green: 0.36, blue: 0.15, alpha: 0.18)
    static let fieldTint = NSColor.white.withAlphaComponent(0.24)

    static let inspectorWidth: CGFloat = 288

    static func display(_ size: CGFloat = 32) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .bold)
    }

    static func title(_ size: CGFloat = 20) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func section(_ size: CGFloat = 10) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .bold)
    }

    static func body(_ size: CGFloat = 13) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .regular)
    }

    static func caption(_ size: CGFloat = 11) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .medium)
    }

    static func mono(_ size: CGFloat = 15) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
    }

    static func label(_ field: NSTextField, color: NSColor = ink) {
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = false
        field.isSelectable = false
        field.textColor = color
    }

    static func labelStyle(_ field: NSTextField) { label(field) }

    static func blur(material: NSVisualEffectView.Material = .hudWindow) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    static func hairline() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = line.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([v.heightAnchor.constraint(equalToConstant: 1)])
        return v
    }

    static func levelColor(_ level: InterventionLevel) -> NSColor {
        switch level {
        case .gentle: now
        case .focus: focus
        case .takeover: takeover
        }
    }
}
