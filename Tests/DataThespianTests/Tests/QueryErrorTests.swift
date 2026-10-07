//
//  QueryErrorTests.swift
//  DataThespian
//

import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct QueryErrorTests {
  #if canImport(SwiftData)
    @Test(arguments: DatabaseKind.allCases)
    internal func getThrowsItemNotFoundForMissingPredicate(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let missingID = UUID()

      let error = await #expect(throws: QueryError<Parent>.self) {
        try await database.get(for: .predicate(#Predicate<Parent> { $0.id == missingID }))
      }
      guard case .itemNotFound(.predicate) = error else {
        Issue.record("Expected itemNotFound(.predicate), got \(String(describing: error))")
        return
      }
    }

    @Test internal func descriptionNamesTheModelType() throws {
      let missingID = UUID()
      let error = QueryError<Parent>.itemNotFound(
        .predicate(#Predicate<Parent> { $0.id == missingID })
      )
      #expect(error.localizedDescription.hasPrefix("No Parent found for "))
      #expect(error.description == error.localizedDescription)
    }
  #endif
}
