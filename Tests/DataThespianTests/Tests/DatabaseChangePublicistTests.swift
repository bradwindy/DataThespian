//
//  DatabaseChangePublicistTests.swift
//  DataThespian
//

import Testing

@testable import DataThespian

#if canImport(Combine) && canImport(SwiftData)
  import Combine

  @Suite(.enabled(if: swiftDataIsAvailable()))
  internal struct DatabaseChangePublicistTests {
    /// `.never()` is documented as a no-op but used to assert, and it was also the SwiftUI
    /// environment default, so previews and tests crashed in debug builds.
    @Test internal func neverAndUnconfiguredPublicistsAreNoOps() {
      for publicist in [DatabaseChangePublicist.never(), .unconfigured()] {
        let cancellable = publicist(id: "nothing").sink { _ in
          Issue.record("A no-op publicist emitted a change")
        }
        cancellable.cancel()
      }
    }
  }
#endif
