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
import ObvCrypto
import ObvMetaManager
import ObvEncoder
import OlvidUtils


/// As a result of requesting a refresh of a `UserData` on the server, it can happen that the server responds with a `.deletedFromServer` error. In that case, we try to put the `UserData` back on the server.
/// This operation is executed in that situation and creates the `PendingServerQuery` that, when executed, will put the `UserData` back on the server.
final class CreatePendingServerQueryOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let ownedCryptoId: ObvCryptoIdentity
    private let label: UID
    private let delegateManager: ObvNetworkFetchDelegateManager
    private let identityDelegate: ObvIdentityDelegate
    
    init(ownedCryptoId: ObvCryptoIdentity, label: UID, delegateManager: ObvNetworkFetchDelegateManager, identityDelegate: ObvIdentityDelegate) {
        self.ownedCryptoId = ownedCryptoId
        self.label = label
        self.delegateManager = delegateManager
        self.identityDelegate = identityDelegate
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let userData = identityDelegate.getServerUserData(for: ownedCryptoId, with: label, within: obvContext) else { return }
            
            let dataURL: URL?
            let dataKey: AuthenticatedEncryptionKey?
            switch userData.kind {
            case .identity:
                let (ownedIdentityDetailsElements, photoURL) = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(userData.ownedIdentity, within: obvContext)
                dataURL = photoURL
                dataKey = ownedIdentityDetailsElements.photoServerKeyAndLabel?.key
            case .group(groupUid: let groupUid):
                let groupInformationWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: userData.ownedIdentity, groupUid: groupUid, within: obvContext)
                dataURL = groupInformationWithPhoto.groupDetailsElementsWithPhoto.photoURL
                dataKey = groupInformationWithPhoto.groupDetailsElementsWithPhoto.photoServerKeyAndLabel?.key
            case .groupV2(groupIdentifier: let groupIdentifier):
                guard let photoURLAndServerPhotoInfo = try identityDelegate.getGroupV2PhotoURLAndServerPhotoInfofOwnedIdentityIsUploader(ownedIdentity: userData.ownedIdentity, groupIdentifier: groupIdentifier, within: obvContext) else {
                    throw Self.makeError(message: "Could not get photoURLAndServerPhotoInfo for group v2 (the owned identity might not be the uploader)")
                }
                dataURL = photoURLAndServerPhotoInfo.photoURL
                dataKey = photoURLAndServerPhotoInfo.serverPhotoInfo.photoServerKeyAndLabel.key
            }
            
            guard let dataURL, let dataKey else { return }
            
            let serverQueryType: ServerQuery.QueryType = .putUserData(label: label, dataURL: dataURL, dataKey: dataKey)
            let noElements: [ObvEncoded] = []
            
            let serverQuery = ServerQuery(ownedIdentity: ownedCryptoId, queryType: serverQueryType, encodedElements: noElements.obvEncode())
            
            _ = PendingServerQuery(serverQuery: serverQuery, delegateManager: delegateManager, within: obvContext)

        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
