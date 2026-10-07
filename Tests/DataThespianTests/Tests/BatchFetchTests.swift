//
//  BatchFetchTests.swift
//  DataThespian
//

import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct BatchFetchTests {
  #if canImport(SwiftData)
    /// `fetch(for: [Selector.Get])` returns results in selector order and drops misses.
    /// It used to collect from a task group in completion order.
    @Test(arguments: DatabaseKind.allCases)
    internal func batchFetchPreservesSelectorOrder(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let parentIDs = (0..<30).map { _ in UUID() }
      try await database.withModelContext { context in
        for id in parentIDs {
          context.insert(Parent(id: id))
        }
        try context.save()
      }

      let modelsByID = try await database.fetch(for: .all(Parent.self)) { parents in
        Dictionary(uniqueKeysWithValues: parents.map { ($0.id, Model($0)) })
      }

      for _ in 0..<5 {
        let order = parentIDs.shuffled()
        var selectors = try order.map { id in
          DataThespian.Selector<Parent>.Get.model(try #require(modelsByID[id]))
        }
        let missingID = UUID()
        selectors.insert(
          .predicate(#Predicate<Parent> { $0.id == missingID }),
          at: selectors.count / 2
        )

        let fetchedIDs = try await database.fetch(for: selectors) { $0.id }
        #expect(fetchedIDs == order)
      }
    }

    @Test internal func modelContextBatchFetchPreservesSelectorOrder() async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let context = ModelContext(container)
      let parents = (0..<10).map { _ in Parent(id: UUID()) }
      for parent in parents {
        context.insert(parent)
      }
      try context.save()

      let order = parents.shuffled()
      let selectors: [DataThespian.Selector<Parent>.Get] = order.map { .model(Model($0)) }
      let fetched = try context.fetch(for: selectors)
      #expect(fetched.map(\.id) == order.map(\.id))
    }
  #endif
}
