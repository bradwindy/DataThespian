//
//  PublishingAgentTests.swift
//  DataThespian
//

import Foundation
import Testing
import os

@testable import DataThespian

#if canImport(Combine) && canImport(SwiftData) && canImport(CoreData)
  import Combine
  import CoreData

  @Suite(.enabled(if: swiftDataIsAvailable()))
  internal struct PublishingAgentTests {
    /// A change set that carries its position, so delivery order can be checked.
    private struct NumberedChange: DatabaseChangeSet {
      let number: Int
      var inserted: Set<ManagedObjectMetadata> { [] }
      var deleted: Set<ManagedObjectMetadata> { [] }
      var updated: Set<ManagedObjectMetadata> { [] }
    }

    /// What a subscriber has seen.
    private final class Received: Sendable {
      private let state = OSAllocatedUnfairLock<(numbers: [Int], isFinished: Bool)>(
        initialState: ([], false)
      )

      var numbers: [Int] { state.withLock { $0.numbers } }
      var isFinished: Bool { state.withLock { $0.isFinished } }
      var count: Int { state.withLock { $0.numbers.count } }

      func record(_ update: any DatabaseChangeSet) {
        let number = (update as? NumberedChange)?.number ?? -1
        state.withLock { $0.numbers.append(number) }
      }

      func recordFinished() {
        state.withLock { $0.isFinished = true }
      }

      func subscribe(to publisher: some Publisher<any DatabaseChangeSet, Never>) -> AnyCancellable {
        publisher.sink { _ in self.recordFinished() } receiveValue: { self.record($0) }
      }
    }

    /// Each update used to take its own unstructured Task to the main actor, so a burst of
    /// changes could reach subscribers in a different order from the one they were saved in.
    @Test internal func updatesArriveInOrder() async {
      let subject = PassthroughSubject<any DatabaseChangeSet, Never>()
      let agent = PublishingAgent(id: "order", subject: subject)
      let received = Received()
      let cancellable = received.subscribe(to: subject)

      for number in 0..<200 {
        agent.onUpdate(NumberedChange(number: number))
      }

      #expect(await eventually { received.count == 200 })
      #expect(received.numbers == Array(0..<200))
      withExtendedLifetime((cancellable, subject, agent)) {}
    }

    /// A replaced publisher used to stay open forever, so its subscribers hung silently.
    @Test internal func replacedPublisherCompletes() async {
      let monitor = DataMonitor(notificationCenter: NotificationCenter())
      let publicist = DatabaseChangePublicist(dbWatcher: monitor)
      let received = Received()
      let first = publicist(id: "items")
      let cancellable = received.subscribe(to: first)
      await monitor.flush()

      let second = publicist(id: "items")
      await monitor.flush()

      #expect(await eventually { received.isFinished })
      #expect(await monitor.registrationCount() == 1)
      withExtendedLifetime((cancellable, second)) {}
      await monitor.stopObserving()
    }

    /// Nothing used to notice that every subscriber had gone, so each id stayed registered,
    /// and kept dispatching every save to the main actor, for the life of the process.
    @Test internal func releasedPublisherUnregistersOnTheNextChange() async {
      let center = NotificationCenter()
      let monitor = DataMonitor(notificationCenter: center, allowEmptyChanges: true)
      let publicist = DatabaseChangePublicist(dbWatcher: monitor)
      monitor.begin(with: [])
      do {
        let received = Received()
        let cancellable = received.subscribe(to: publicist(id: "gone"))
        await monitor.flush()
        #expect(await monitor.registrationCount() == 1)
        cancellable.cancel()
      }

      center.post(name: .NSManagedObjectContextDidSaveObjectIDs, object: nil, userInfo: [:])
      await monitor.flush()

      #expect(await eventually { await monitor.registrationCount() == 0 })
      await monitor.stopObserving()
    }

    @Test internal func subscribedPublisherReceivesSaves() async {
      let center = NotificationCenter()
      let monitor = DataMonitor(notificationCenter: center, allowEmptyChanges: true)
      let publicist = DatabaseChangePublicist(dbWatcher: monitor)
      monitor.begin(with: [])
      let received = Received()
      let publisher = publicist(id: "live")
      let cancellable = received.subscribe(to: publisher)

      center.post(name: .NSManagedObjectContextDidSaveObjectIDs, object: nil, userInfo: [:])
      await monitor.flush()

      #expect(await eventually { received.count == 1 })
      #expect(await monitor.registrationCount() == 1)
      withExtendedLifetime((cancellable, publisher)) {}
      await monitor.stopObserving()
    }

    /// `finish()` before the completion closure is set must still call it.
    @Test internal func completionSetAfterFinishStillRuns() async {
      let subject = PassthroughSubject<any DatabaseChangeSet, Never>()
      let agent = PublishingAgent(id: "late", subject: subject)
      let called = OSAllocatedUnfairLock(initialState: false)

      await agent.finish()
      await agent.setCompleted { called.withLock { $0 = true } }

      #expect(called.withLock { $0 })
      withExtendedLifetime(subject) {}
    }
  }
#endif
