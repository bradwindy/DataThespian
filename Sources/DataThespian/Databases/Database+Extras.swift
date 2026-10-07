//
//  Database+Extras.swift
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
  import Foundation
  public import SwiftData

  extension Database {
    /// Executes a database transaction asynchronously.
    ///
    /// The block's changes are saved when it returns. That save commits every pending change in
    /// the database's context, including changes other callers made before the transaction.
    ///
    /// If the block or the save throws, the block's partial changes are discarded so a later
    /// `save()` cannot commit them:
    /// - When the context had no unsaved changes on entry, it is rolled back.
    /// - Otherwise another caller's pending work is in the same context and a rollback would
    ///   silently discard it. Only the models the block inserted are removed. Property changes
    ///   and deletions the block made on existing models stay pending, so a caller that needs a
    ///   clean context after a failure must save or roll back its own work first.
    ///
    /// - Parameter block: A closure that performs database operations within the transaction.
    /// - Throws: Any errors that occur during the transaction.
    public func transaction(_ block: @Sendable @escaping (ModelContext) throws -> Void) async throws
    {
      try await self.withModelContext { context in
        let wasClean = !context.hasChanges
        let insertedBefore = Set(context.insertedModelsArray.map { $0.persistentModelID })
        do {
          try context.transaction {
            try block(context)
          }
        } catch {
          // ModelContext.transaction(block:) does not roll back. Without this the block's
          // partial changes stay pending in the long-lived context.
          if wasClean {
            context.rollback()
          } else {
            for model in context.insertedModelsArray
            where !insertedBefore.contains(model.persistentModelID) {
              context.delete(model)
            }
          }
          throw error
        }
      }
    }

    /// Deletes all models of the specified types from the database asynchronously.
    ///
    /// - Parameter types: An array of `PersistentModel.Type` instances
    /// representing the model types to delete.
    /// - Throws: Any errors that occur during the deletion process. On failure the changes are
    ///   discarded as described in ``transaction(_:)``.
    public func deleteAll(of types: [any PersistentModel.Type]) async throws {
      try await self.transaction { context in
        for type in types {
          try context.delete(model: type)
        }
      }
    }
  }
#endif
