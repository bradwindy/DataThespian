//
//  ModelActorDatabaseTests.swift
//  DataThespian
//

import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

/// A `ModelActorDatabase` runs its work on the queue of the context it creates, so creating it
/// on the main actor can put every query on the main thread. These are the supported ways to
/// create a database from main-actor code.
@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct ModelActorDatabaseTests {
  #if canImport(SwiftData)
    @MainActor
    @Test internal func makeInBackgroundFromMainActorRunsOffMain() async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)

      let database = await ModelActorDatabase.makeInBackground(modelContainer: container)

      let ranOnMain = await database.withModelContext { _ in Thread.isMainThread }
      #expect(ranOnMain == false)
      _ = await database.insert { Parent(id: UUID()) }
      try await database.save()
      #expect(try ModelContext(container).fetchCount(FetchDescriptor<Parent>()) == 1)
    }

    @MainActor
    @Test internal func makeInBackgroundWithExecutorFromMainActorRunsOffMain() async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)

      let database = await ModelActorDatabase.makeInBackground(
        modelContainer: container,
        modelExecutor: { DefaultSerialModelExecutor(modelContext: ModelContext($0)) }
      )

      let ranOnMain = await database.withModelContext { _ in Thread.isMainThread }
      #expect(ranOnMain == false)
    }

    @MainActor
    @Test internal func backgroundDatabaseFromMainActorRunsOffMain() async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)

      let database = BackgroundDatabase(modelContainer: container)

      let ranOnMain = await database.withModelContext { _ in Thread.isMainThread }
      #expect(ranOnMain == false)
    }
  #endif
}
