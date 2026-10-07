import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct ModelActorTests {
  @Test internal func testGetOptionalWithModel() async throws {
    #if canImport(SwiftData)
      let database = try TestingDatabase(for: Parent.self, Child.self)
      let parentID = UUID()

      // Insert a parent
      try await database.withModelContext { context in
        context.insert(Parent(id: parentID))
        try context.save()
      }

      // Test getOptional with model selector
      let parentModels: [Model<Parent>]
      let parentIDs: [UUID]
      parentModels = try await database.fetch(for: .all(Parent.self))

      let selectors = parentModels.map { Selector<Parent>.Get.model($0) }
      #expect(parentModels.count == 1)

      parentIDs = try await database.fetch(for: selectors) { $0.id }

      #expect(parentIDs.count == 1)
      #expect(parentIDs.first == parentID)
    #endif
  }

  @Test internal func testGetOptionalWithPredicate() async throws {
    #if canImport(SwiftData)
      let database = try TestingDatabase(for: Parent.self, Child.self)
      let parentID = UUID()

      // Insert a parent
      try await database.withModelContext { context in
        context.insert(Parent(id: parentID))
        try context.save()
      }

      // Test getOptional with predicate selector
      let predicate = #Predicate<Parent> { $0.id == parentID }
      let result = try await database.getOptional(
        for: .predicate(predicate)
      ) { $0?.id }

      #expect(result == parentID)
    #endif
  }

  @Test internal func testFetchWithDescriptor() async throws {
    #if canImport(SwiftData)
      let database = try TestingDatabase(for: Parent.self, Child.self)
      let parentIDs = [UUID(), UUID(), UUID()]

      // Insert multiple parents
      try await database.withModelContext { context in
        for id in parentIDs {
          context.insert(Parent(id: id))
        }
        try context.save()
      }

      // Create a descriptor
      let descriptor = FetchDescriptor<Parent>()

      // Test fetch with descriptor
      let fetchedModels = try await database.fetch(for: .descriptor(descriptor))

      #expect(fetchedModels.count == parentIDs.count)

      let allModels = try await database.fetch(for: .all(Parent.self))
      #expect(allModels.count == 3)
    #endif
  }
}
