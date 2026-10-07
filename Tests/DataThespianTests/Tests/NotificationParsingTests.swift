//
//  NotificationParsingTests.swift
//  DataThespian
//

import Foundation
import Testing
import os

@testable import DataThespian

#if canImport(SwiftData) && canImport(CoreData)
  import CoreData
  import SwiftData

  /// Covers how a save notification becomes a `DatabaseChangeSet`.
  @Suite(.enabled(if: swiftDataIsAvailable()))
  internal struct NotificationParsingTests {
    @Test internal func missingUserInfoGivesNoChanges() {
      let notification = Notification(
        name: .NSManagedObjectContextDidSaveObjectIDs, object: nil, userInfo: nil
      )

      let update = NotificationDataUpdate(notification)

      #expect(update.isEmpty)
      #expect(ManagedObjectIDChanges(notification).isEmpty)
    }

    @Test internal func managedObjectIDsReadsOnlyObjectIDSets() {
      let notification = Notification(
        name: .NSManagedObjectContextDidSaveObjectIDs,
        object: nil,
        userInfo: [
          NSInsertedObjectIDsKey: Set<NSManagedObjectID>(),
          NSUpdatedObjectIDsKey: "not a set",
        ]
      )

      #expect(notification.managedObjectIDs(key: NSInsertedObjectIDsKey) == [])
      #expect(notification.managedObjectIDs(key: NSUpdatedObjectIDsKey) == nil)
      #expect(notification.managedObjectIDs(key: NSDeletedObjectIDsKey) == nil)
    }

    /// A real SwiftData save, parsed the way `DataMonitor` parses it.
    @Test internal func realSaveReportsTheInsertedIdentifier() throws {
      let captured = OSAllocatedUnfairLock<[ManagedObjectIDChanges]>(initialState: [])
      let observer = NotificationCenter.default.addObserver(
        forName: .NSManagedObjectContextDidSaveObjectIDs, object: nil, queue: nil
      ) { notification in
        let changes = ManagedObjectIDChanges(notification)
        captured.withLock { $0.append(changes) }
      }
      defer { NotificationCenter.default.removeObserver(observer) }

      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let context = ModelContext(container)
      let parent = Parent(id: UUID())
      context.insert(parent)
      try context.save()
      let savedID = parent.persistentModelID
      let expected = ManagedObjectMetadata(entityName: "Parent", persistentIdentifier: savedID)

      // The notification is process-wide, so pick ours out from saves in other suites.
      let updates = captured.withLock { $0 }.map(NotificationDataUpdate.init)
      let ours = updates.first { $0.inserted.contains(expected) }
      #expect(ours != nil)
      #expect(ours?.deleted.isEmpty == true)
      #expect(ours?.updated.isEmpty == true)
    }
  }
#endif
