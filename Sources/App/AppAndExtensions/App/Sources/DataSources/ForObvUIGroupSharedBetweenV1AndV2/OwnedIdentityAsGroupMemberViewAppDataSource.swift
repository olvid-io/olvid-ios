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
import CoreData
import ObvUIGroupSharedBetweenV1AndV2
import ObvTypes
import ObvAppTypes
import ObvUICoreData
import ObvDesignSystem
import OlvidUtils

@MainActor
final class OwnedIdentityAsGroupMemberViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var ownedIdentityAsGroupMemberViewModelFromGroupV1StreamManagerForStreamUUID = [UUID: OwnedIdentityAsGroupMemberViewModelFromGroupV1StreamManager]()
    private var ownedIdentityAsGroupMemberViewModelFromGroupV2StreamManagerForStreamUUID = [UUID: OwnedIdentityAsGroupMemberViewModelFromGroupV2StreamManager]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
    enum ObvError: Error {
        case couldNotFetchGroup
        case groupCannotBeFound
    }

}


extension OwnedIdentityAsGroupMemberViewAppDataSource: OwnedIdentityAsGroupMemberViewDataSource {
    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel>) {
        switch groupIdentifier {
        case .groupV1(let groupIdentifier):
            let streamManager = OwnedIdentityAsGroupMemberViewModelFromGroupV1StreamManager(groupIdentifier: groupIdentifier, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.ownedIdentityAsGroupMemberViewModelFromGroupV1StreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        case .groupV2(let groupIdentifier):
            let streamManager = OwnedIdentityAsGroupMemberViewModelFromGroupV2StreamManager(groupIdentifier: groupIdentifier, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.ownedIdentityAsGroupMemberViewModelFromGroupV2StreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        }
    }
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, streamUUID: UUID) {
        if let streamManager = ownedIdentityAsGroupMemberViewModelFromGroupV1StreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
        if let streamManager = ownedIdentityAsGroupMemberViewModelFromGroupV2StreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}


// MARK: - Stream Manager for OwnedIdentityAsGroupMemberViewModel

extension OwnedIdentityAsGroupMemberViewAppDataSource {
    
    private final class OwnedIdentityAsGroupMemberViewModelFromGroupV2StreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel, PersistedObvOwnedIdentity, PersistedGroupV2>, @unchecked Sendable {
        
        init(groupIdentifier: ObvGroupV2Identifier, context: NSManagedObjectContext) {
            let frcForPersistedObvOwnedIdentity = PersistedObvOwnedIdentity.getFetchedResultsController(ownedCryptoId: groupIdentifier.ownedCryptoId, within: context)
            let frcForPersistedGroupV2 = PersistedGroupV2.getFetchedResultsController(groupV2Identifier: groupIdentifier, within: context)
            super.init(frc1: frcForPersistedObvOwnedIdentity, frc2: frcForPersistedGroupV2)
        }
        
        override func createModel(fetchedObjects1: [PersistedObvOwnedIdentity], fetchedObjects2: [PersistedGroupV2]) throws -> OwnedIdentityAsGroupMemberViewModel {
            guard let persistedGroup = fetchedObjects2.first else {
                // This happens when leaving a group
                throw ObvError.groupCannotBeFound
            }
            let model = try ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel(persistedGroup: persistedGroup)
            return model
        }
        
    }

    private final class OwnedIdentityAsGroupMemberViewModelFromGroupV1StreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel, PersistedObvOwnedIdentity, PersistedContactGroup>, @unchecked Sendable {
        
        init(groupIdentifier: ObvGroupV1Identifier, context: NSManagedObjectContext) {
            let frcForPersistedObvOwnedIdentity = PersistedObvOwnedIdentity.getFetchedResultsController(ownedCryptoId: groupIdentifier.ownedCryptoId, within: context)
            let frcForPersistedGroupV1 = PersistedContactGroup.getFetchedResultsController(groupV1Identifier: groupIdentifier, within: context)
            super.init(frc1: frcForPersistedObvOwnedIdentity, frc2: frcForPersistedGroupV1)
        }
        
        override func createModel(fetchedObjects1: [PersistedObvOwnedIdentity], fetchedObjects2: [PersistedContactGroup]) throws -> OwnedIdentityAsGroupMemberViewModel {
            guard let persistedGroup = fetchedObjects2.first else {
                // This happens when leaving a group
                throw ObvError.groupCannotBeFound
            }
            let model = try ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel(persistedGroup: persistedGroup)
            return model
        }
        
    }

}


// MARK: - ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel from PersistedGroupV2 (and associated owned identity)

extension ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel {
    
    init(persistedGroup: PersistedGroupV2) throws {
        
        guard let ownedIdentity = persistedGroup.persistedOwnedIdentity else {
            // This happens when leaving a group
            throw ObvErrorForInitBasedOnPersistedGroupV2.persistedOwnedIdentityMissing
        }
        
        self.init(ownedCryptoId: ownedIdentity.ownedCryptoId,
                  isKeycloakManaged: ownedIdentity.isKeycloakManaged,
                  profilePictureInitial: ownedIdentity.circledInitialsConfiguration.initials?.text,
                  circleColors: .init(background: ownedIdentity.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                      foreground: ownedIdentity.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  identityDetails: ownedIdentity.identityDetails,
                  isAdmin: persistedGroup.ownPermissions.contains(.groupAdmin),
                  customDisplayName: ownedIdentity.customDisplayName,
                  customPhotoURL: nil)
    }
    
    enum ObvErrorForInitBasedOnPersistedGroupV2: Error {
        case persistedOwnedIdentityMissing
    }
    
}

// MARK: - ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel from PersistedContactGroup (and associated owned identity)

extension ObvUIGroupSharedBetweenV1AndV2.OwnedIdentityAsGroupMemberViewModel {
    
    init(persistedGroup: PersistedContactGroup) throws {
        
        guard let ownedIdentity = persistedGroup.ownedIdentity else {
            // This happens when leaving a group
            throw ObvErrorForInitBasedOnPersistedGroupV1.persistedOwnedIdentityMissing
        }
        
        let isAdmin: Bool
        if persistedGroup is PersistedContactGroupOwned {
            isAdmin = true
        } else if persistedGroup is PersistedContactGroupJoined {
            isAdmin = false
        } else {
            assertionFailure()
            throw ObvErrorForInitBasedOnPersistedGroupV1.unexpectedGroupType
        }
        
        self.init(ownedCryptoId: ownedIdentity.ownedCryptoId,
                  isKeycloakManaged: ownedIdentity.isKeycloakManaged,
                  profilePictureInitial: ownedIdentity.circledInitialsConfiguration.initials?.text,
                  circleColors: .init(background: ownedIdentity.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                      foreground: ownedIdentity.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  identityDetails: ownedIdentity.identityDetails,
                  isAdmin: isAdmin,
                  customDisplayName: ownedIdentity.customDisplayName,
                  customPhotoURL: nil)
    }
    
    enum ObvErrorForInitBasedOnPersistedGroupV1: Error {
        case persistedOwnedIdentityMissing
        case unexpectedGroupType
    }
    
}
