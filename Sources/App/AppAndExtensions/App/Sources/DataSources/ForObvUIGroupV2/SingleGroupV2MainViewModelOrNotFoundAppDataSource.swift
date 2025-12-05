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
import ObvUIGroupV2
import ObvUIGroupSharedBetweenV1AndV2
import ObvTypes
import ObvAppTypes
import ObvUICoreData
import ObvDesignSystem
import OlvidUtils

/// This App Data Source is used by multiples views, including
/// - `ObvUIGroupV2.EditGroupNameAndPictureView`,
/// - `ObvUIGroupV2.EditGroupTypeView`
/// - `ObvUIGroupV2.SingleGroupV2MainView`
/// and more.
@MainActor
final class SingleGroupV2MainViewModelOrNotFoundAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var singleGroupV2MainViewModelStreamManagerForStreamUUID = [UUID: SingleGroupV2MainViewModelStreamManager]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
 
    enum ObvError: Error {
        case couldNotFetchGroup
    }
    
}



extension SingleGroupV2MainViewModelOrNotFoundAppDataSource: EditGroupTypeViewDataSource {
    
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: ObvUIGroupV2.EditGroupTypeView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.SingleGroupV2MainViewModelOrNotFound>) {
        return try await self.getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: groupIdentifier)
    }
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: ObvUIGroupV2.EditGroupTypeView, streamUUID: UUID) {
        self.finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: streamUUID)
    }

}


extension SingleGroupV2MainViewModelOrNotFoundAppDataSource: SingleGroupV2MainViewDataSource {
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: ObvUIGroupV2.SingleGroupV2MainView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.SingleGroupV2MainViewModelOrNotFound>) {
        return try await self.getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: groupIdentifier)
    }
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: ObvUIGroupV2.SingleGroupV2MainView, streamUUID: UUID) {
        self.finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: streamUUID)
    }
    
}


// MARK: - Private helper

extension SingleGroupV2MainViewModelOrNotFoundAppDataSource {
    
    func getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.SingleGroupV2MainViewModelOrNotFound>) {
        let streamManager = SingleGroupV2MainViewModelStreamManager(groupV2Identifier: groupIdentifier, context: backgroundContext)
        let (streamUUID, stream) = try await streamManager.startStream()
        self.singleGroupV2MainViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: UUID) {
        guard let streamManager = singleGroupV2MainViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }

}

// MARK: - Stream Manager for SingleGroupV2MainViewModelOrNotFound

extension SingleGroupV2MainViewModelOrNotFoundAppDataSource {
    
    private final class SingleGroupV2MainViewModelStreamManager: ObvDataSourceStreamManagerWithThreeFetchedResultsController<ObvUIGroupV2.SingleGroupV2MainViewModelOrNotFound, PersistedGroupV2, PersistedGroupV2Details, PersistedGroupV2Details>, @unchecked Sendable {
        
        init(groupV2Identifier: ObvGroupV2Identifier, context: NSManagedObjectContext) {
            let frcForPersistedGroupV2 = PersistedGroupV2.getFetchedResultsController(groupV2Identifier: groupV2Identifier, within: context)
            let frcForGroupTrustedDetails = PersistedGroupV2Details.getFetchedResultsControllerForTrustedDetails(groupV2Identifier: groupV2Identifier, within: context)
            let frcForGroupPublishedDetails = PersistedGroupV2Details.getFetchedResultsControllerForPublishedDetails(groupV2Identifier: groupV2Identifier, within: context)
            super.init(frc1: frcForPersistedGroupV2, frc2: frcForGroupTrustedDetails, frc3: frcForGroupPublishedDetails)
        }
        
        override func createModel(fetchedObjects1: [PersistedGroupV2], fetchedObjects2: [PersistedGroupV2Details], fetchedObjects3: [PersistedGroupV2Details]) throws -> SingleGroupV2MainViewModelOrNotFound {
            let fetchedObjects = fetchedObjects1
            assert(fetchedObjects.count <= 1)
            guard let persistedGroup = fetchedObjects.first else {
                return .groupNotFound
            }
            let model = try ObvUIGroupV2.SingleGroupV2MainViewModel(with: persistedGroup)
            return .model(model: model)
        }
        
    }
        
}


// MARK: SingleGroupV2MainViewModel from a PersistedGroupV2

extension SingleGroupV2MainViewModel {
    
    init(with persistedGroup: PersistedGroupV2) throws {

        let ownedIdentityCanLeaveGroup: SingleGroupV2MainViewModel.CanLeaveGroup
        switch persistedGroup.ownedIdentityCanLeaveGroup {
        case .canLeaveGroup:
            ownedIdentityCanLeaveGroup = .canLeaveGroup
        case .cannotLeaveGroupAsThisIsKeycloakGroup:
            ownedIdentityCanLeaveGroup = .cannotLeaveGroupAsThisIsKeycloakGroup
        case .cannotLeaveGroupAsWeAreTheOnlyAdmin:
            ownedIdentityCanLeaveGroup = .cannotLeaveGroupAsWeAreTheOnlyAdmin
        }

        let publishedDetailsForValidation: PublishedDetailsValidationViewModel?
        if let detailsPublished = persistedGroup.detailsPublished {
            var differences = DifferencesBetweenTrustedAndPublished()
            if persistedGroup.detailsPublished?.name != persistedGroup.detailsTrusted?.name {
                differences.insert(.name)
            }
            if persistedGroup.detailsPublished?.groupDescription != persistedGroup.detailsTrusted?.groupDescription {
                differences.insert(.description)
            }
            switch (persistedGroup.detailsPublished?.photoURLFromEngine, persistedGroup.detailsTrusted?.photoURLFromEngine) {
            case (nil, nil):
                break
            case (.some, nil), (nil, .some):
                differences.insert(.photo)
            case (.some(let publishedURL), .some(let trustedURL)):
                if publishedURL != trustedURL && !FileManager.default.contentsEqual(atPath: publishedURL.path, andPath: trustedURL.path) {
                    differences.insert(.photo)
                }
            }
            if differences.isEmpty {
                publishedDetailsForValidation = nil
            } else {
                publishedDetailsForValidation = .init(groupIdentifier: .groupV2(try persistedGroup.obvGroupIdentifier),
                                                      publishedName: detailsPublished.name ?? persistedGroup.displayName,
                                                      publishedDescription: detailsPublished.groupDescription,
                                                      publishedPhotoURL: detailsPublished.photoURLFromEngine,
                                                      circleColors: .init(background: persistedGroup.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                                                          foreground: persistedGroup.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                                                      differences: differences,
                                                      isKeycloakManaged: persistedGroup.keycloakManaged)
            }
        } else {
            publishedDetailsForValidation = nil
        }

        self.init(groupIdentifier: try persistedGroup.obvGroupIdentifier,
                  trustedName: persistedGroup.displayName,
                  trustedDescription: persistedGroup.trustedDescription,
                  trustedPhotoURL: persistedGroup.trustedPhotoURL,
                  customPhotoURL: persistedGroup.customPhotoURL,
                  nickname: persistedGroup.customNameSanitized,
                  isKeycloakManaged: persistedGroup.keycloakManaged,
                  circleColors: .init(background: persistedGroup.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                      foreground: persistedGroup.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  updateInProgress: persistedGroup.updateInProgress,
                  ownedIdentityIsAdmin: persistedGroup.ownedIdentityIsAdmin,
                  ownedIdentityCanLeaveGroup: ownedIdentityCanLeaveGroup,
                  publishedDetailsForValidation: publishedDetailsForValidation,
                  personalNote: persistedGroup.personalNote,
                  groupType: persistedGroup.getOrInferGroupType())
    }

}
