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
import ObvUICoreData
import CoreData
import os.log


final class UpdateCustomNameAndGroupV2PhotoOperation: ContextualOperationWithSpecificReasonForCancel<UpdateCustomNameAndGroupV2PhotoOperation.ReasonForCancel> {
    
    enum Update {
        case customName(customName: String?)
        case customNameAndCustomPhoto(customName: String?, customPhoto: UIImage?)
    }
    
    private let ownedCryptoId: ObvCryptoId
    private let groupIdentifier: Data
    private let update: Update
    
    private let makeSyncAtomRequest: Bool
    private weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?

    init(ownedCryptoId: ObvCryptoId, groupIdentifier: Data, update: Update, makeSyncAtomRequest: Bool, syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?) {
        self.ownedCryptoId = ownedCryptoId
        self.groupIdentifier = groupIdentifier
        self.update = update
        self.makeSyncAtomRequest = makeSyncAtomRequest
        self.syncAtomRequestDelegate = syncAtomRequestDelegate
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            // Update the custom name
            
            switch update {
            case .customNameAndCustomPhoto(customName: let customName, customPhoto: _),
                    .customName(customName: let customName):
                
                let groupNameCustomHadToBeUpdated = try ownedIdentity.setCustomNameOfGroupV2(groupIdentifier: groupIdentifier, to: customName)

                // If the custom display name was updated, we propagate the change to our other owned devices
                
                if makeSyncAtomRequest && groupNameCustomHadToBeUpdated {
                    assert(self.syncAtomRequestDelegate != nil)
                    if let syncAtomRequestDelegate = self.syncAtomRequestDelegate {
                        let ownedCryptoId = self.ownedCryptoId
                        let syncAtom = ObvSyncAtom.groupV2Nickname(groupIdentifier: groupIdentifier, groupNickname: customName)
                        try? obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            Task.detached {
                                await syncAtomRequestDelegate.requestPropagationToOtherOwnedDevices(of: syncAtom, for: ownedCryptoId)
                            }
                        }
                    }
                }

            }
            
            // Update the custom photo
            
            switch update {
            case .customName:
                break
            case .customNameAndCustomPhoto(customName: _, customPhoto: let customPhoto):
                
                try ownedIdentity.updateCustomPhotoOfGroupV2(withGroupIdentifier: groupIdentifier, withPhoto: customPhoto, within: obvContext)
                
            }
                        
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case couldNotFindOwnedIdentity
        case coreDataError(error: Error)
        
        var logType: OSLogType {
            return .fault
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
