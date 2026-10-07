//
//  PublishingAgent.swift
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
  @preconcurrency import Combine
  import Foundation

  /// An actor that manages the publishing of database change sets.
  ///
  /// Change sets are queued in order and sent to the subject on the main actor.
  /// The agent holds the subject weakly: once the caller and every subscriber have
  /// released it, the agent finishes on the next change and unregisters itself.
  internal actor PublishingAgent: DataAgent, Loggable {
    /// Holds the subject weakly. It is only read on the main actor.
    private final class WeakSubject: @unchecked Sendable {
      weak var subject: PassthroughSubject<any DatabaseChangeSet, Never>?

      init(_ subject: PassthroughSubject<any DatabaseChangeSet, Never>) {
        self.subject = subject
      }
    }

    /// The logging category for the `PublishingAgent`.
    internal static var loggingCategory: ThespianLogging.Category { .application }

    /// The unique identifier for the agent.
    internal let agentID = UUID()

    /// The identifier for the agent.
    private let id: String

    /// Change sets waiting to be sent to the subject, in arrival order.
    private let updates: AsyncStream<any DatabaseChangeSet>.Continuation

    /// The completion closure.
    private var completed: (@Sendable () -> Void)?

    /// Whether ``finish()`` has run.
    private var isFinished = false

    /// Initializes a new `PublishingAgent` instance.
    /// - Parameters:
    ///   - id: The identifier for the agent.
    ///   - subject: The subject that publishes the database change sets.
    internal init(id: String, subject: PassthroughSubject<any DatabaseChangeSet, Never>) {
      self.id = id
      let (stream, updates) = AsyncStream.makeStream(of: (any DatabaseChangeSet).self)
      self.updates = updates
      let box = WeakSubject(subject)
      Task { @MainActor [weak self] in
        for await update in stream {
          guard let subject = box.subject else {
            break
          }
          subject.send(update)
        }
        box.subject?.send(completion: .finished)
        await self?.finish()
      }
    }

    deinit {
      updates.finish()
    }

    /// Handles an update to the database.
    /// - Parameter update: The database change set.
    nonisolated internal func onUpdate(_ update: any DatabaseChangeSet) {
      updates.yield(update)
    }

    /// Sets the completion closure.
    /// - Parameter closure: The completion closure.
    nonisolated internal func onCompleted(_ closure: @escaping @Sendable () -> Void) {
      Task { await self.setCompleted(closure) }
    }

    /// Sets the completion closure, or calls it at once if the agent has already finished.
    /// - Parameter closure: The completion closure.
    internal func setCompleted(_ closure: @escaping @Sendable () -> Void) {
      guard !isFinished else {
        closure()
        return
      }
      Self.logger.debug("SetCompleted \(self.id, privacy: .public) \(self.agentID, privacy: .public)")
      completed = closure
    }

    /// Finishes the agent: the subject completes once queued change sets are sent,
    /// and the completion closure runs. Calling it again has no effect.
    internal func finish() {
      guard !isFinished else {
        return
      }
      isFinished = true
      Self.logger.debug("Finishing \(self.id, privacy: .public) \(self.agentID, privacy: .public)")
      updates.finish()
      let completed = self.completed
      self.completed = nil
      completed?()
    }
  }
#endif
