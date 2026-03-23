// SW³ TextFellow — Cursor Animator
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import CoreGraphics

/// Smooth cursor animation with position lerp and easing.
///
/// When the cursor moves (keystroke, click, arrow key), instead of
/// instantly teleporting, it smoothly slides to the new position
/// over ~60ms using an ease-out curve. This makes the editor feel alive.
///
/// ```
///  Cursor Movement Timeline:
///
///  Frame 0     Frame 1     Frame 2     Frame 3     Frame 4
///  ├───────────┼───────────┼───────────┼───────────┤
///  ■           ·■·         ··■·        ···■        ····■
///  (old pos)   (lerp 25%)  (lerp 55%)  (lerp 82%)  (target)
///
///  Easing: ease-out cubic = 1 - (1-t)³
/// ```
public final class CursorAnimator {
    /// Current interpolated cursor position.
    public private(set) var currentPosition: CGPoint

    /// Target position the cursor is animating toward.
    public private(set) var targetPosition: CGPoint

    /// Animation duration in seconds.
    public var animationDuration: TimeInterval = 0.06 // 60ms

    /// Blink rate: full cycle time in seconds.
    public var blinkCycleTime: TimeInterval = 1.0

    private var animationStartTime: TimeInterval = 0
    private var animationStartPosition: CGPoint = .zero
    private var isAnimating: Bool = false

    public init(position: CGPoint = .zero) {
        self.currentPosition = position
        self.targetPosition = position
    }

    /// Set a new target position. Starts smooth animation from current.
    public func moveTo(_ target: CGPoint, at time: TimeInterval) {
        guard target != targetPosition else { return }
        animationStartPosition = currentPosition
        targetPosition = target
        animationStartTime = time
        isAnimating = true
    }

    /// Update the animation state for the current frame.
    /// Returns the cursor alpha (for blink) and updated position.
    public func update(at time: TimeInterval) -> (position: CGPoint, alpha: CGFloat) {
        // Position animation
        if isAnimating {
            let elapsed = time - animationStartTime
            let t = min(elapsed / animationDuration, 1.0)
            let eased = easeOutCubic(t)

            currentPosition = CGPoint(
                x: animationStartPosition.x + (targetPosition.x - animationStartPosition.x) * eased,
                y: animationStartPosition.y + (targetPosition.y - animationStartPosition.y) * eased
            )

            if t >= 1.0 {
                currentPosition = targetPosition
                isAnimating = false
            }
        }

        // Blink animation (cursor visible for 60% of cycle, smooth fade)
        let blinkPhase = time.truncatingRemainder(dividingBy: blinkCycleTime) / blinkCycleTime
        let alpha: CGFloat
        if isAnimating {
            alpha = 1.0 // Don't blink during movement
        } else if blinkPhase < 0.5 {
            alpha = 1.0 // Visible phase
        } else {
            // Smooth fade out/in
            let fadePhase = (blinkPhase - 0.5) * 2.0 // 0..1
            alpha = CGFloat(1.0 - easeInOutCubic(fadePhase))
        }

        return (currentPosition, alpha)
    }

    // MARK: - Easing functions

    private func easeOutCubic(_ t: TimeInterval) -> CGFloat {
        CGFloat(1.0 - pow(1.0 - t, 3))
    }

    private func easeInOutCubic(_ t: TimeInterval) -> CGFloat {
        if t < 0.5 {
            return CGFloat(4 * t * t * t)
        } else {
            return CGFloat(1 - pow(-2 * t + 2, 3) / 2)
        }
    }
}
