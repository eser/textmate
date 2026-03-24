// SW³ TextFellow — Smooth Cursor Animation
// SPDX-License-Identifier: GPL-3.0-or-later
//
// 80ms ease-out cursor interpolation for Metal rendering.
// Skips animation if keystrokes arrive <50ms apart (rapid typing).
// Provides the animated cursor position each frame.

import AppKit

/// Animates cursor position with 80ms ease-out interpolation.
/// Feed it target positions from OakTextView; it returns the
/// interpolated position for Metal rendering each frame.
@objc(SW3TCursorAnimator)
public class CursorAnimator: NSObject {
    private var currentX: CGFloat = 0
    private var currentY: CGFloat = 0
    private var targetX: CGFloat = 0
    private var targetY: CGFloat = 0
    private var animationStart: CFTimeInterval = 0
    private var lastTargetChange: CFTimeInterval = 0

    /// Animation duration in seconds.
    private let duration: CFTimeInterval = 0.08 // 80ms

    /// Minimum time between keystrokes before animation engages.
    /// Below this threshold, cursor teleports instantly.
    private let debounceThreshold: CFTimeInterval = 0.05 // 50ms

    /// Set new target cursor position. Call when cursor moves.
    @objc public func setTarget(x: CGFloat, y: CGFloat) {
        let now = CACurrentMediaTime()
        let timeSinceLastChange = now - lastTargetChange

        if timeSinceLastChange < debounceThreshold {
            // Rapid typing — teleport instantly
            currentX = x
            currentY = y
            targetX = x
            targetY = y
            animationStart = 0
        } else {
            // Start smooth animation
            targetX = x
            targetY = y
            animationStart = now
        }

        lastTargetChange = now
    }

    /// Get interpolated cursor position for the current frame.
    /// Call this each render frame.
    @objc public func animatedPosition() -> NSPoint {
        guard animationStart > 0 else {
            return NSPoint(x: currentX, y: currentY)
        }

        let elapsed = CACurrentMediaTime() - animationStart
        let progress = min(elapsed / duration, 1.0)

        // Ease-out: decelerating from start
        let eased = 1.0 - pow(1.0 - progress, 3.0) // cubic ease-out

        let x = currentX + (targetX - currentX) * CGFloat(eased)
        let y = currentY + (targetY - currentY) * CGFloat(eased)

        if progress >= 1.0 {
            // Animation complete
            currentX = targetX
            currentY = targetY
            animationStart = 0
            return NSPoint(x: targetX, y: targetY)
        }

        return NSPoint(x: x, y: y)
    }

    /// Whether an animation is currently in progress.
    @objc public var isAnimating: Bool {
        animationStart > 0 && CACurrentMediaTime() - animationStart < duration
    }
}
