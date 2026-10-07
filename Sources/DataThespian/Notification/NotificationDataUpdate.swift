//
//  NotificationDataUpdate.swift
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

#if canImport(CoreData) && canImport(SwiftData)
  import CoreData
  import Foundation

  /// The raw object IDs from one `NSManagedObjectContextDidSaveObjectIDs` notification.
  ///
  /// Reading these is cheap, so the notification observer does only this on the saving
  /// thread. Converting them to `PersistentIdentifier`s happens later, on the monitor,
  /// and only when an agent is registered.
  ///
  /// `NSManagedObjectID` is immutable and documented as safe to pass between threads,
  /// which is why this is `@unchecked Sendable`.
  internal struct ManagedObjectIDChanges: @unchecked Sendable {
    internal let inserted: Set<NSManagedObjectID>
    internal let deleted: Set<NSManagedObjectID>
    internal let updated: Set<NSManagedObjectID>

    internal var isEmpty: Bool { inserted.isEmpty && deleted.isEmpty && updated.isEmpty }

    internal init(
      inserted: Set<NSManagedObjectID>, deleted: Set<NSManagedObjectID>, updated: Set<NSManagedObjectID>
    ) {
      self.inserted = inserted
      self.deleted = deleted
      self.updated = updated
    }

    internal init(_ notification: Notification) {
      self.init(
        inserted: notification.managedObjectIDs(key: NSInsertedObjectIDsKey) ?? [],
        deleted: notification.managedObjectIDs(key: NSDeletedObjectIDsKey) ?? [],
        updated: notification.managedObjectIDs(key: NSUpdatedObjectIDsKey) ?? []
      )
    }
  }

  /// Represents a set of changes to managed objects in a Core Data store.
  internal struct NotificationDataUpdate: DatabaseChangeSet, Sendable, Loggable {
    internal static var loggingCategory: ThespianLogging.Category { .data }

    /// The set of managed objects that were inserted.
    internal let inserted: Set<ManagedObjectMetadata>

    /// The set of managed objects that were deleted.
    internal let deleted: Set<ManagedObjectMetadata>

    /// The set of managed objects that were updated.
    internal let updated: Set<ManagedObjectMetadata>

    /// Converts raw object IDs, sharing one encoder and decoder across the whole batch.
    ///
    /// An ID that cannot be converted is logged and dropped.
    internal init(_ changes: ManagedObjectIDChanges) {
      let encoder = JSONEncoder()
      let decoder = JSONDecoder()
      self.inserted = Self.metadata(for: changes.inserted, encoder: encoder, decoder: decoder)
      self.deleted = Self.metadata(for: changes.deleted, encoder: encoder, decoder: decoder)
      self.updated = Self.metadata(for: changes.updated, encoder: encoder, decoder: decoder)
    }

    /// Initializes a `NotificationDataUpdate` instance from a Notification object.
    ///
    /// - Parameter notification: The notification that triggered the data update.
    internal init(_ notification: Notification) {
      self.init(ManagedObjectIDChanges(notification))
    }

    private static func metadata(
      for objectIDs: Set<NSManagedObjectID>, encoder: JSONEncoder, decoder: JSONDecoder
    ) -> Set<ManagedObjectMetadata> {
      var metadata = Set<ManagedObjectMetadata>(minimumCapacity: objectIDs.count)
      for objectID in objectIDs {
        do {
          let item = try ManagedObjectMetadata(
            objectID: objectID, encoder: encoder, decoder: decoder
          )
          metadata.insert(item)
        } catch {
          Self.logger.warning(
            "Dropping an object ID with no PersistentIdentifier: \(String(describing: error), privacy: .public)"
          )
        }
      }
      return metadata
    }
  }
#endif
