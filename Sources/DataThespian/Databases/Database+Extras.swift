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
    /// The block's changes are saved when it returns. If the block or the save throws, the
    /// context is rolled back so the partial changes cannot be committed by a later `save()`.
    /// The rollback discards every unsaved change in the database's context, including changes
    /// made before the transaction started, not only the block's own.
    ///
    /// - Parameter block: A closure that performs database operations within the transaction.
    /// - Throws: Any errors that occur during the transaction.
    public func transaction(_ block: @Sendable @escaping (ModelContext) throws -> Void) async throws
    {
      try await self.withModelContext { context in
        do {
          try context.transaction {
            try block(context)
          }
        } catch {
          // ModelContext.transaction(block:) saves but never rolls back. Without this the
          // block's partial changes stay pending in the long-lived context.
          context.rollback()
          throw error
        }
      }
    }

    /// Deletes all models of the specified types from the database asynchronously.
    ///
    /// - Parameter types: An array of `PersistentModel.Type` instances
    /// representing the model types to delete.
    /// - Throws: Any errors that occur during the deletion process. On failure the context is
    ///   rolled back, as described in ``transaction(_:)``.
    public func deleteAll(of types: [any PersistentModel.Type]) async throws {
      try await self.transaction { context in
        for type in types {
          try context.delete(model: type)
        }
      }
    }
  }
#endif
