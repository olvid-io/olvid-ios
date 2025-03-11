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
import os.log
import ObvTypes
import CoreData
import ObvUICoreData


final class UpdateCustomNicknameAndPictureForContactOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    let persistedContactObjectID: NSManagedObjectID
    let customDisplayName: String?
    let customPhoto: PhotoKind
    private let makeSyncAtomRequest: Bool
    private weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?
    
    enum PhotoKind {
        case url(url: URL?)
        case image(image: UIImage?)
    }
    
    init(persistedContactObjectID: NSManagedObjectID, customDisplayName: String?, customPhoto: PhotoKind, makeSyncAtomRequest: Bool, syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?) {
        self.persistedContactObjectID = persistedContactObjectID
        self.customDisplayName = customDisplayName
        self.customPhoto = customPhoto
        self.makeSyncAtomRequest = makeSyncAtomRequest
        self.syncAtomRequestDelegate = syncAtomRequestDelegate
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let contact = try PersistedObvContactIdentity.get(objectID: persistedContactObjectID, within: obvContext.context) else { assertionFailure(); return }
            let customDisplayNameWasUpdated = try contact.setCustomDisplayName(to: customDisplayName)
            switch customPhoto {
            case .url(let url):
                contact.setCustomPhotoURL(with: url)
            case .image(let image):
                try contact.setCustomPhoto(with: image)
            }

            // If the custom display name was updated, we propagate the change to our other owned devices
            
            if makeSyncAtomRequest && customDisplayNameWasUpdated {
                if let ownedCryptoId = contact.ownedIdentity?.cryptoId, let syncAtomRequestDelegate = self.syncAtomRequestDelegate {
                    let contactCryptoId = contact.cryptoId
                    let syncAtom = ObvSyncAtom.contactNickname(contactCryptoId: contactCryptoId, contactNickname: customDisplayName)
                    try? obvContext.addContextDidSaveCompletionHandler { error in
                        guard error == nil else { return }
                        Task.detached {
                            await syncAtomRequestDelegate.requestPropagationToOtherOwnedDevices(of: syncAtom, for: ownedCryptoId)
                        }
                    }
                } else {
                    assertionFailure("Could not propagate the new nickname to our other owned devices")
                }
            }
            
            // If the contact is updated, we want to refresh it in the view context to update the UI
            
            if contact.isUpdated {
                do {
                    let contactObjectID = contact.objectID
                    try obvContext.addContextDidSaveCompletionHandler { error in
                        guard error == nil else { return }
                        viewContext.perform {
                            guard let contactInViewContext = viewContext.registeredObjects.first(where: { $0.objectID == contactObjectID }) else { return }
                            viewContext.refresh(contactInViewContext, mergeChanges: false)
                        }
                    }
                } catch {
                    assertionFailure(error.localizedDescription)
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
}
