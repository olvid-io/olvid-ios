/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import Combine
import CoreData
import ObvTypes


/// Proxy object allowing to embed any type representing an Olvid user from one of its possible persistent representations within the app.
///
/// Currently, the two supported representations are `PersistedObvContactIdentity` and `PersistedGroupV2Member`.
///
/// This proxy leverages the `Observable` compliance of the proxied objects so as to be itself `Observable`, which makes it easy to use in SwiftUI views.
/// It is particularly useful when displaying a mix of contacts and non-contact group members during a group update, where a pending group member might not be contact yet.
public final class PersistedUser: ObservableObject {
    
    public enum Kind {
        case contact(contact: PersistedObvContactIdentity)
        case groupMember(groupMember: PersistedGroupV2Member)
        fileprivate var rawKind: RawKind {
            switch self {
            case .contact: return .contact
            case .groupMember: return .groupMember
            }
        }
    }

    fileprivate enum RawKind {
        case contact
        case groupMember
    }
    
    public let userIdentifier: ObvContactIdentifier
    public let normalizedSortKey: String
    
    public let kind: Kind
    private var cancellable: AnyCancellable?


    deinit {
        self.cancellable?.cancel()
    }

    
    public init(contact: PersistedObvContactIdentity) throws {
        self.kind = .contact(contact: contact)
        self.userIdentifier = try contact.obvContactIdentifier
        self.normalizedSortKey = contact.sortDisplayName
        // We leverage the fact that
        self.cancellable = contact.objectWillChange.sink(receiveValue: { [weak self] _ in
            self?.objectWillChange.send()
        })
    }
    
    
    public init(groupMember: PersistedGroupV2Member) throws {
        self.kind = .groupMember(groupMember: groupMember)
        self.userIdentifier = try groupMember.userIdentifier
        self.normalizedSortKey = groupMember.normalizedSortKey
        self.cancellable = groupMember.objectWillChange.sink(receiveValue: { [weak self] _ in
            self?.objectWillChange.send()
        })
    }
    
    
    var managedObjectContext: NSManagedObjectContext? {
        switch kind {
        case .contact(let contact):
            return contact.managedObjectContext
        case .groupMember(let groupMember):
            return groupMember.managedObjectContext
        }
    }
    
}


// MARK: - Implementing equatable

extension PersistedUser: Equatable {
    
    public static func == (lhs: PersistedUser, rhs: PersistedUser) -> Bool {
        switch lhs.kind {
        case .contact(contact: let lhsContact):
            switch rhs.kind {
            case .contact(contact: let rhsContact):
                return lhsContact == rhsContact
            default:
                return false
            }
        case .groupMember(groupMember: let lhsGroupMember):
            switch rhs.kind {
            case .groupMember(groupMember: let rhsGroupMember):
                return lhsGroupMember == rhsGroupMember
            default:
                return false
            }
        }
    }
    
}

// MARK: - Implementing Hashable

extension PersistedUser: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.kind.rawKind)
        switch self.kind {
        case .contact(contact: let contact):
            hasher.combine(contact)
        case .groupMember(groupMember: let groupMember):
            hasher.combine(groupMember)
        }
    }
    
}


// MARK: - Implementing Comparable

extension PersistedUser: Comparable {
    
    public static func < (lhs: PersistedUser, rhs: PersistedUser) -> Bool {
        lhs.normalizedSortKey < rhs.normalizedSortKey
    }
    
}
