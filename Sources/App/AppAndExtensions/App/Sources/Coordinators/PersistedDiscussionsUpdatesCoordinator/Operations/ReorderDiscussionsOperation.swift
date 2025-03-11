/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import os.log
import ObvEngine
import ObvTypes
import OlvidUtils
import ObvUICoreData


final class ReorderDiscussionsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    let input: Input
    let ownedIdentity: ObvCryptoId
    
    private let makeSyncAtomRequest: Bool
    private weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?

    enum Input {
        case discussionObjectIDs(discussionObjectIDs: [NSManagedObjectID])
        case discussionsIdentifiers(discussionIdentifiers: [ObvSyncAtom.DiscussionIdentifier], ordered: Bool)
    }
    
    init(input: Input, ownedIdentity: ObvCryptoId, makeSyncAtomRequest: Bool, syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?) {
        self.input = input
        self.ownedIdentity = ownedIdentity
        self.makeSyncAtomRequest = makeSyncAtomRequest
        self.syncAtomRequestDelegate = syncAtomRequestDelegate
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            
            let discussionObjectIDs: [NSManagedObjectID]
            let ordered: Bool
            
            switch input {
            case .discussionObjectIDs(discussionObjectIDs: let objectIDs):
                discussionObjectIDs = objectIDs
                ordered = true
            case .discussionsIdentifiers(discussionIdentifiers: let discussionIdentifiers, ordered: let _ordered):
                ordered = _ordered
                discussionObjectIDs = discussionIdentifiers.compactMap { discussionIdentifier in
                    switch discussionIdentifier {
                    case .oneToOne(contactCryptoId: let contactCryptoId):
                        let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedIdentity)
                        guard let contact = try? PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .oneToOne, within: obvContext.context) else {
                            return nil
                        }
                        return contact.oneToOneDiscussion?.objectID
                    case .groupV1(groupIdentifier: let groupIdentifier):
                        guard let groupV1 = try? PersistedContactGroup.getContactGroup(groupIdentifier: groupIdentifier, ownedCryptoId: ownedIdentity, within: obvContext.context) else {
                            return nil
                        }
                        return groupV1.discussion.objectID
                    case .groupV2(groupIdentifier: let groupIdentifier):
                        guard let groupV2 = try? PersistedGroupV2.get(ownIdentity: ownedIdentity, appGroupIdentifier: groupIdentifier, within: obvContext.context) else {
                            return nil
                        }
                        return groupV2.discussion?.objectID
                    }
                }
            }
            
            let atLeastOnePinnedIndexWasChanged = try PersistedDiscussion.setPinnedDiscussions(persistedDiscussionObjectIDs: discussionObjectIDs, ordered: ordered, ownedCryptoId: ownedIdentity, within: obvContext.context)
            
            // Propagate the new order to our other owned devices if required
            
            if makeSyncAtomRequest && atLeastOnePinnedIndexWasChanged {
                assert(self.syncAtomRequestDelegate != nil)
                if let syncAtomRequestDelegate = self.syncAtomRequestDelegate {
                    let ownedCryptoId = self.ownedIdentity
                    guard let pinnedDiscussions = try? PersistedDiscussion.getAllPinnedDiscussions(ownedCryptoId: ownedCryptoId, with: obvContext.context) else { assertionFailure(); return }
                    let discussionIdentifiers: [ObvSyncAtom.DiscussionIdentifier] = pinnedDiscussions.compactMap { getObvSyncAtomDiscussionIdentifierFrom(persistedDiscussion: $0) }
                    let syncAtom = ObvSyncAtom.pinnedDiscussions(discussionIdentifiers: discussionIdentifiers, ordered: true)
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
