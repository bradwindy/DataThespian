import Foundation
import Testing

@testable import DataThespian

#if canImport(Combine) && canImport(SwiftData) && canImport(CoreData)
  import Combine
  import CoreData
  import SwiftData

  /// Every test builds its own `DataMonitor` on a private `NotificationCenter`, so saves from
  /// suites running in parallel cannot reach it and nothing leaks into `DataMonitor.shared`.
  @Suite(.enabled(if: swiftDataIsAvailable()))
  internal struct DataMonitorTests {
    private static func postSave(on center: NotificationCenter) {
      center.post(name: .NSManagedObjectContextDidSaveObjectIDs, object: nil, userInfo: [:])
    }

    @Test internal func testSharedInstance() async {
      let monitor1 = DataMonitor.shared
      let monitor2 = DataMonitor.shared

      #expect(ObjectIdentifier(monitor1) == ObjectIdentifier(monitor2))
    }

    /// One save notification must reach the agent exactly once.
    @Test internal func oneSaveDeliversOneUpdate() async {
      let center = NotificationCenter()
      let monitor = DataMonitor(notificationCenter: center, allowEmptyChanges: true)
      let agent = RecordingAgent()
      monitor.begin(with: [RecordingAgentRegister(id: "one", agent: agent)])

      Self.postSave(on: center)
      await monitor.flush()

      #expect(agent.updateCount == 1)
      await monitor.stopObserving()
    }

    /// `begin(with:)` used to install its registrations through separate unstructured Tasks,
    /// so a save made straight after it returned was usually missed.
    @Test internal func saveStraightAfterBeginIsDelivered() async {
      let center = NotificationCenter()
      let monitor = DataMonitor(notificationCenter: center, allowEmptyChanges: true)
      let agent = RecordingAgent()

      monitor.begin(with: [RecordingAgentRegister(id: "early", agent: agent)])
      for _ in 0..<5 {
        Self.postSave(on: center)
      }
      await monitor.flush()

      #expect(agent.updateCount == 5)
      await monitor.stopObserving()
    }

    @Test internal func savesBeforeBeginAreNotDelivered() async {
      let center = NotificationCenter()
      let monitor = DataMonitor(notificationCenter: center, allowEmptyChanges: true)
      let agent = RecordingAgent()
      monitor.register(RecordingAgentRegister(id: "before", agent: agent), force: false)

      Self.postSave(on: center)
      await monitor.flush()

      #expect(agent.updateCount == 0)
      await monitor.stopObserving()
    }

    @Test internal func emptySavesAreSkippedByDefault() async {
      let center = NotificationCenter()
      let monitor = DataMonitor(notificationCenter: center)
      let agent = RecordingAgent()
      monitor.begin(with: [RecordingAgentRegister(id: "empty", agent: agent)])

      Self.postSave(on: center)
      await monitor.flush()

      #expect(agent.updateCount == 0)
      await monitor.stopObserving()
    }

    /// Two forced registrations for one id used to race through unordered Tasks and a
    /// reentrant `append`, so either could win and the loser was never finished.
    @Test internal func forcedRegistrationsApplyInCallOrder() async {
      let monitor = DataMonitor(notificationCenter: NotificationCenter())
      let first = RecordingAgent()
      let second = RecordingAgent()

      monitor.register(RecordingAgentRegister(id: "same", agent: first), force: true)
      monitor.register(RecordingAgentRegister(id: "same", agent: second), force: true)
      await monitor.flush()

      #expect(await monitor.registrationCount() == 1)
      #expect(await monitor.registeredAgentID(forID: "same") == second.agentID)
      #expect(first.finishCount == 1)
      #expect(second.finishCount == 0)
      await monitor.stopObserving()
    }

    @Test internal func unforcedRegistrationKeepsTheFirstAgent() async {
      let monitor = DataMonitor(notificationCenter: NotificationCenter())
      let first = RecordingAgent()
      let second = RecordingAgent()

      monitor.register(RecordingAgentRegister(id: "same", agent: first), force: false)
      monitor.register(RecordingAgentRegister(id: "same", agent: second), force: false)
      await monitor.flush()

      #expect(await monitor.registeredAgentID(forID: "same") == first.agentID)
      #expect(first.finishCount == 0)
      await monitor.stopObserving()
    }

    /// A finished agent removes its own registration.
    @Test internal func finishedAgentIsUnregistered() async {
      let monitor = DataMonitor(notificationCenter: NotificationCenter())
      let agent = RecordingAgent()
      monitor.register(RecordingAgentRegister(id: "done", agent: agent), force: false)
      await monitor.flush()
      #expect(await monitor.registrationCount() == 1)

      await agent.finish()

      #expect(await eventually { await monitor.registrationCount() == 0 })
      await monitor.stopObserving()
    }

    /// A forced registration through `RegistrationCollection` directly, racing two appends.
    @Test internal func concurrentAppendsLeaveOneAgentAndFinishTheOther() async {
      let collection = RegistrationCollection()
      let first = RecordingAgent()
      let second = RecordingAgent()

      async let firstAppend: Void = collection.append(withID: "x", force: false) {
        try? await Task.sleep(for: .milliseconds(50))
        return first
      }
      async let secondAppend: Void = collection.append(withID: "x", force: false) {
        try? await Task.sleep(for: .milliseconds(50))
        return second
      }
      _ = await (firstAppend, secondAppend)

      #expect(await collection.count == 1)
      #expect(first.finishCount + second.finishCount == 1)
      let winner = await collection.agentID(forID: "x")
      #expect(winner == first.agentID || winner == second.agentID)
    }
  }
#endif
