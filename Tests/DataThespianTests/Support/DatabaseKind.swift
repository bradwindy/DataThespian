//
//  DatabaseKind.swift
//  DataThespian
//

#if canImport(SwiftData)
  @testable import DataThespian
  import SwiftData

  /// The `Database` implementations a parameterised test runs against.
  ///
  /// `TestingDatabase` is a `@ModelActor`; `BackgroundDatabase` is the type most apps use and
  /// reaches every `Queryable` call through `any Database`.
  internal enum DatabaseKind: String, CaseIterable, Sendable, CustomStringConvertible {
    case testingDatabase
    case modelActorDatabase
    case backgroundDatabase

    internal var description: String { rawValue }

    internal static func makeContainer(
      for types: any PersistentModel.Type...
    ) throws -> ModelContainer {
      try ModelContainer(
        for: Schema(types),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
      )
    }

    internal func makeDatabase(modelContainer: ModelContainer) -> any Database {
      switch self {
      case .testingDatabase:
        TestingDatabase(modelContainer: modelContainer)
      case .modelActorDatabase:
        ModelActorDatabase(modelContainer: modelContainer)
      case .backgroundDatabase:
        BackgroundDatabase(modelContainer: modelContainer)
      }
    }
  }
#endif
