//
//  DatabaseChangePublicist.swift
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

#if canImport(Combine) && canImport(SwiftData)
  public import Combine

  private struct NeverDatabaseMonitor: DatabaseMonitoring {
    /// Ignores the registration, so nothing is ever published.
    func register(_: any AgentRegister, force _: Bool) {}
  }

  /// The monitor behind the SwiftUI environment default, used when no publicist was injected.
  private struct UnconfiguredDatabaseMonitor: DatabaseMonitoring, Loggable {
    static var loggingCategory: ThespianLogging.Category { .application }

    /// Logs a warning and ignores the registration.
    func register(_ registration: any AgentRegister, force _: Bool) {
      Self.logger.warning(
        // swiftlint:disable:next line_length
        "databaseChangePublicist used for \(registration.id, privacy: .public) without being set in the environment; no changes will be published."
      )
    }
  }

  /// A struct that publishes database change events.
  public struct DatabaseChangePublicist: Sendable {
    private let dbWatcher: any DatabaseMonitoring

    /// Initializes a new `DatabaseChangePublicist` instance.
    /// - Parameter dbWatcher: The database monitoring instance to use. Defaults to `DataMonitor.shared`.
    public init(dbWatcher: any DatabaseMonitoring = DataMonitor.shared) {
      self.dbWatcher = dbWatcher
    }

    /// Creates a `DatabaseChangePublicist` that never publishes any changes.
    ///
    /// Subscribing to it is safe: it never asserts and never emits.
    public static func never() -> DatabaseChangePublicist {
      self.init(dbWatcher: NeverDatabaseMonitor())
    }

    /// The SwiftUI environment default: publishes nothing and logs a warning when used,
    /// so a missing injection shows up in the log instead of crashing a preview.
    internal static func unconfigured() -> DatabaseChangePublicist {
      self.init(dbWatcher: UnconfiguredDatabaseMonitor())
    }

    /// Publishes database change events for the specified ID.
    ///
    /// Calling this again with the same ID replaces the earlier publisher, which then completes.
    /// Like any `PassthroughSubject`, the publisher drops change sets sent before you subscribe.
    /// When the publisher and all its subscriptions are released, the registration is removed
    /// on the next change.
    ///
    /// - Parameter id: The ID of the entity to watch for changes.
    /// - Returns: A publisher that emits `DatabaseChangeSet` values
    /// whenever the database changes for the specified ID.
    @Sendable public func callAsFunction(id: String) -> some Publisher<any DatabaseChangeSet, Never>
    {
      let subject = PassthroughSubject<any DatabaseChangeSet, Never>()
      dbWatcher.register(PublishingRegister(id: id, subject: subject), force: true)
      return subject
    }
  }
#endif
