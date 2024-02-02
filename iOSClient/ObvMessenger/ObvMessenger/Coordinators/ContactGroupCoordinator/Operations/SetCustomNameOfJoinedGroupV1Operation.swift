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
import OlvidUtils
import ObvTypes
import ObvCrypto
import CoreData
import ObvUICoreData
import os.log


final class SetCustomNameOfJoinedGroupV1Operation: ContextualOperationWithSpecificReasonForCancel<SetCustomNameOfJoinedGroupV1Operation.ReasonForCancel> {
    
    private let ownedCryptoId: ObvCryptoId
    private let groupIdentifier: GroupV1Identifier
    private let groupNameCustom: String?
    
    private let makeSyncAtomRequest: Bool
    private weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?

    init(ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV1Identifier, groupNameCustom: String?, makeSyncAtomRequest: Bool, syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?) {
        self.ownedCryptoId = ownedCryptoId
        self.groupIdentifier = groupIdentifier
        self.groupNameCustom = groupNameCustom
        self.syncAtomRequestDelegate = syncAtomRequestDelegate
        self.makeSyncAtomRequest = makeSyncAtomRequest
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            let customDisplayNameWasUpdated = try ownedIdentity.setCustomNameOfJoinedGroupV1(groupIdentifier: groupIdentifier, to: groupNameCustom)
            
            // If the custom display name was updated, we propagate the change to our other owned devices
            
            if makeSyncAtomRequest && customDisplayNameWasUpdated {
                assert(self.syncAtomRequestDelegate != nil)
                if let syncAtomRequestDelegate = self.syncAtomRequestDelegate {
                    let ownedCryptoId = self.ownedCryptoId
                    let syncAtom = ObvSyncAtom.groupV1Nickname(groupOwner: groupIdentifier.groupOwner, groupUid: groupIdentifier.groupUid, groupNickname: groupNameCustom)
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
 
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case couldNotFindOwnedIdentity
        
        var logType: OSLogType {
            switch self {
            case .coreDataError, .couldNotFindOwnedIdentity:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            }
        }

    }

}
