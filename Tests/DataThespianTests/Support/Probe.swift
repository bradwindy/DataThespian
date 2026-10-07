//
//  Probe.swift
//  DataThespian
//

#if canImport(SwiftData)
  import Foundation
  import SwiftData

  /// A model with a computed, non-persisted property.
  ///
  /// A predicate on ``doubled`` cannot be translated to the store, so `ModelContext.fetch`
  /// throws. Tests use it to check that SwiftData errors reach the caller.
  @Model
  internal final class Probe {
    internal var value: Int

    internal var doubled: Int { value * 2 }

    internal init(value: Int) {
      self.value = value
    }
  }
#endif
