//
//  DataMonitor.swift
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

#if canImport(Combine) && canImport(SwiftData) && canImport(CoreData)

  import CoreData
  import Foundation
  import SwiftData
  import os

  /// Monitors the database for changes and notifies registered agents of those changes.
  ///
  /// Registrations and saved changes go through one first-in, first-out queue, so
  /// agents see changes in the order they were saved, and a change saved after
  /// ``register(_:force:)`` or ``begin(with:)`` returns is delivered to that registration.
  public actor DataMonitor: DatabaseMonitoring, Loggable {
    /// Work for the monitor, handled strictly one item at a time.
    private enum Event: Sendable {
      case register(any AgentRegister, force: Bool)
      case update(ManagedObjectIDChanges)
      case barrier(CheckedContinuation<Void, Never>)

      /// Releases anything waiting on an event that will never be handled.
      fileprivate func discard() {
        if case .barrier(let continuation) = self {
          continuation.resume()
        }
      }
    }

    /// The logging category for this class.
    public static var loggingCategory: ThespianLogging.Category { .data }

    /// The shared instance of the `DataMonitor`.
    public static let shared = DataMonitor()

    private let events: AsyncStream<Event>.Continuation
    private let isObserving: OSAllocatedUnfairLock<Bool>
    private let notificationCenter: NotificationCenter
    private let observer: any NSObjectProtocol
    private let registrations = RegistrationCollection()

    /// Creates a monitor.
    ///
    /// - Parameters:
    ///   - notificationCenter: Where save notifications are observed. Tests pass their own.
    ///   - allowEmptyChanges: Whether a save with no object IDs is delivered.
    internal init(notificationCenter: NotificationCenter = .default, allowEmptyChanges: Bool = false) {
      let (stream, events) = AsyncStream.makeStream(of: Event.self)
      let isObserving = OSAllocatedUnfairLock(initialState: false)
      self.events = events
      self.isObserving = isObserving
      self.notificationCenter = notificationCenter
      self.observer = notificationCenter.addObserver(
        forName: .NSManagedObjectContextDidSaveObjectIDs,
        object: nil,
        queue: nil,
        using: Self.observerBlock(
          events: events, isObserving: isObserving, allowEmptyChanges: allowEmptyChanges
        )
      )
      Self.logger.debug("Creating DatabaseMonitor")
      Task { [weak self] in
        for await event in stream {
          if let self {
            await self.handle(event)
          } else {
            event.discard()
          }
        }
      }
    }

    deinit {
      events.finish()
    }

    /// The observer runs synchronously on the saving thread, so it only reads the raw
    /// object IDs and queues them. It never converts them or touches the actor.
    private static func observerBlock(
      events: AsyncStream<Event>.Continuation,
      isObserving: OSAllocatedUnfairLock<Bool>,
      allowEmptyChanges: Bool
    ) -> @Sendable (Notification) -> Void {
      { notification in
        guard isObserving.withLock({ $0 }) else {
          return
        }
        let changes = ManagedObjectIDChanges(notification)
        guard allowEmptyChanges || !changes.isEmpty else {
          return
        }
        events.yield(.update(changes))
      }
    }

    /// Registers the given agent with the database monitor.
    ///
    /// The registration is queued before this returns, so it is in place before any
    /// change saved afterwards is delivered.
    ///
    /// - Parameters:
    ///   - registration: The agent to register.
    ///   - force: Whether to force the registration,
    ///    even if a registration with the same ID already exists.
    ///    A forced registration replaces and finishes the existing agent.
    public nonisolated func register(_ registration: any AgentRegister, force: Bool) {
      events.yield(.register(registration, force: force))
    }

    /// Begins monitoring the database with the given agent registrations.
    ///
    /// Changes saved after this returns are delivered; changes saved before it are not.
    ///
    /// - Parameter builders: The agent registrations to monitor.
    public nonisolated func begin(with builders: [any AgentRegister]) {
      for builder in builders {
        events.yield(.register(builder, force: false))
      }
      isObserving.withLock { $0 = true }
    }

    private func handle(_ event: Event) async {
      switch event {
      case .register(let registration, let force):
        await registrations.append(withID: registration.id, force: force, agent: registration.agent)

      case .update(let changes):
        await notify(changes)

      case .barrier(let continuation):
        continuation.resume()
      }
    }

    private func notify(_ changes: ManagedObjectIDChanges) async {
      let hasRegistrations = await !registrations.isEmpty
      guard hasRegistrations else {
        return
      }
      let update = NotificationDataUpdate(changes)
      guard !update.isEmpty || changes.isEmpty else {
        // Every ID failed to convert, so there is nothing to tell the agents.
        return
      }
      Self.logger.debug("Notifying of Update")
      await registrations.onUpdate(update)
    }

    /// Returns once every registration and change queued before this call has been handled.
    internal nonisolated func flush() async {
      await withCheckedContinuation { continuation in
        if case .terminated = events.yield(.barrier(continuation)) {
          continuation.resume()
        }
      }
    }

    /// Stops observing saves for good. Used by tests that create their own monitor.
    internal func stopObserving() {
      isObserving.withLock { $0 = false }
      notificationCenter.removeObserver(observer)
    }

    /// The number of registered agents.
    internal func registrationCount() async -> Int {
      await registrations.count
    }

    /// The `agentID` of the agent registered under `id`, if any.
    internal func registeredAgentID(forID id: String) async -> UUID? {
      await registrations.agentID(forID: id)
    }
  }

#endif
