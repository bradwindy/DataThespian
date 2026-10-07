//
//  CollectionSynchronizer.swift
//  DataThespian
//
//  Created by Leo Dion.
//  Copyright © 2025 BrightDigit.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the “Software”), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

#if canImport(SwiftData)
  public import SwiftData
  /// A protocol that defines the synchronization behavior between a persistent model and data.
  public protocol CollectionSynchronizer {
    /// The type of the persistent model.
    associatedtype PersistentModelType: PersistentModel

    /// The type of the data.
    associatedtype DataType: Sendable

    /// The type of the identifier.
    associatedtype ID: Hashable

    /// The key path to the identifier in the data.
    static var dataKey: KeyPath<DataType, ID> { get }

    /// The key path to the identifier in the persistent model.
    static var persistentModelKey: KeyPath<PersistentModelType, ID> { get }

    /// Retrieves a selector for fetching the persistent model from the data.
    ///
    /// - Parameter data: The data to use for constructing the selector.
    /// - Returns: A selector for fetching the persistent model.
    static func getSelector(from data: DataType) -> DataThespian.Selector<PersistentModelType>.Get

    /// Creates a persistent model from the provided data.
    ///
    /// - Parameter data: The data to create the persistent model from.
    /// - Returns: The created persistent model.
    static func persistentModel(from data: DataType) -> PersistentModelType

    /// Synchronizes the persistent model with the provided data.
    ///
    /// - Parameters:
    ///   - persistentModel: The persistent model to synchronize.
    ///   - data: The data to synchronize the persistent model with.
    /// - Throws: Any errors that occur during the synchronization process.
    static func synchronize(_ persistentModel: PersistentModelType, with data: DataType) throws
  }

  extension CollectionSynchronizer {
    /// Synchronizes the difference between a collection of persistent models and a collection of data.
    ///
    /// Every delete and update target is resolved before the context is changed, so a missing
    /// update target throws without leaving deletes or inserts behind. A delete target that no
    /// longer exists is skipped. Update targets come from
    /// ``CollectionDifference/modelsToUpdate`` when it is set, and otherwise from
    /// ``getSelector(from:)``. Updates are applied in the order of
    /// ``CollectionDifference/updates``, then the inserts are made.
    ///
    /// If `synchronize(_:with:)` throws and the context had no unsaved changes on entry, the
    /// context is rolled back, so nothing from this call can be committed by a later save. If it
    /// already had unsaved changes, they are kept, and so are the changes this call made before
    /// the error; roll back or discard them yourself. On success the caller must save.
    ///
    /// - Parameters:
    ///   - difference: The difference between the persistent models and the data.
    ///   - modelContext: The model context to use for the synchronization.
    /// - Returns: The list of persistent models that were inserted.
    /// - Throws: `QueryError.itemNotFound` when an update target cannot be found,
    ///   ``SynchronizationError/keyMismatch(expected:found:)`` when `getSelector(from:)` finds a
    ///   model with a different key, and any error from `synchronize(_:with:)`.
    public static func synchronizeDifference(
      _ difference: CollectionDifference<PersistentModelType, DataType>,
      using modelContext: ModelContext
    ) throws -> [PersistentModelType] {
      let wasClean = !modelContext.hasChanges

      let entriesToDelete = try difference.modelsToDelete.compactMap { model in
        try modelContext.getOptional(model)
      }
      let entriesToUpdate = try Self.updateTargets(for: difference, using: modelContext)

      do {
        for entry in entriesToDelete {
          modelContext.delete(entry)
        }

        for (entry, data) in entriesToUpdate {
          try Self.synchronize(entry, with: data)
        }

        return difference.inserts.map { data in
          let persistentModel = Self.persistentModel(from: data)
          modelContext.insert(persistentModel)
          return persistentModel
        }
      } catch {
        if wasClean {
          modelContext.rollback()
        }
        throw error
      }
    }

    private static func updateTargets(
      for difference: CollectionDifference<PersistentModelType, DataType>,
      using modelContext: ModelContext
    ) throws -> [(PersistentModelType, DataType)] {
      if let models = difference.modelsToUpdate, models.count == difference.updates.count {
        return try zip(models, difference.updates).map { pair in
          let entry = try modelContext.get(pair.0)
          return (entry, pair.1)
        }
      }

      return try difference.updates.map { data in
        let selector = Self.getSelector(from: data)
        guard let entry = try modelContext.getOptional(for: selector) else {
          throw QueryError<PersistentModelType>.itemNotFound(selector)
        }
        let expected = data[keyPath: Self.dataKey]
        let found = entry[keyPath: Self.persistentModelKey]
        guard expected == found else {
          throw SynchronizationError.keyMismatch(
            expected: String(describing: expected),
            found: String(describing: found)
          )
        }
        return (entry, data)
      }
    }
  }
#endif
