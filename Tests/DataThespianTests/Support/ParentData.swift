//
//  ParentData.swift
//  DataThespian
//

import Foundation

/// Plain data mirrored into ``Parent`` rows by the synchronisation tests.
internal struct ParentData: Sendable, Equatable {
  internal let id: UUID
  internal let name: String

  internal init(id: UUID, name: String = "") {
    self.id = id
    self.name = name
  }
}
