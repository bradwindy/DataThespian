import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct SelectorExtensionTests {
  @Test internal func testSelectorDeleteAllType() async throws {
    #if canImport(SwiftData)
      // Test that the .all(Type) extension method returns .all
      let selector = DataThespian.Selector<Parent>.Delete.all(Parent.self)

      // Use pattern matching to verify the case
      switch selector {
      case .all:
        // Test passes - selector is the .all case
        break
      default:
        // Test fails - selector is not the .all case
        Issue.record("Expected .all case but got a different case")
      }
    #endif
  }

  #if canImport(SwiftData)
    /// Used to end with `#expect(true)` on an empty store, so it could not fail.
    @Test(arguments: DatabaseKind.allCases)
    internal func testSelectorDeleteAllTypeUsage(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      try await database.withModelContext { context in
        for _ in 0..<3 {
          context.insert(Parent(id: UUID()))
        }
        try context.save()
      }

      try await database.delete(.all(Parent.self))
      try await database.save()

      let remaining = try ModelContext(container).fetchCount(FetchDescriptor<Parent>())
      #expect(remaining == 0)
    }
  #endif
}
