//
//  FetchErrorTests.swift
//  DataThespian
//

import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

/// SwiftData errors from a fetch must come back through `try`.
///
/// `getOptional(for:with:)` and `fetch(for:with:)` used to be `rethrows`, so a call with a
/// non-throwing closure was typed as unable to throw while the fetch inside could still fail.
@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct FetchErrorTests {
  #if canImport(SwiftData)
    private static func makeContainer() throws -> ModelContainer {
      try ModelContainer(
        for: Probe.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
      )
    }

    private static let untranslatable = #Predicate<Probe> { $0.doubled == 4 }

    private static func seed(_ database: any Database) async throws {
      _ = await database.insert { Probe(value: 2) }
      try await database.save()
    }

    private static func expectFetchErrors(from database: any Database) async throws {
      try await seed(database)

      await #expect(throws: (any Error).self) {
        try await database.fetch(for: .descriptor(predicate: Self.untranslatable)) { $0.count }
      }
      await #expect(throws: (any Error).self) {
        try await database.fetch(for: .descriptor(predicate: Self.untranslatable))
      }
      await #expect(throws: (any Error).self) {
        try await database.getOptional(for: .predicate(Self.untranslatable)) { $0 != nil }
      }
      await #expect(throws: (any Error).self) {
        try await database.getOptional(for: .predicate(Self.untranslatable))
      }
      await #expect(throws: (any Error).self) {
        try await database.fetch(for: [.predicate(Self.untranslatable)]) { $0.value }
      }
    }
  #endif

  @Test internal func backgroundDatabaseFetchErrorsPropagate() async throws {
    #if canImport(SwiftData)
      let database = BackgroundDatabase(modelContainer: try Self.makeContainer())
      try await Self.expectFetchErrors(from: database)
    #endif
  }

  @Test internal func modelActorDatabaseFetchErrorsPropagate() async throws {
    #if canImport(SwiftData)
      let database = ModelActorDatabase(modelContainer: try Self.makeContainer())
      try await Self.expectFetchErrors(from: database)
    #endif
  }

  @Test internal func modelActorFetchModelsDoesNotSwallowErrors() async throws {
    #if canImport(SwiftData)
      // Statically typed as the @ModelActor database: this used to bind to an overload that
      // logged the error and returned [].
      let database = try TestingDatabase(for: Probe.self)
      try await Self.seed(database)
      await #expect(throws: (any Error).self) {
        try await database.fetch(for: .descriptor(predicate: Self.untranslatable))
      }
    #endif
  }
}
