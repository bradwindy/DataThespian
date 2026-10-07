//
//  UniqueKeyPathTests.swift
//  DataThespian
//

import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct UniqueKeyPathTests {
  #if canImport(SwiftData)
    /// `predicate(equals:)` used to be `fatalError("Not implemented yet.")`.
    @Test internal func predicateMatchesEqualValuesOnly() throws {
      let predicate = KeyedItem.Keys.primary.predicate(equals: "alpha")
      #expect(try predicate.evaluate(KeyedItem(name: "alpha")))
      #expect(try !predicate.evaluate(KeyedItem(name: "beta")))
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func uniqueSelectorFetchesThroughSwiftData(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: KeyedItem.self)
      let database = kind.makeDatabase(modelContainer: container)
      try await database.withModelContext { context in
        context.insert(KeyedItem(name: "alpha"))
        context.insert(KeyedItem(name: "beta"))
        try context.save()
      }

      let name = try await database.getOptional(
        for: .unique(KeyedItem.Keys.primary, equals: "beta")
      ) { $0?.name }
      #expect(name == "beta")

      let missing = try await database.getOptional(
        for: .unique(KeyedItem.Keys.primary, equals: "gamma")
      ) { $0 != nil }
      #expect(missing == false)
    }
  #endif
}
