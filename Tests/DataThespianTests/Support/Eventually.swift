//
//  Eventually.swift
//  DataThespian
//

/// Polls `condition` until it holds or `timeout` passes, and returns its last value.
///
/// Used for work the library finishes on the main actor after the call under test returns.
internal func eventually(
  timeout: Duration = .seconds(2),
  _ condition: @Sendable () async -> Bool
) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if await condition() {
      return true
    }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return await condition()
}
