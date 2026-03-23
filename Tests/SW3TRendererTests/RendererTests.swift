import Testing
@testable import SW3TRenderer
import CoreGraphics
import simd

// MARK: - Cursor Animator Tests

@Test func cursorAnimatorStartsAtInitialPosition() {
    let animator = CursorAnimator(position: CGPoint(x: 100, y: 200))
    let (pos, alpha) = animator.update(at: 0)
    #expect(pos.x == 100)
    #expect(pos.y == 200)
    #expect(alpha > 0) // visible
}

@Test func cursorAnimatorLerpsToTarget() {
    let animator = CursorAnimator(position: CGPoint(x: 0, y: 0))
    animator.moveTo(CGPoint(x: 100, y: 0), at: 0)

    // At t=0, should still be near start
    let (pos0, _) = animator.update(at: 0.001)
    #expect(pos0.x < 50) // hasn't reached target yet

    // After animation duration, should be at target
    let (posEnd, _) = animator.update(at: 0.1) // well past 60ms
    #expect(posEnd.x == 100)
    #expect(posEnd.y == 0)
}

@Test func cursorAnimatorDoesNotBlinkDuringMovement() {
    let animator = CursorAnimator(position: .zero)
    animator.moveTo(CGPoint(x: 100, y: 0), at: 0)

    let (_, alpha) = animator.update(at: 0.01) // mid-animation
    #expect(alpha == 1.0) // fully visible during movement
}

@Test func projectionMatrixDimensions() {
    let matrix = TextEditorRenderer.orthographicProjection(width: 800, height: 600)
    // Top-left should map to (-1, 1) in clip space
    let topLeft = matrix * SIMD4<Float>(0, 0, 0, 1)
    #expect(abs(topLeft.x - (-1.0)) < 0.01)
    #expect(abs(topLeft.y - 1.0) < 0.01)
}
