/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import CoreData
import Intents
import ObvAppTypes
import ObvCommunicationInteractor
import ObvTypes
import ObvUICoreData


extension PersistedObvContactIdentity {
    
    static func getOneToOneDiscussionIdentifier(contactIdentifier: ObvContactIdentifier) async throws -> ObvDiscussionIdentifier? {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<ObvDiscussionIdentifier?, any Error>, context: NSManagedObjectContext) in
            guard let contactIdentity = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .oneToOne, within: context) else {
                return continuation.resume(returning: nil)
            }
            // Siri-sourced identifiers may point at a contact whose owned profile has since been hidden.
            guard contactIdentity.ownedIdentity?.isHidden == false else {
                return continuation.resume(returning: nil)
            }
            guard let discussion = contactIdentity.oneToOneDiscussion else {
                assertionFailure("The contact is one2one, we expect to have an associated one2one discussion")
                return continuation.resume(returning: nil)
            }
            let discussionIdentifier = try discussion.discussionIdentifier
            return continuation.resume(returning: discussionIdentifier)
        }
    }


    /// Returns all discussion identifiers (1:1 and all groups) in which the given contact is a member.
    static func getAllDiscussionIdentifiers(contactIdentifier: ObvContactIdentifier) async throws -> Set<ObvDiscussionIdentifier> {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<Set<ObvDiscussionIdentifier>, any Error>, context: NSManagedObjectContext) in
            guard let contact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: context) else {
                return continuation.resume(returning: Set())
            }
            // Siri-sourced identifiers may point at a contact whose owned profile has since been hidden.
            guard contact.ownedIdentity?.isHidden == false else {
                return continuation.resume(returning: Set())
            }
            var identifiers = Set<ObvDiscussionIdentifier>()
            if let id = try? contact.oneToOneDiscussion?.discussionIdentifier {
                identifiers.insert(id)
            }
            for contactGroup in contact.contactGroups {
                if let id = try? contactGroup.discussion.discussionIdentifier {
                    identifiers.insert(id)
                }
            }
            for groupMember in contact.asGroupV2Member {
                if let group = try? groupMember.persistedGroup,
                   let id = try? group.discussion?.discussionIdentifier {
                    identifiers.insert(id)
                }
            }
            continuation.resume(returning: identifiers)
        }
    }


    static func oneToOneDiscussionAsINPersonFromContactIdentifier(contactIdentifier: ObvContactIdentifier) async throws -> INPerson? {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<INPerson?, any Error>, context: NSManagedObjectContext) in
            guard let contactIdentity = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .oneToOne, within: context) else {
                return continuation.resume(returning: nil)
            }
            // Siri-sourced identifiers may point at a contact whose owned profile has since been hidden.
            guard contactIdentity.ownedIdentity?.isHidden == false else {
                return continuation.resume(returning: nil)
            }
            guard let discussion = contactIdentity.oneToOneDiscussion else {
                assertionFailure("The contact is one2one, we expect to have an associated one2one discussion")
                return continuation.resume(returning: nil)
            }
            let discussionINPerson = try discussion.toINPerson(withImage: true)
            return continuation.resume(returning: discussionINPerson)
        }
    }
    
}
