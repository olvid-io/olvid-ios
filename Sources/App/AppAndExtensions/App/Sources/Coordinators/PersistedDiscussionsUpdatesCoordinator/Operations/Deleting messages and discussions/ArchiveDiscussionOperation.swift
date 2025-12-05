/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OlvidUtils
import ObvUICoreData
import CoreData
import ObvTypes

final class ArchiveDiscussionOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    let input: Input
    let action: Action
    
    enum Input {
        case discussionObjectID(TypeSafeManagedObjectID<PersistedDiscussion>)
        case discussionsIdentifier(ownedCryptoId: ObvCryptoId, discussionIdentifier: ObvSyncAtom.DiscussionIdentifier)
    }
    
    enum Action {
        case archive
        case unarchive
    }
    
    private let makeSyncAtomRequest: Bool
    private weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?
    
    init(input: Input, action: Action, makeSyncAtomRequest: Bool, syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?) {
        self.input = input
        self.action = action
        self.makeSyncAtomRequest = makeSyncAtomRequest
        self.syncAtomRequestDelegate = syncAtomRequestDelegate
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let discussion: PersistedDiscussion?
            
            switch input {
            case .discussionObjectID(let discussionObjectID):
                discussion = try PersistedDiscussion.get(objectID: discussionObjectID.objectID, within: obvContext.context)
            case .discussionsIdentifier(ownedCryptoId: let ownedCryptoId, discussionIdentifier: let discussionIdentifier):
                switch discussionIdentifier {
                case .oneToOne(contactCryptoId: let contactCryptoId):
                    let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
                    guard let contact = try? PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .oneToOne, within: obvContext.context) else {
                        return
                    }
                    discussion = contact.oneToOneDiscussion
                case .groupV1(groupIdentifier: let groupIdentifier):
                    guard let groupV1 = try? PersistedContactGroup.getContactGroup(groupIdentifier: groupIdentifier, ownedCryptoId: ownedCryptoId, within: obvContext.context) else {
                        return
                    }
                    discussion = groupV1.discussion
                case .groupV2(groupIdentifier: let groupIdentifier):
                    guard let groupV2 = try? PersistedGroupV2.get(ownIdentity: ownedCryptoId, appGroupIdentifier: groupIdentifier, within: obvContext.context) else {
                        return
                    }
                    discussion =  groupV2.discussion
                }
            }
            
            guard let discussion, let ownedCryptoId = discussion.ownedIdentity?.cryptoId else { return }
            
            switch action {
            case .archive:
                try discussion.archive()
            case .unarchive:
                discussion.unarchive()
            }
            
            if makeSyncAtomRequest {
                assert(self.syncAtomRequestDelegate != nil)
                if let syncAtomRequestDelegate = self.syncAtomRequestDelegate,
                    let discussionIdentifier = getObvSyncAtomDiscussionIdentifierFrom(persistedDiscussion: discussion) {
                    
                    var archived = false
                    switch action {
                    case .archive: archived = true
                    case .unarchive: archived = false
                    }
                    
                    let syncAtom = ObvSyncAtom.archivedDiscussions(discussionIdentifiers: [discussionIdentifier], archived: archived)
                    try? obvContext.addContextDidSaveCompletionHandler { error in
                        guard error == nil else { return }
                        Task.detached {
                            await syncAtomRequestDelegate.requestPropagationToOtherOwnedDevices(of: syncAtom, for: ownedCryptoId)
                        }
                    }
                }
            }
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    private func getObvSyncAtomDiscussionIdentifierFrom(persistedDiscussion: PersistedDiscussion) -> ObvSyncAtom.DiscussionIdentifier? {
        guard let discussionKind = try? persistedDiscussion.kind else { assertionFailure(); return nil }
        switch discussionKind {
        case .oneToOne(withContactIdentity: let persistedContact):
            guard let persistedContact else { assertionFailure(); return nil }
            return .oneToOne(contactCryptoId: persistedContact.cryptoId)
        case .groupV1(withContactGroup: let groupV1):
            guard let groupV1 else { assertionFailure(); return nil }
            guard let groupId = try? groupV1.getGroupId() else { assertionFailure(); return nil }
            return .groupV1(groupIdentifier: groupId)
        case .groupV2(withGroup: let groupV2):
            guard let groupV2 else { assertionFailure(); return nil }
            return .groupV2(groupIdentifier: groupV2.groupIdentifier)
        }

    }
}
