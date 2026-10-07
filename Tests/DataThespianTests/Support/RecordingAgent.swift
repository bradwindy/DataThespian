//
//  RecordingAgent.swift
//  DataThespian
//

#if canImport(SwiftData)
  import Foundation
  import os

  @testable import DataThespian

  /// A `DataAgent` that records what it is sent, synchronously, behind a lock.
  internal final class RecordingAgent: DataAgent {
    private struct State: Sendable {
      var updates: [any DatabaseChangeSet] = []
      var finishCount = 0
      var completed: (@Sendable () -> Void)?
    }

    internal let agentID = UUID()
    private let state = OSAllocatedUnfairLock(initialState: State())

    internal var updateCount: Int { state.withLock { $0.updates.count } }
    internal var finishCount: Int { state.withLock { $0.finishCount } }

    internal func onUpdate(_ update: any DatabaseChangeSet) {
      state.withLock { $0.updates.append(update) }
    }

    internal func onCompleted(_ closure: @escaping @Sendable () -> Void) {
      state.withLock { $0.completed = closure }
    }

    internal func finish() async {
      let completed = state.withLock { state in
        state.finishCount += 1
        let completed = state.completed
        state.completed = nil
        return completed
      }
      completed?()
    }
  }

  /// Hands out a fixed agent under a fixed id.
  internal struct RecordingAgentRegister: AgentRegister {
    internal let id: String
    private let recordingAgent: RecordingAgent

    internal init(id: String, agent: RecordingAgent) {
      self.id = id
      self.recordingAgent = agent
    }

    internal func agent() async -> RecordingAgent {
      recordingAgent
    }
  }
#endif
