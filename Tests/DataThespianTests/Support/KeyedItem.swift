//
//  KeyedItem.swift
//  DataThespian
//

#if canImport(SwiftData)
  import DataThespian
  import Foundation
  import SwiftData

  /// A model with a unique key, used to test `UniqueKeyPath`.
  @Model
  internal final class KeyedItem: Unique {
    internal enum Keys: UniqueKeys {
      internal typealias Model = KeyedItem
      internal static let primary = keyPath(\KeyedItem.name)
    }

    internal var name: String

    internal init(name: String) {
      self.name = name
    }
  }
#endif
