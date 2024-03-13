/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import os.log
import CoreData
import ObvCrypto
import OlvidUtils
import ObvServerInterface
import ObvMetaManager


/// This operation processes the response returned by the server after posting a ``PendingServerQuery``.
final class ProcessServerResponseToPendingServerQueryOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let pendingServerQueryObjectID: NSManagedObjectID
    private let responseData: Data
    private let log: OSLog
    private let delegateManager: ObvNetworkFetchDelegateManager
    private let downloadedUserData: URL
    private let sessionTokenUsed: Data?
    
    
    init(pendingServerQueryObjectID: NSManagedObjectID, responseData: Data, log: OSLog, delegateManager: ObvNetworkFetchDelegateManager, downloadedUserData: URL, sessionTokenUsed: Data?) {
        self.pendingServerQueryObjectID = pendingServerQueryObjectID
        self.responseData = responseData
        self.log = log
        self.delegateManager = delegateManager
        self.downloadedUserData = downloadedUserData
        self.sessionTokenUsed = sessionTokenUsed
        super.init()
    }
    
    enum PostOperationAction: CustomDebugStringConvertible, Hashable {
        case postResponseAndDeleteServerQuery(pendingServerQueryObjectID: NSManagedObjectID)
        case shouldBeProcessedByServerQueryWebSocketCoordinator
        case retryLater(pendingServerQueryObjectID: NSManagedObjectID)
        case retryAsSessionIsInvalid(pendingServerQueryObjectID: NSManagedObjectID, ownedCryptoId: ObvCryptoIdentity, invalidToken: Data)
        case pendingServerQueryNotFound
        case cancelAsOwnedIdentityIsNotActive
        
        var debugDescription: String {
            switch self {
            case .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: let pendingServerQueryObjectID):
                return "PostOperationAction.postResponseAndDeleteServerQuery<\(pendingServerQueryObjectID.debugDescription)>"
            case .shouldBeProcessedByServerQueryWebSocketCoordinator:
                return "PostOperationAction.shouldBeProcessedByServerQueryWebSocketCoordinator"
            case .retryLater(pendingServerQueryObjectID: let pendingServerQueryObjectID):
                return "PostOperationAction.retryLater<\(pendingServerQueryObjectID.debugDescription)>"
            case .retryAsSessionIsInvalid(pendingServerQueryObjectID: _, ownedCryptoId: _, invalidToken: _):
                return "PostOperationAction.retryAsSessionIsInvalid"
            case .pendingServerQueryNotFound:
                return "PostOperationAction.pendingServerQueryNotFound"
            case .cancelAsOwnedIdentityIsNotActive:
                return "PostOperationAction.cancelAsOwnedIdentityIsNotActive"
            }
        }

    }
    
    private(set) var postOperationAction: PostOperationAction?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let serverQuery = try PendingServerQuery.get(objectId: pendingServerQueryObjectID, delegateManager: delegateManager, within: obvContext) else {
                os_log("Could not find server query in database %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription)
                assertionFailure()
                return postOperationAction = .pendingServerQueryNotFound
            }
            
            let ownedCryptoId = try serverQuery.ownedIdentity
            
            switch serverQuery.queryType {
                
            case .deviceDiscovery: // ok
                
                guard let status = ObvServerDeviceDiscoveryMethod.parseObvServerResponse(responseData: responseData, using: log) else {
                    os_log("Could not parse the server response for the ObvServerDeviceDiscoveryMethod task of pending server query %{public}@", log: log, type: .error, pendingServerQueryObjectID.debugDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }

                switch status {

                case .ok(deviceUids: let deviceUids):
                    os_log("The ObvServerDeviceDiscoveryMethod returned %d device uids", log: log, type: .debug, deviceUids.count)

                    let serverResponseType = ServerResponse.ResponseType.deviceDiscovery(result: .success(deviceUIDs: deviceUids))
                    serverQuery.responseType = serverResponseType

                    return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                case .generalError:
                    os_log("Server reported general error during the ObvServerDeviceDiscoveryMethod task for pending server query %@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription)
                    
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }

            case .ownedDeviceDiscovery: // ok
                
                let result = ObvServerOwnedDeviceDiscoveryMethod.parseObvServerResponse(responseData: responseData, using: log)
                
                switch result {
                case .success(let status):
                    
                    os_log("The ObvServerOwnedDeviceDiscoveryMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                    case .ok(encryptedOwnedDeviceDiscoveryResult: let encryptedOwnedDeviceDiscoveryResult):
                        
                        let serverResponseType = ServerResponse.ResponseType.ownedDeviceDiscovery(result: .success(encryptedOwnedDeviceDiscoveryResult: encryptedOwnedDeviceDiscoveryResult))
                        serverQuery.responseType = serverResponseType

                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .generalError:
                        
                        return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    }
                    
                case .failure(let error):
                    
                    os_log("The ObvServerOwnedDeviceDiscoveryMethod failed: %{public}@", log: log, type: .fault, error.localizedDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                }
                
            case .setOwnedDeviceName(ownedDeviceUID: _, encryptedOwnedDeviceName: _, isCurrentDevice: let isCurrentDevice): // ok
                
                let result = OwnedDeviceManagementServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):

                    os_log("The OwnedDeviceManagementServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .invalidSession:
                        guard let sessionTokenUsed else {
                            assertionFailure()
                            return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                        }
                        return postOperationAction = .retryAsSessionIsInvalid(
                            pendingServerQueryObjectID: pendingServerQueryObjectID,
                            ownedCryptoId: ownedCryptoId,
                            invalidToken: sessionTokenUsed)

                    case .deviceNotRegistered:
                        // In case the device for which we are setting a new name is the current device, we try again.
                        // Otherwise, we fail
                        if isCurrentDevice {
                            return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                        } else {
                            let serverResponseType = ServerResponse.ResponseType.actionPerformedAboutOwnedDevice(success: false)
                            serverQuery.responseType = serverResponseType
                            return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)
                        }

                    case .ok:
                        
                        let serverResponseType = ServerResponse.ResponseType.actionPerformedAboutOwnedDevice(success: true)
                        serverQuery.responseType = serverResponseType
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .generalError:

                        let serverResponseType = ServerResponse.ResponseType.actionPerformedAboutOwnedDevice(success: false)
                        serverQuery.responseType = serverResponseType
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    }
                                        
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerCreateGroupBlobServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription, error.localizedDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }
                
            case .deactivateOwnedDevice(ownedDeviceUID: _, isCurrentDevice: _): // ok
                
                let result = OwnedDeviceManagementServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):

                    os_log("The OwnedDeviceManagementServerMethod (deactivateOwnedDevice) returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .invalidSession:
                        guard let sessionTokenUsed else {
                            assertionFailure()
                            return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                        }
                        return postOperationAction = .retryAsSessionIsInvalid(
                            pendingServerQueryObjectID: pendingServerQueryObjectID,
                            ownedCryptoId: ownedCryptoId,
                            invalidToken: sessionTokenUsed)

                    case .deviceNotRegistered, .ok:
                        // In case the device we are deactivating is not registered, there is nothing left to do
                        let serverResponseType = ServerResponse.ResponseType.actionPerformedAboutOwnedDevice(success: true)
                        serverQuery.responseType = serverResponseType
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .generalError:

                        let serverResponseType = ServerResponse.ResponseType.actionPerformedAboutOwnedDevice(success: false)
                        serverQuery.responseType = serverResponseType
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    }
                                        
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerCreateGroupBlobServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription, error.localizedDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }

            case .setUnexpiringOwnedDevice(ownedDeviceUID: _): // ok
                
                let result = OwnedDeviceManagementServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):

                    os_log("The OwnedDeviceManagementServerMethod (setUnexpiringOwnedDevice) returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .invalidSession:
                        guard let sessionTokenUsed else {
                            assertionFailure()
                            return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                        }
                        return postOperationAction = .retryAsSessionIsInvalid(
                            pendingServerQueryObjectID: pendingServerQueryObjectID,
                            ownedCryptoId: ownedCryptoId,
                            invalidToken: sessionTokenUsed)

                    case .deviceNotRegistered:
                        // In case the device we are deactivating is not registered, there is nothing left to
                        let serverResponseType = ServerResponse.ResponseType.actionPerformedAboutOwnedDevice(success: false)
                        serverQuery.responseType = serverResponseType
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .ok:
                        
                        let serverResponseType = ServerResponse.ResponseType.actionPerformedAboutOwnedDevice(success: true)
                        serverQuery.responseType = serverResponseType
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .generalError:

                        let serverResponseType = ServerResponse.ResponseType.actionPerformedAboutOwnedDevice(success: false)
                        serverQuery.responseType = serverResponseType
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    }
                                        
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerCreateGroupBlobServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription, error.localizedDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }

            case .putUserData: // ok

                let result = ObvServerPutUserDataMethod.parseObvServerResponse(responseData: responseData, using: log)
                
                switch result {
                case .success(let status):
                    switch status {
                    case .ok:
                        os_log("The ObvServerPutUserDataMethod returned .ok", log: log, type: .debug)
                        let serverResponseType = ServerResponse.ResponseType.putUserData
                        serverQuery.responseType = serverResponseType
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .invalidSession:
                        guard let sessionTokenUsed else {
                            assertionFailure()
                            return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                        }
                        return postOperationAction = .retryAsSessionIsInvalid(
                            pendingServerQueryObjectID: pendingServerQueryObjectID,
                            ownedCryptoId: ownedCryptoId,
                            invalidToken: sessionTokenUsed)

                    case .generalError:
                        os_log("Server reported general error during the ObvServerPutUserDataMethod task for pending server query %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription)
                        return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    }
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerPutUserDataMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription, error.localizedDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }
                
            case .getUserData(of: _, label: let label): // ok

                guard let status = ObvServerGetUserDataMethod.parseObvServerResponse(responseData: responseData, using: log, downloadedUserData: downloadedUserData, serverLabel: label) else {
                    os_log("Could not parse the server response for the ObvServerGetUserDataMethod task of pending server query %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }

                switch status {
                    
                case .generalError:
                    os_log("Server reported general error during the ObvServerGetUserDataMethod task for pending server query %@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                case .ok(userDataFilename: let userDataFilename):
                    os_log("The ObvServerGetUserDataMethod returned .ok", log: log, type: .debug)

                    let serverResponseType = ServerResponse.ResponseType.getUserData(result: .downloaded(userDataFilename: userDataFilename))
                    serverQuery.responseType = serverResponseType
                    return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                case .deletedFromServer:
                    
                    os_log("Server reported deleted form server data during the ObvServerGetUserDataMethod task for pending server query %@", log: log, type: .info, pendingServerQueryObjectID.debugDescription)
                    
                    let serverResponseType = ServerResponse.ResponseType.getUserData(result: .deletedFromServer)
                    serverQuery.responseType = serverResponseType
                    return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                }
                
            case .checkKeycloakRevocation: // ok

                guard let status = ObvServerCheckKeycloakRevocationMethod.parseObvServerResponse(responseData: responseData, using: log) else {
                    os_log("Could not parse the server response for the ObvServerCheckKeycloakRevocationMethod task of pending server query %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }

                switch status {
                case .ok(verificationSuccessful: let verificationSuccessful):
                    os_log("The ObvServerCheckKeycloakRevocationMethod returned .ok", log: log, type: .debug)

                    let serverResponseType = ServerResponse.ResponseType.checkKeycloakRevocation(verificationSuccessful: verificationSuccessful)
                    serverQuery.responseType = serverResponseType
                    return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                case .generalError:
                    os_log("Server reported general error during the ObvServerCheckKeycloakRevocationMethod task for pending server query %@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }

            case .createGroupBlob: // ok
                
                let result = ObvServerCreateGroupBlobServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):

                    os_log("The ObvServerCreateGroupBlobServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .generalError:
                        return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .invalidSession:
                        guard let sessionTokenUsed else {
                            assertionFailure()
                            return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                        }
                        return postOperationAction = .retryAsSessionIsInvalid(
                            pendingServerQueryObjectID: pendingServerQueryObjectID,
                            ownedCryptoId: ownedCryptoId,
                            invalidToken: sessionTokenUsed)

                    case .ok:
                        serverQuery.responseType = .createGroupBlob(uploadResult: .success)
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .groupUIDAlreadyUsed:
                        serverQuery.responseType = .createGroupBlob(uploadResult: .permanentFailure)
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    }
                    
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerCreateGroupBlobServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription, error.localizedDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }

            case .getGroupBlob: // ok
                
                let result = ObvServerGetGroupBlobServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):

                    os_log("The ObvServerGetGroupBlobServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .groupIsLocked, .generalError:
                        return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .ok(encryptedBlob: let encryptedBlob, logItems: let logItems, adminPublicKey: let adminPublicKey):
                        serverQuery.responseType = .getGroupBlob(result: .blobDownloaded(
                            encryptedServerBlob: encryptedBlob,
                            logEntries: logItems,
                            groupAdminPublicKey: adminPublicKey))
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .deletedFromServer:
                        serverQuery.responseType = .getGroupBlob(result: .blobWasDeletedFromServer)
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    }

                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerGetGroupBlobServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription, error.localizedDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }
                
            case .deleteGroupBlob: // ok
                
                let result = ObvServerDeleteGroupBlobServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):
                    
                    os_log("The ObvServerDeleteGroupBlobServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .ok:
                        serverQuery.responseType = .deleteGroupBlob(groupDeletionWasSuccessful: true)
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .invalidSignature:
                        serverQuery.responseType = .deleteGroupBlob(groupDeletionWasSuccessful: false)
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)
                        
                    case .generalError, .groupIsLocked:
                        return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    }

                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerDeleteGroupBlobServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription, error.localizedDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }

            case .putGroupLog: // ok
                
                let result = ObvServerPutGroupLogServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):
                    
                    os_log("The ObvServerPutGroupLogServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .generalError, .groupIsLocked:
                        return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .ok, .deletedFromServer:
                        serverQuery.responseType = .putGroupLog
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    }
                    
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerPutGroupLogServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription, error.localizedDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }

            case .requestGroupBlobLock: // ok
                
                let result = ObvServerGroupBlobLockServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):
                    
                    os_log("The ObvServerGroupBlobLockServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                    
                    case .generalError, .groupIsLocked:
                        return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .ok(let encryptedBlob, let logItems, let adminPublicKey):
                        serverQuery.responseType = .requestGroupBlobLock(result: .lockObtained(
                            encryptedServerBlob: encryptedBlob,
                            logEntries: logItems,
                            groupAdminPublicKey: adminPublicKey))
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .deletedFromServer, .invalidSignature:
                        serverQuery.responseType = .requestGroupBlobLock(result: .permanentFailure)
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    }
                    
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerGroupBlobLockServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription, error.localizedDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                }

            case .updateGroupBlob: // ok
                
                let result = ObvServerGroupBlobUpdateServerMethod.parseObvServerResponse(responseData: responseData, using: log)

                switch result {
                case .success(let status):
                    
                    os_log("The ObvServerGroupBlobUpdateServerMethod returned status is %{public}@", log: log, type: .debug, String(reflecting: status))

                    switch status {
                        
                    case .generalError, .groupIsLocked:
                        return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .ok:
                        serverQuery.responseType = .updateGroupBlob(uploadResult: .success)
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .deletedFromServer, .invalidSignature:
                        serverQuery.responseType = .updateGroupBlob(uploadResult: .permanentFailure)
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    case .groupNotLocked:
                        serverQuery.responseType = .updateGroupBlob(uploadResult: .temporaryFailure)
                        return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                    }
                    
                case .failure(let error):
                    os_log("Could not parse the server response for the ObvServerGroupBlobUpdateServerMethod task of pending server query %{public}@: %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription, error.localizedDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                }

            case .getKeycloakData(serverURL: _, serverLabel: let serverLabel): // ok

                guard let status = GetKeycloakDataServerMethod.parseObvServerResponse(responseData: responseData, using: log, downloadedUserData: downloadedUserData, serverLabel: serverLabel) else {
                    assertionFailure()
                    os_log("Could not parse the server response for the GetKeycloakDataServerMethod task of pending server query %{public}@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)
                }

                switch status {
                    
                case .generalError:
                    os_log("Server reported general error during the GetKeycloakDataServerMethod task for pending server query %@", log: log, type: .fault, pendingServerQueryObjectID.debugDescription)
                    return postOperationAction = .retryLater(pendingServerQueryObjectID: pendingServerQueryObjectID)

                case .ok(userDataFilename: let userDataFilename):
                    os_log("The GetKeycloakDataServerMethod returned .ok", log: log, type: .debug)
                    serverQuery.responseType = .getKeycloakData(result: .downloaded(userDataFilename: userDataFilename))
                    return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                case .deletedFromServer:
                    os_log("Server reported deleted form server data during the ObvServerGetUserDataMethod task for pending server query %@", log: log, type: .info, pendingServerQueryObjectID.debugDescription)
                    serverQuery.responseType = .getKeycloakData(result: .deletedFromServer)
                    return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)

                }
                
            case .sourceGetSessionNumber, .sourceWaitForTargetConnection, .targetSendEphemeralIdentity, .transferRelay, .transferWait, .closeWebsocketConnection:
                
                assertionFailure("This case should never happen as this type of server query is handled by the ServerQueryWebSocketCoordinator")
                return postOperationAction = .shouldBeProcessedByServerQueryWebSocketCoordinator

            }
            

            
        } catch {
            assertionFailure()
            postOperationAction = nil
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

}
