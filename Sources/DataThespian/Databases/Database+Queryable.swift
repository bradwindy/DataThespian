//
//  Database+Queryable.swift
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

  extension Database {
    /// Saves the current state of the database.
    /// - Throws: Any errors that occur during the save operation.
    public func save() async throws {
      try await self.withModelContext { try $0.save() }
    }

    /// Inserts a new persistent model into the database.
    /// - Parameters:
    ///   - closuer: A closure that creates a new instance of the persistent model.
    ///   - closure: A closure that performs additional operations on the inserted model.
    /// - Returns: The result of the `closure` parameter.
    public func insert<PersistentModelType: PersistentModel, U: Sendable>(
      _ closuer: @Sendable @escaping () -> PersistentModelType,
      with closure: @escaping @Sendable (PersistentModelType) throws -> U
    ) async rethrows -> U {
      try await self.withModelContext {
        try $0.insert(closuer, with: closure)
      }
    }

    /// Retrieves an optional persistent model from the database.
    /// - Parameters:
    ///   - selector: A selector that specifies the model to retrieve.
    ///   - closure: A closure that performs additional operations on the retrieved model.
    /// - Returns: The result of the `closure` parameter.
    /// - Throws: Any error thrown by `closure`, and any SwiftData error from the fetch.
    public func getOptional<PersistentModelType, U: Sendable>(
      for selector: Selector<PersistentModelType>.Get,
      with closure: @escaping @Sendable (PersistentModelType?) throws -> U
    ) async throws -> U {
      try await self.withModelContext {
        try $0.getOptional(for: selector, with: closure)
      }
    }

    /// Retrieves a list of persistent models from the database.
    /// - Parameters:
    ///   - selector: A selector that specifies the models to retrieve.
    ///   - closure: A closure that performs additional operations on the retrieved models.
    /// - Returns: The result of the `closure` parameter.
    /// - Throws: Any error thrown by `closure`, and any SwiftData error from the fetch.
    public func fetch<PersistentModelType, U: Sendable>(
      for selector: Selector<PersistentModelType>.List,
      with closure: @escaping @Sendable ([PersistentModelType]) throws -> U
    ) async throws -> U {
      try await self.withModelContext {
        try $0.fetch(for: selector, with: closure)
      }
    }

    /// Inserts a model unless one matching a selector already exists, then transforms the
    /// existing or inserted model.
    ///
    /// The factory is called exactly once, on the database's context. The existence check, the
    /// insert and the transform run in one `withModelContext` call, so concurrent `insertIf`
    /// calls on the same database cannot both insert. The check sees unsaved inserts in this
    /// context. Other contexts or processes writing the same store can still race; only a
    /// unique constraint (`@Attribute(.unique)` or `#Unique`) prevents duplicates there.
    ///
    /// Build the selector from stable key values, for example
    /// `.predicate(#Predicate { $0.key == key })`. A `.model(Model(candidate))` selector never
    /// matches, because the candidate has not been inserted.
    ///
    /// - Parameters:
    ///   - model: A closure that creates the model to insert.
    ///   - selector: A closure that creates a selector from the candidate model.
    ///   - closure: A transformation closure applied to the existing or inserted model.
    /// - Returns: The transformed result.
    /// - Throws: Any error thrown by `closure`, and any SwiftData error from the existence
    ///   check. A failed check never falls through to an insert.
    public func insertIf<PersistentModelType, U: Sendable>(
      _ model: @Sendable @escaping () -> PersistentModelType,
      notExist selector: @Sendable @escaping (PersistentModelType) ->
        Selector<PersistentModelType>.Get,
      with closure: @escaping @Sendable (PersistentModelType) throws -> U
    ) async throws -> U {
      try await self.withModelContext { context in
        try context.insertIf(model, notExist: selector, with: closure)
      }
    }

    /// Inserts a model unless one matching a selector already exists.
    ///
    /// See ``insertIf(_:notExist:with:)`` for the atomicity guarantee and how to build the
    /// selector. The returned ``Model`` of a fresh insert holds a temporary identifier that
    /// stops resolving after the next save. Save, then look the model up again by its key,
    /// when you need a handle that outlives the save.
    ///
    /// - Parameters:
    ///   - model: A closure that creates the model to insert.
    ///   - selector: A closure that creates a selector from the candidate model.
    /// - Returns: Either the existing model or the newly inserted model.
    /// - Throws: Any SwiftData error from the existence check.
    @discardableResult
    public func insertIf<PersistentModelType>(
      _ model: @Sendable @escaping () -> PersistentModelType,
      notExist selector: @Sendable @escaping (PersistentModelType) ->
        Selector<PersistentModelType>.Get
    ) async throws -> Model<PersistentModelType> {
      try await self.insertIf(model, notExist: selector) { persistentModel in
        Model(persistentModel)
      }
    }

    /// Inserts a model, saves, and returns a ``Model`` holding its permanent identifier.
    ///
    /// The ``Model`` returned by ``Queryable/insert(_:)`` is built before any save, so it holds
    /// a temporary identifier that stops resolving once the context saves. This method saves
    /// and reads the identifier in the same `withModelContext` call, so the result stays valid.
    /// Saving also commits any other pending changes in the database's context.
    ///
    /// - Parameter closure: A closure that creates the model to insert.
    /// - Returns: A ``Model`` that resolves after the save, from any context on the same store.
    /// - Throws: Any error from saving. The model is then removed from the context again, and
    ///   other pending changes are left as they were.
    @discardableResult
    public func insertAndSave<PersistentModelType: PersistentModel>(
      _ closure: @Sendable @escaping () -> PersistentModelType
    ) async throws -> Model<PersistentModelType> {
      try await self.withModelContext { context in
        let persistentModel = closure()
        context.insert(persistentModel)
        do {
          try context.save()
        } catch {
          context.delete(persistentModel)
          throw error
        }
        return Model(persistentModel)
      }
    }

    /// Deletes a persistent model from the database.
    /// - Parameter selector: A selector that specifies the model to delete.
    /// - Throws: Any errors that occur during the delete operation.
    public func delete<PersistentModelType>(_ selector: Selector<PersistentModelType>.Delete)
      async throws
    {
      try await self.withModelContext {
        try $0.delete(selector)
      }
    }
  }
#endif
