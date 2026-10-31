extension DuoModel {
  /// DeviceHub's hinge spring (ModelScene's `_hingeSpring`): a critically damped SmoothDamp with a
  /// smooth time of 0.25 s, settled within 0.05° and 0.5°/s.
  ///
  /// DeviceHub's model follows its commanded angle through this spring, stepped every frame with
  /// the frame time clamped to 0...0.05 s. SpatialSim drives the angle from the hand and can skip
  /// it; the debug viewer's preset buttons use it.
  public struct HingeSpring: Sendable {
    public var value = 180.0
    public var target = 180.0
    public var velocity = 0.0
    public var smoothTime = 0.25
    public var epsilon = 0.05
    public var settleVelocity = 0.5

    /// At rest, flat.
    public init() {}

    public var isSettled: Bool {
      abs(value - target) < epsilon && abs(velocity) < settleVelocity
    }

    public mutating func step(_ deltaTime: Double) {
      guard deltaTime.isFinite else {
        return
      }
      let dt = min(max(deltaTime, 0), 0.05)
      guard dt > 0 else {
        return
      }
      let omega = 2 / max(smoothTime, 1e-4)
      let x = omega * dt
      let decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
      let change = value - target
      let temp = (velocity + omega * change) * dt
      velocity = (velocity - omega * temp) * decay
      var next = target + (change + temp) * decay
      // Never past the target: SmoothDamp's overshoot guard.
      if (target - value > 0) == (next > target) {
        next = target
        velocity = 0
      }
      value = next
      if isSettled {
        value = target
        velocity = 0
      }
    }
  }
}
