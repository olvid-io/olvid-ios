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

import Intents
import Foundation
import OSLog
import CoreData
import ObvAppTypes
import ObvTypes
import ObvUICoreData
import ObvSettings

actor SiriVocabularyManager {

    private static let logger = Logger(subsystem: ObvUICoreDataConstants.logSubsystem, category: "SiriVocabularyManager")

    private var isPerformPostInitializationPerformed = false
    private var debounceTask: Task<Void, Never>?
    
    func performPostInitialization() async {
        guard !isPerformPostInitializationPerformed else { return }
        defer { isPerformPostInitializationPerformed = true }
        await PersistedObvContactIdentity.addObvObserver(self)
        await DisplayedContactGroup.addObvObserver(self)
        await PersistedObvOwnedIdentity.addObvObserver(self)
        await PersistedContactGroupJoined.addObvObserver(self)
        await PersistedGroupV2.addObvObserver(self)
    }


    func updateContactsVocabularies() async {

        await performPostInitialization()
        
        do {
            Self.logger.info("Will set INVocabulary for contacts")
            let contactsVocabulary = try await PersistedObvContactIdentity.getAllINSpeakableStrings()
            INVocabulary.shared().setVocabulary(NSOrderedSet(array: contactsVocabulary), of: .contactName)
            Self.logger.info("Did set INVocabulary for contacts")
        } catch {
            Self.logger.error("Could not set INVocabulary for contacts: \(error)")
            assertionFailure()
        }

        Self.logger.info("Will set INVocabulary for groups")

        var groupDiscussionsVocabulary = [INSpeakableString]()

        var isGroupV2DiscussionsVocabularyAvailable = false

        do {
            let groupV2DiscussionsVocabulary = try await PersistedGroupV2.getAllINSpeakableStrings()
            groupDiscussionsVocabulary.append(contentsOf: groupV2DiscussionsVocabulary)
            isGroupV2DiscussionsVocabularyAvailable = true
        } catch {
            Self.logger.error("Could not determine INVocabulary for groups v2: \(error)")
            assertionFailure()
        }

        var isGroupV1DiscussionsVocabularyAvailable = false

        do {
            let groupV1DiscussionsVocabulary = try await PersistedContactGroup.getAllINSpeakableStrings()
            groupDiscussionsVocabulary.append(contentsOf: groupV1DiscussionsVocabulary)
            isGroupV1DiscussionsVocabularyAvailable = true
        } catch {
            Self.logger.error("Could not determine INVocabulary for groups v1: \(error)")
            assertionFailure()
        }

        if isGroupV1DiscussionsVocabularyAvailable || isGroupV2DiscussionsVocabularyAvailable {
            INVocabulary.shared().setVocabulary(NSOrderedSet(array: groupDiscussionsVocabulary), of: .contactGroupName)
            Self.logger.info("Did set INVocabulary for groups")
        } else {
            Self.logger.error("Could not set INVocabulary for groups")
        }

    }


    private func scheduleVocabularyUpdate() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await updateContactsVocabularies()
        }
    }

}


// MARK: - Implementing PersistedObvContactIdentityObserver

extension SiriVocabularyManager: PersistedObvContactIdentityObserver {

    func aPersistedObvContactIdentityWasInserted(contactIdentifier: ObvContactIdentifier, isOneToOne: Bool) async {
        scheduleVocabularyUpdate()
    }

    func aPersistedObvContactIdentityWasDeleted(contactIdentifier: ObvContactIdentifier) async {
        scheduleVocabularyUpdate()
    }

    func aPersistedContactIsActiveStatusChanged(contactIdentifier: ObvContactIdentifier) async {
        scheduleVocabularyUpdate()
    }

    func aPersistedContactOneToOneStatusChanged(contactIdentifier: ObvContactIdentifier) async {
        scheduleVocabularyUpdate()
    }

    func aPersistedObvContactIdentityCustomDisplayNameChanged(contactIdentifier: ObvContactIdentifier) async {
        scheduleVocabularyUpdate()
    }

    func aPersistedObvContactIdentityFullDisplayNameChanged(contactIdentifier: ObvContactIdentifier) async {
        scheduleVocabularyUpdate()
    }
    
}


// MARK: - Implementing PersistedObvOwnedIdentityObserver

extension SiriVocabularyManager: PersistedObvOwnedIdentityObserver {

    func aPersistedObvOwnedIdentityIsHiddenChanged(ownedCryptoId: ObvCryptoId, isHidden: Bool) async {
        scheduleVocabularyUpdate()
    }

}


// MARK: - Implementing PersistedContactGroupJoinedObserver

extension SiriVocabularyManager: PersistedContactGroupJoinedObserver {

    func aGroupV1CustomNameChanged(groupIdentifier: ObvGroupV1Identifier) async {
        scheduleVocabularyUpdate()
    }

}


// MARK: - Implementing PersistedGroupV2Observer

extension SiriVocabularyManager: PersistedGroupV2Observer {

    func aGroupV2CustomNameChanged(groupIdentifier: ObvGroupV2Identifier) async {
        scheduleVocabularyUpdate()
    }

}


// MARK: - Implementing DisplayedContactGroupObserver

extension SiriVocabularyManager: DisplayedContactGroupObserver {
    
    func aDisplayedContactGroupWasInserted(groupIdentifier: ObvGroupIdentifier) async {
        scheduleVocabularyUpdate()
    }
    
}


// MARK: - Vocabulary identifier design note
//
// INSpeakableString.vocabularyIdentifier carries different identifier types for contacts and groups.
// This is intentional — not an oversight — for the following reasons:
//
// CONTACTS use ObvContactIdentifier
//   The contact vocabulary (INVocabularyType.contactName) is shared by all three intent types:
//   calling (INStartCallIntent), messaging (INSendMessageIntent), and search
//   (INSearchForMessagesIntent). StartCallIntentHandler strictly requires ObvContactIdentifier in
//   customIdentifier (it has no fallback path). Switching contacts to ObvDiscussionIdentifier would
//   break every call initiated from Siri vocabulary.
//
// GROUPS use ObvDiscussionIdentifier
//   There is a 1:1 mapping between a group and its discussion, so the discussion identifier
//   unambiguously identifies the group. It also carries the owned-identity context, which is
//   necessary in multi-profile setups to look up the right discussion without an extra DB query.
//   Every group handler (SendMessageIntentHandler, SearchForMessagesIntentHandler,
//   PersistedDiscussion.resolveGroupName) decodes vocabularyIdentifier as ObvDiscussionIdentifier
//   directly — using ObvGroupIdentifier instead would add a resolution step at every call site.
//
// Do not harmonise these two types without updating StartCallIntentHandler and all group handlers.

fileprivate extension PersistedObvContactIdentity {

    static func getAllINSpeakableStrings() async throws -> [INSpeakableString] {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INSpeakableString], any Error>, context: NSManagedObjectContext) in
            // Restricted to one-to-one contacts for two reasons:
            // 1. Non-one-to-one contacts can be numerous, and registering all of them would bloat
            //    Siri's vocabulary and slow down name recognition.
            // 2. When a user says "call Alice" or "message Alice", they almost always mean their
            //    direct contact. Including group-only contacts would add noise to disambiguation.
            let contacts = try PersistedObvContactIdentity.getAll(within: context, restrictToContactsOfNonHiddenOwnedIdentities: true, whereOneToOneStatusIs: .oneToOne)
            // Contacts with a nickname get two entries: nickname first (higher Siri priority),
            // then the full name. Both carry the same vocabularyIdentifier so Siri resolves
            // either phrase to the same contact.
            let contactsVocabulary: [INSpeakableString] = contacts.flatMap { persistedContact -> [INSpeakableString] in
                guard let contactIdentifier = try? persistedContact.obvContactIdentifier else { return [] }
                let identifier = contactIdentifier.description
                var strings: [INSpeakableString] = []
                if let nickname = persistedContact.customDisplayName, !nickname.isEmpty {
                    strings.append(INSpeakableString(vocabularyIdentifier: identifier, spokenPhrase: nickname, pronunciationHint: nil))
                }
                strings.append(INSpeakableString(vocabularyIdentifier: identifier, spokenPhrase: persistedContact.fullDisplayName, pronunciationHint: nil))
                return strings
            }
            return continuation.resume(returning: contactsVocabulary)
        }
    }

}


fileprivate extension PersistedGroupV2 {

    static func getAllINSpeakableStrings() async throws -> [INSpeakableString] {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INSpeakableString], any Error>, context: NSManagedObjectContext) in
            let groups = try Self.getAllPersistedGroupV2(restrictToGroupsOfNonHiddenOwnedIdentities: true, within: context)
            let discussionsVocabulary: [INSpeakableString] = groups.compactMap { group in
                guard let discussion = group.discussion else { return nil }
                guard let discussionIdentifier = try? discussion.discussionIdentifier else { return nil }
                return INSpeakableString(vocabularyIdentifier: discussionIdentifier.description, spokenPhrase: discussion.title, pronunciationHint: nil)
            }
            return continuation.resume(returning: discussionsVocabulary)
        }
    }

}


fileprivate extension PersistedContactGroup {

    static func getAllINSpeakableStrings() async throws -> [INSpeakableString] {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INSpeakableString], any Error>, context: NSManagedObjectContext) in
            let groups = try Self.getAllPersistedGroupV1(restrictToGroupssOfNonHiddenOwnedIdentities: true, within: context)
            let discussionsVocabulary: [INSpeakableString] = groups.compactMap { group in
                let discussion = group.discussion
                guard let discussionIdentifier = try? discussion.discussionIdentifier else { return nil }
                return INSpeakableString(vocabularyIdentifier: discussionIdentifier.description, spokenPhrase: discussion.title, pronunciationHint: nil)
            }
            return continuation.resume(returning: discussionsVocabulary)
        }
    }

}
