/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import SwiftUI

@available(iOS 13, *)
struct ValueWithBinding<Root: TypeWithObjectID, Value> {
    let value: Value
    let objectID: TypeSafeManagedObjectID<Root>?
    let sendNotification: ((Value, TypeSafeManagedObjectID<Root>) -> Void)?

    init(_ root: Root,
         _ keyPath: KeyPath<Root, Value>,
         sendNotification: @escaping (Value, TypeSafeManagedObjectID<Root>) -> Void) {
        self.value = root[keyPath: keyPath]
        self.objectID = root.typedObjectID
        self.sendNotification = sendNotification
    }

    init(_ root: Root,
         _ keyPath: KeyPath<Root, Value?>,
         defaultValue: Value,
         sendNotification: @escaping (Value, TypeSafeManagedObjectID<Root>) -> Void) {
        self.value = root[keyPath: keyPath] ?? defaultValue
        self.objectID = root.typedObjectID
        self.sendNotification = sendNotification
    }

    /// This init is less typed than the others, please call inits with KeyPath as far as possible.
    init(_ root: Root,
         _ value: Value,
         sendNotification: @escaping (Value, TypeSafeManagedObjectID<Root>) -> Void) {
        self.value = value
        self.objectID = root.typedObjectID
        self.sendNotification = sendNotification
    }

    /// For testing purpose
    init(constant: Value) {
        self.value = constant
        self.objectID = nil
        self.sendNotification = nil
    }

    func set(_ newValue: Value) {
        if let objectID = objectID,
           let sendNotification = sendNotification {
            sendNotification(newValue, objectID)
        }
    }

    var binding: Binding<Value> {
        .init {
            value
        } set: { newValue in
            set(newValue)
        }
    }
}

@available(iOS 13.0, *)
extension Binding {

    func map(_ tranform: @escaping (Value) -> Value) -> Binding<Value> {
        .init {
            wrappedValue
        } set: { newValue in
            wrappedValue = tranform(newValue)
        }
    }

}
