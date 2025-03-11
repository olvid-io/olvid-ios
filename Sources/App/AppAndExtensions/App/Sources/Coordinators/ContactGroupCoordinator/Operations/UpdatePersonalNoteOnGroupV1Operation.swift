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
import CoreData
import os.log
import ObvEngine
import ObvUICoreData
import ObvTypes
import ObvCrypto


final class UpdatePersonalNoteOnGroupV1Operation: ContextualOperationWithSpecificReasonForCancel<UpdatePersonalNoteOnGroupV1Operation.ReasonForCancel>, @unchecked Sendable {
    
    private let ownedCryptoId: ObvCryptoId
    private let groupIdentifier: GroupV1Identifier
    private let newText: String?
    
    private let makeSyncAtomRequest: Bool
    private weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?

    init(ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV1Identifier, newText: String?, makeSyncAtomRequest: Bool, syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?) {
        self.ownedCryptoId = ownedCryptoId
        self.groupIdentifier = groupIdentifier
        self.newText = newText
        self.makeSyncAtomRequest = makeSyncAtomRequest
        self.syncAtomRequestDelegate = syncAtomRequestDelegate
        super.init()
    }
    
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            let noteHadToBeUpdatedInDatabase = try ownedIdentity.setPersonalNoteOnGroupV1(groupIdentifier: groupIdentifier, newText: newText)
            
            if makeSyncAtomRequest && noteHadToBeUpdatedInDatabase {
                assert(self.syncAtomRequestDelegate != nil)
                if let syncAtomRequestDelegate = self.syncAtomRequestDelegate {
                    let ownedCryptoId = self.ownedCryptoId
                    let syncAtom = ObvSyncAtom.groupV1PersonalNote(groupOwner: groupIdentifier.groupOwner, groupUid: groupIdentifier.groupUid, note: newText)
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
            return .fault
        }
        
        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            }
        }

    }

    
}
