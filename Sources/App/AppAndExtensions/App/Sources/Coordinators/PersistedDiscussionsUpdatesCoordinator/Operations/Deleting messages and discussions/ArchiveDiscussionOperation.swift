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
                    guard let oneToOneDiscussion = try? PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: .oneToOne(id: contactIdentifier), within: obvContext.context) else {
                        return
                    }
                    discussion = oneToOneDiscussion
                case .groupV1(groupIdentifier: let groupIdentifier):
                    guard let groupV1Discussion = try? PersistedGroupDiscussion.getPersistedDiscussion(ownedCryptoId: ownedCryptoId, discussionId: .groupV1(id: .groupV1Identifier(groupV1Identifier: groupIdentifier)), within: obvContext.context) else {
                        return
                    }
                    discussion = groupV1Discussion
                case .groupV2(groupIdentifier: let groupIdentifier):
                    guard let identifier = ObvGroupV2.Identifier(appGroupIdentifier: groupIdentifier) else { assertionFailure(); return }
                    let obvGroupV2Identifier = ObvGroupV2Identifier(ownedCryptoId: ownedCryptoId, identifier: identifier)
                    guard let groupV2Discussion = try? PersistedGroupV2Discussion.getPersistedDiscussion(discussionIdentifier: .groupV2(id: obvGroupV2Identifier), within: obvContext.context) else { assertionFailure(); return }
                    discussion = groupV2Discussion
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
        case .oneToOne(withContactIdentity: _):
            guard let oneToOneDiscussion = persistedDiscussion as? PersistedOneToOneDiscussion else { assertionFailure(); return nil }
            guard let contactCryptoId = oneToOneDiscussion.contactCryptoId else { assertionFailure(); return nil }
            return .oneToOne(contactCryptoId: contactCryptoId)
        case .groupV1(withContactGroup: _):
            guard let groupV1Discussion = persistedDiscussion as? PersistedGroupDiscussion else { assertionFailure(); return nil }
            guard let groupId = groupV1Discussion.groupIdentifier else { assertionFailure(); return nil }
            return .groupV1(groupIdentifier: groupId.groupV1Identifier)
        case .groupV2(withGroup: _):
            guard let groupV2Discussion = persistedDiscussion as? PersistedGroupV2Discussion else { assertionFailure(); return nil }
            guard let groupId = groupV2Discussion.obvGroupIdentifier else { assertionFailure(); return nil }
            return .groupV2(groupIdentifier: groupId.identifier.appGroupIdentifier)
        }
    }
}
