//
//  CollectionDifference.swift
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
  /// Represents the difference between a persistent model and its associated data.
  public struct CollectionDifference<PersistentModelType: PersistentModel, DataType: Sendable>:
    Sendable
  {
    /// The items that need to be inserted.
    public let inserts: [DataType]
    /// The models that need to be deleted.
    public let modelsToDelete: [Model<PersistentModelType>]
    /// The items that need to be updated.
    public let updates: [DataType]

    /// Initializes a `CollectionDifference` instance with
    /// the specified inserts, models to delete, and updates.
    /// - Parameters:
    ///   - inserts: The items that need to be inserted.
    ///   - modelsToDelete: The models that need to be deleted.
    ///   - updates: The items that need to be updated.
    public init(
      inserts: [DataType], modelsToDelete: [Model<PersistentModelType>], updates: [DataType]
    ) {
      self.inserts = inserts
      self.modelsToDelete = modelsToDelete
      self.updates = updates
    }
  }

  extension CollectionDifference {
    /// The delete selectors for the models that need to be deleted.
    public var deleteSelectors: [DataThespian.Selector<PersistentModelType>.Delete] {
      self.modelsToDelete.map {
        .model($0)
      }
    }

    /// Initializes a `CollectionDifference` instance by comparing the persistent models and data.
    ///
    /// Duplicate identifiers never trap:
    /// - For persistent models, the first model with an identifier is kept and every later
    ///   model with the same identifier goes into ``modelsToDelete``, so synchronising the
    ///   difference collapses the duplicate rows.
    /// - For data, the last item with an identifier wins, at the position where that identifier
    ///   first appears.
    ///
    /// ``inserts`` and ``updates`` follow the order of `data`, and ``modelsToDelete`` follows
    /// the order of `persistentModels`.
    ///
    /// - Parameters:
    ///   - persistentModels: The persistent models to compare.
    ///   - data: The data to compare.
    ///   - persistentModelKeyPath: The key path to the unique identifier in the persistent models.
    ///   - dataKeyPath: The key path to the unique identifier in the data.
    public init<ID: Hashable>(
      persistentModels: [PersistentModelType]?,
      data: [DataType]?,
      persistentModelKeyPath: KeyPath<PersistentModelType, ID>,
      dataKeyPath: KeyPath<DataType, ID>
    ) {
      var entryMap: [ID: PersistentModelType] = [:]
      var entryOrder: [ID] = []
      var duplicateEntries: [PersistentModelType] = []
      for model in persistentModels ?? [] {
        let id = model[keyPath: persistentModelKeyPath]
        if entryMap[id] == nil {
          entryMap[id] = model
          entryOrder.append(id)
        } else {
          duplicateEntries.append(model)
        }
      }

      var dataMap: [ID: DataType] = [:]
      var dataOrder: [ID] = []
      for item in data ?? [] {
        let id = item[keyPath: dataKeyPath]
        if dataMap.updateValue(item, forKey: id) == nil {
          dataOrder.append(id)
        }
      }

      let inserts = dataOrder.filter { entryMap[$0] == nil }.compactMap { dataMap[$0] }
      let updates = dataOrder.filter { entryMap[$0] != nil }.compactMap { dataMap[$0] }
      let entriesToDelete =
        entryOrder.filter { dataMap[$0] == nil }.compactMap { entryMap[$0] } + duplicateEntries

      self.init(
        inserts: inserts,
        modelsToDelete: entriesToDelete.map(Model.init),
        updates: updates
      )
    }
  }
#endif
