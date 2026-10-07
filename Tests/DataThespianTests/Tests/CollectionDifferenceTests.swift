//
//  CollectionDifferenceTests.swift
//  DataThespian
//

import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct CollectionDifferenceTests {
  #if canImport(SwiftData)
    private typealias Difference = DataThespian.CollectionDifference<Parent, ParentData>

    private static func makeContext() throws -> ModelContext {
      ModelContext(try DatabaseKind.makeContainer(for: Parent.self, Child.self))
    }

    private static func insertParents(_ ids: [UUID], into context: ModelContext) -> [Parent] {
      ids.map { id in
        let parent = Parent(id: id)
        context.insert(parent)
        return parent
      }
    }

    @Test internal func partitionsInInputOrder() throws {
      let context = try Self.makeContext()
      let ids = (0..<6).map { _ in UUID() }
      let parents = Self.insertParents([ids[0], ids[1], ids[2]], into: context)
      let data = [ids[3], ids[2], ids[4], ids[1]].map { ParentData(id: $0) }

      let difference = Difference(
        persistentModels: parents,
        data: data,
        persistentModelKeyPath: \.id,
        dataKeyPath: \.id
      )

      #expect(difference.inserts.map(\.id) == [ids[3], ids[4]])
      #expect(difference.updates.map(\.id) == [ids[2], ids[1]])
      #expect(
        difference.modelsToDelete.map(\.persistentIdentifier) == [parents[0].persistentModelID]
      )
    }

    @Test internal func nilInputsProduceAnEmptyDifference() {
      let difference = Difference(
        persistentModels: nil,
        data: nil,
        persistentModelKeyPath: \.id,
        dataKeyPath: \.id
      )
      #expect(difference.inserts.isEmpty)
      #expect(difference.updates.isEmpty)
      #expect(difference.modelsToDelete.isEmpty)
    }

    /// Duplicate keys used to trap in `Dictionary(uniqueKeysWithValues:)`.
    @Test internal func duplicatePersistentKeysAreQueuedForDeletion() throws {
      let context = try Self.makeContext()
      let id = UUID()
      let parents = Self.insertParents([id, id], into: context)

      let difference = Difference(
        persistentModels: parents,
        data: [ParentData(id: id)],
        persistentModelKeyPath: \.id,
        dataKeyPath: \.id
      )

      #expect(difference.updates.map(\.id) == [id])
      #expect(difference.inserts.isEmpty)
      #expect(
        difference.modelsToDelete.map(\.persistentIdentifier) == [parents[1].persistentModelID]
      )
    }

    @Test internal func duplicateDataKeysKeepTheLastItem() {
      let id = UUID()
      let otherID = UUID()
      let difference = Difference(
        persistentModels: [],
        data: [
          ParentData(id: id, name: "first"),
          ParentData(id: otherID, name: "other"),
          ParentData(id: id, name: "second"),
        ],
        persistentModelKeyPath: \.id,
        dataKeyPath: \.id
      )

      #expect(
        difference.inserts == [
          ParentData(id: id, name: "second"),
          ParentData(id: otherID, name: "other"),
        ]
      )
      #expect(difference.updates.isEmpty)
      #expect(difference.modelsToDelete.isEmpty)
    }
  #endif
}
