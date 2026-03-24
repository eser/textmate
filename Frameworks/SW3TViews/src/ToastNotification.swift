// SW³ TextFellow — Toast Notification System
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Non-modal toast notifications for background events.
// Shows in bottom-right corner of the key window, auto-dismisses after 3 seconds.
//
// Usage from ObjC: [[SW3TToastManager shared] showToast:@"LSP server started" category:@"LSP"];
// Usage from Swift: ToastManager.shared.show("Format applied", category: "FORMAT")

import AppKit

// MARK: - Toast View

private class ToastView: NSView {
    private let label: NSTextField
    private let iconView: NSImageView
    private var dismissTimer: Timer?

    init(message: String, category: String) {
        self.label = NSTextField(labelWithString: message)
        self.iconView = NSImageView()
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor

        // Subtle shadow
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow?.shadowBlurRadius = 8
        shadow?.shadowOffset = NSSize(width: 0, height: -2)

        // Icon based on category
        let symbolName: String
        switch category.uppercased() {
        case "LSP":      symbolName = "server.rack"
        case "FORMAT":   symbolName = "text.alignleft"
        case "GIT":      symbolName = "arrow.triangle.branch"
        case "METAL":    symbolName = "gpu"
        case "ERROR":    symbolName = "exclamationmark.triangle"
        case "AI":       symbolName = "sparkles"
        default:         symbolName = "info.circle"
        }
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: category)
        iconView.contentTintColor = .secondaryLabelColor

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail

        iconView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func dismiss(animated: Bool = true) {
        dismissTimer?.invalidate()
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                self.animator().alphaValue = 0
            }, completionHandler: {
                self.removeFromSuperview()
            })
        } else {
            removeFromSuperview()
        }
    }
}

// MARK: - Toast Manager

@objc(SW3TToastManager)
public class ToastManager: NSObject, @unchecked Sendable {

    @objc public static let shared = ToastManager()

    private var activeToasts: [ToastView] = []
    private let maxVisible = 3
    private let toastWidth: CGFloat = 280
    private let bottomMargin: CGFloat = 40
    private let rightMargin: CGFloat = 16
    private let spacing: CGFloat = 8

    /// Show a toast notification in the key window.
    @objc public func show(_ message: String, category: String = "INFO") {
        DispatchQueue.main.async { [weak self] in
            self?.showOnMainThread(message, category: category)
        }
    }

    /// ObjC-compatible method name.
    @objc(showToast:category:)
    public func showToast(_ message: String, category: String) {
        show(message, category: category)
    }

    private func showOnMainThread(_ message: String, category: String) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView else { return }

        // Remove oldest if at max
        while activeToasts.count >= maxVisible {
            activeToasts.first?.dismiss(animated: false)
            activeToasts.removeFirst()
        }

        let toast = ToastView(message: message, category: category)
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.alphaValue = 0
        contentView.addSubview(toast)

        // Position: bottom-right, stacked above existing toasts
        let yOffset = bottomMargin + activeToasts.reduce(0) { sum, existing in
            sum + existing.frame.height + spacing
        }

        NSLayoutConstraint.activate([
            toast.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -rightMargin),
            toast.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -yOffset),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: toastWidth),
        ])

        activeToasts.append(toast)

        // Animate in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            toast.animator().alphaValue = 1
        }

        // Auto-dismiss after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self, weak toast] in
            guard let toast, let self else { return }
            toast.dismiss()
            self.activeToasts.removeAll { $0 === toast }
        }

        // Log to debug logger
        DebugLogger.shared.log("TOAST", "\(category): \(message)")
    }
}
