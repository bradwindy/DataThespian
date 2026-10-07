//
//  RegistrationCollection.swift
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

  /// An actor that manages a collection of `DataAgent` registrations.
  internal actor RegistrationCollection: Loggable {
    internal static var loggingCategory: ThespianLogging.Category { .application }

    private var registrations = [String: any DataAgent]()

    /// Whether no agent is registered.
    internal var isEmpty: Bool { registrations.isEmpty }

    /// The number of registered agents.
    internal var count: Int { registrations.count }

    /// The `agentID` of the agent registered under `id`, if any.
    internal func agentID(forID id: String) -> UUID? {
      registrations[id]?.agentID
    }

    /// Adds a new `DataAgent` registration to the collection.
    ///
    /// The agent is built first. The existing registration is then read and replaced with
    /// no suspension point in between, so two registrations for one id cannot both win.
    /// An agent that loses, or that a forced registration displaces, is finished.
    ///
    /// - Parameters:
    ///   - id: The unique identifier for the registration.
    ///   - force: A Boolean value indicating whether to replace an existing registration.
    ///   - agent: A closure that creates the `DataAgent` to be registered.
    internal func append(
      withID id: String, force: Bool, agent makeAgent: @Sendable @escaping () async -> any DataAgent
    ) async {
      if !force, registrations[id] != nil {
        Self.logger.debug("Can't register \(id, privacy: .public). Already exists.")
        return
      }
      let agent = await makeAgent()

      // No suspension from this read until the store below.
      let existing = registrations[id]
      if existing != nil, !force {
        Self.logger.debug("Can't register \(id, privacy: .public). Already exists.")
        if existing?.agentID != agent.agentID {
          await agent.finish()
        }
        return
      }
      registrations[id] = agent
      let agentID = agent.agentID
      agent.onCompleted { [weak self] in
        Task { await self?.remove(withID: id, agentID: agentID) }
      }
      Self.logger.debug(
        "Registered \(id, privacy: .public) \(agentID, privacy: .public). Count \(self.registrations.count)"
      )

      if let existing, existing.agentID != agentID {
        Self.logger.debug("Replaced \(id, privacy: .public) \(existing.agentID, privacy: .public)")
        await existing.finish()
      }
    }

    private func remove(withID id: String, agentID: UUID) {
      guard let agent = registrations[id] else {
        Self.logger.warning("No matching registration with id: \(id, privacy: .public)")
        return
      }
      guard agent.agentID == agentID else {
        // Expected when a forced registration replaced this agent.
        Self.logger.debug(
          "Registration \(id, privacy: .public) already replaced; ignoring \(agentID, privacy: .public)"
        )
        return
      }
      registrations.removeValue(forKey: id)
      Self.logger.debug("Registration Count \(self.registrations.count)")
    }

    /// Passes a change set to every registered agent.
    internal func onUpdate(_ update: any DatabaseChangeSet) {
      for (id, registration) in registrations {
        Self.logger.debug("Notifying \(id, privacy: .public)")
        registration.onUpdate(update)
      }
    }
  }
#endif
