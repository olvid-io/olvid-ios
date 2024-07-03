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
import CoreData
import OlvidUtils
import ObvMetaManager


/// Called when a ``PendingServerQuery`` failed to be processed. Sometimes, we want to set the failure response without condition (e.g., when the server indicated that the server query payload is too large)
/// sometimes we want to fail only if the server query failed to be processed for more than 2 weeks.
final class SetFailureResponseOnPendingServerQueryIfAppropriate: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    enum Condition {
        case none
        case ifServerQueryIsTooOld
    }
    
    private let pendingServerQueryObjectID: NSManagedObjectID
    private let condition: Condition
    private let delegateManager: ObvNetworkFetchDelegateManager
    
    init(pendingServerQueryObjectID: NSManagedObjectID, condition: Condition, delegateManager: ObvNetworkFetchDelegateManager) {
        self.pendingServerQueryObjectID = pendingServerQueryObjectID
        self.condition = condition
        self.delegateManager = delegateManager
        super.init()
    }
    
    enum PostOperationAction: CustomDebugStringConvertible, Hashable {
        case postResponseAndDeleteServerQuery(pendingServerQueryObjectID: NSManagedObjectID)
        case shouldBeProcessedByServerQueryWebSocketCoordinator
        case doNothingAsPendingServerQueryCannotBeFound
        case retryLater
        
        var debugDescription: String {
            switch self {
            case .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: let pendingServerQueryObjectID):
                return "PostOperationAction.postResponseAndDeleteServerQuery<\(pendingServerQueryObjectID.debugDescription)>"
            case .shouldBeProcessedByServerQueryWebSocketCoordinator:
                return "PostOperationAction.shouldBeProcessedByServerQueryWebSocketCoordinator"
            case .doNothingAsPendingServerQueryCannotBeFound:
                return "PostOperationAction.doNothingAsPendingServerQueryCannotBeFound"
            case .retryLater:
                return "PostOperationAction.retryLater"
            }
        }

    }

    private(set) var postOperationAction: PostOperationAction?

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let serverQuery = try PendingServerQuery.get(objectId: pendingServerQueryObjectID, delegateManager: delegateManager, within: obvContext) else {
                return postOperationAction = .doNothingAsPendingServerQueryCannotBeFound
            }
            
            switch condition {
            case .none:
                // Fail and delete the server query now
                break
            case .ifServerQueryIsTooOld:
                // Check if the server query is old enough
                guard abs(serverQuery.creationDate.timeIntervalSinceNow) > ObvConstants.ServerQueryExpirationDelay else {
                    return postOperationAction = .retryLater
                }
            }
            
            // If we reach this point, we choose an appropriate "fail" response for the server query
            
            switch serverQuery.queryType {
                
            case .deviceDiscovery:
                let serverResponseType = ServerResponse.ResponseType.deviceDiscovery(result: .failure)
                serverQuery.responseType = serverResponseType
                
            case .putUserData:
                let serverResponseType = ServerResponse.ResponseType.putUserData
                serverQuery.responseType = serverResponseType

            case .getUserData:
                let serverResponseType = ServerResponse.ResponseType.getUserData(result: .deletedFromServer)
                serverQuery.responseType = serverResponseType
                
            case .checkKeycloakRevocation:
                // Consider the user is not revoked (rationale: another protocol has probably been run since then, we do not want to delete the user)
                let serverResponseType = ServerResponse.ResponseType.checkKeycloakRevocation(verificationSuccessful: true)
                serverQuery.responseType = serverResponseType

            case .createGroupBlob:
                serverQuery.responseType = .createGroupBlob(uploadResult: .permanentFailure)

            case .getGroupBlob:
                serverQuery.responseType = .getGroupBlob(result: .blobCouldNotBeDownloaded)

            case .deleteGroupBlob:
                serverQuery.responseType = .deleteGroupBlob(groupDeletionWasSuccessful: false)

            case .putGroupLog:
                serverQuery.responseType = .putGroupLog

            case .requestGroupBlobLock:
                serverQuery.responseType = .requestGroupBlobLock(result: .permanentFailure)

            case .updateGroupBlob:
                serverQuery.responseType = .updateGroupBlob(uploadResult: .permanentFailure)

            case .getKeycloakData:
                serverQuery.responseType = .getKeycloakData(result: .deletedFromServer)

            case .ownedDeviceDiscovery:
                let serverResponseType = ServerResponse.ResponseType.ownedDeviceDiscovery(result: .failure)
                serverQuery.responseType = serverResponseType

            case .setOwnedDeviceName:
                let serverResponseType = ServerResponse.ResponseType.actionPerformedAboutOwnedDevice(success: false)
                serverQuery.responseType = serverResponseType

            case .deactivateOwnedDevice:
                let serverResponseType = ServerResponse.ResponseType.actionPerformedAboutOwnedDevice(success: false)
                serverQuery.responseType = serverResponseType

            case .setUnexpiringOwnedDevice:
                let serverResponseType = ServerResponse.ResponseType.actionPerformedAboutOwnedDevice(success: false)
                serverQuery.responseType = serverResponseType
                
            case .uploadPreKeyForCurrentDevice:
                let serverResponseType = ServerResponse.ResponseType.uploadPreKeyForCurrentDevice(result: .permanentFailure)
                serverQuery.responseType = serverResponseType

            case .sourceGetSessionNumber, .sourceWaitForTargetConnection, .targetSendEphemeralIdentity, .transferRelay, .transferWait, .closeWebsocketConnection:
                assertionFailure("This case should never happen as this type of server query is handled by the ServerQueryWebSocketCoordinator")
                return postOperationAction = .shouldBeProcessedByServerQueryWebSocketCoordinator

            }
            
            return postOperationAction = .postResponseAndDeleteServerQuery(pendingServerQueryObjectID: pendingServerQueryObjectID)
                        
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
