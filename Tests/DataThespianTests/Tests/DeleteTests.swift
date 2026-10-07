import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct DeleteTests {
  #if canImport(SwiftData)
    @Test(arguments: DatabaseKind.allCases)
    internal func testDeleteAll(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)

      try await database.withModelContext { context in
        for _ in 0..<5 {
          context.insert(Parent(id: UUID()))
        }
        try context.save()
      }

      let initialCount = try await database.fetch(for: .all(Parent.self)) { $0.count }
      #expect(initialCount == 5)

      try await database.delete(.all(Parent.self))

      let parentCount = try await database.fetch(for: .all(Parent.self)) { $0.count }
      #expect(parentCount == 0)
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func testDeleteAllWithMultipleEntityTypes(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)

      try await database.withModelContext { context in
        for _ in 0..<3 {
          context.insert(Parent(id: UUID()))
        }
        for _ in 0..<4 {
          context.insert(Child(id: UUID()))
        }
        try context.save()
      }

      let initialParentCount = try await database.fetch(for: .all(Parent.self)) { $0.count }
      let initialChildCount = try await database.fetch(for: .all(Child.self)) { $0.count }
      #expect(initialParentCount == 3)
      #expect(initialChildCount == 4)

      try await database.delete(.all(Parent.self))

      // Only parents are deleted, not children.
      let parentCount = try await database.fetch(for: .all(Parent.self)) { $0.count }
      let childCount = try await database.fetch(for: .all(Child.self)) { $0.count }
      #expect(parentCount == 0)
      #expect(childCount == 4)
    }

    /// Used to promise a check of the remaining children and then assert only the parent
    /// count. It now checks, against the store, that the bulk delete applied the default
    /// nullify rule: every child survives with no parent.
    @Test(arguments: DatabaseKind.allCases)
    internal func testDeleteAllWithRelationships(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)

      try await database.withModelContext { context in
        for _ in 0..<3 {
          let parent = Parent(id: UUID())
          context.insert(parent)
          for _ in 0..<2 {
            let child = Child(id: UUID())
            context.insert(child)
            // One side only; SwiftData maintains the inverse.
            child.parent = parent
          }
        }
        try context.save()
      }

      let childCounts = try await database.fetch(for: .all(Parent.self)) { parents in
        parents.map { $0.children?.count ?? 0 }
      }
      #expect(childCounts == [2, 2, 2])

      try await database.delete(.all(Parent.self))
      try await database.save()

      // A fresh context, so stale registered objects cannot mask what reached the store.
      let check = ModelContext(container)
      let children = try check.fetch(FetchDescriptor<Child>())
      #expect(try check.fetchCount(FetchDescriptor<Parent>()) == 0)
      #expect(children.count == 6)
      #expect(children.allSatisfy { $0.parent == nil })
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func testDeleteModelsDeletesEachModel(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let keptID = UUID()
      try await database.withModelContext { context in
        context.insert(Parent(id: keptID))
        for _ in 0..<3 {
          context.insert(Parent(id: UUID()))
        }
        try context.save()
      }

      let doomed = try await database.fetch(
        for: .descriptor(predicate: #Predicate<Parent> { $0.id != keptID })
      )
      #expect(doomed.count == 3)
      try await database.deleteModels(doomed)
      try await database.save()

      let remaining = try ModelContext(container).fetch(FetchDescriptor<Parent>()).map(\.id)
      #expect(remaining == [keptID])
    }
  #endif
}
