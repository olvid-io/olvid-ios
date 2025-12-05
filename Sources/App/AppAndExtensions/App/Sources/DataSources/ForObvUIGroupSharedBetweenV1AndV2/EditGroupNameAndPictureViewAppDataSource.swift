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


protocol EditGroupNameAndPictureViewAppDataSourceDelegate: AnyObject {
    func getAsyncStreamOfJoinedGroupV1Details(_ dataSource: EditGroupNameAndPictureViewAppDataSource, groupIdentifier: ObvGroupV1Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupTrustedAndPublishedDetails>)
    func finishAsyncStreamOfJoinedGroupV1Details(_ dataSource: EditGroupNameAndPictureViewAppDataSource, streamUUID: UUID)
}


final class EditGroupNameAndPictureViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    private weak var delegate: EditGroupNameAndPictureViewAppDataSourceDelegate?

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext, delegate: EditGroupNameAndPictureViewAppDataSourceDelegate) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.delegate = delegate
    }
 
    private var editGroupNameAndPictureViewModelStreamManagerForGroupV1ForStreamUUID = [UUID: EditGroupNameAndPictureViewModelStreamManagerForGroupV1]()
    private var editGroupNameAndPictureViewModelStreamManagerForGroupV2ForStreamUUID = [UUID: EditGroupNameAndPictureViewModelStreamManagerForGroupV2]()

    enum ObvError: Error {
        case couldNotFetchGroup
        case delegateIsNil
    }

}


extension EditGroupNameAndPictureViewAppDataSource: EditGroupNameAndPictureViewDataSource {
    
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupNameAndPictureView, groupIdentifier: ObvGroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<EditGroupNameAndPictureView.ModelOrNotFound>) {
        switch groupIdentifier {
        case .groupV1(let groupV1Identifier):
            let streamManager = EditGroupNameAndPictureViewModelStreamManagerForGroupV1(groupV1Identifier: groupV1Identifier, context: backgroundContext, delegate: self)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.editGroupNameAndPictureViewModelStreamManagerForGroupV1ForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        case .groupV2(let groupIdentifier):
            let streamManager = EditGroupNameAndPictureViewModelStreamManagerForGroupV2(groupV2Identifier: groupIdentifier, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.editGroupNameAndPictureViewModelStreamManagerForGroupV2ForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        }
    }
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupNameAndPictureView, streamUUID: UUID) {
        if let streamManager = editGroupNameAndPictureViewModelStreamManagerForGroupV1ForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
        if let streamManager = editGroupNameAndPictureViewModelStreamManagerForGroupV2ForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}


extension EditGroupNameAndPictureViewAppDataSource: EditGroupNameAndPictureViewModelStreamManagerForGroupV1Delegate {
    
    fileprivate func getAsyncStreamOfJoinedGroupV1Details(_ streamManager: EditGroupNameAndPictureViewModelStreamManagerForGroupV1, groupIdentifier: ObvTypes.ObvGroupV1Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvTypes.ObvGroupTrustedAndPublishedDetails>) {
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        return try await delegate.getAsyncStreamOfJoinedGroupV1Details(self, groupIdentifier: groupIdentifier)
    }
    
    fileprivate func finishAsyncStreamOfJoinedGroupV1Details(_ streamManager: EditGroupNameAndPictureViewModelStreamManagerForGroupV1, streamUUID: UUID) {
        guard let delegate else { assertionFailure(); return }
        delegate.finishAsyncStreamOfJoinedGroupV1Details(self, streamUUID: streamUUID)
    }
    
}


private protocol EditGroupNameAndPictureViewModelStreamManagerForGroupV1Delegate: AnyObject {
    func getAsyncStreamOfJoinedGroupV1Details(_ streamManager: EditGroupNameAndPictureViewAppDataSource.EditGroupNameAndPictureViewModelStreamManagerForGroupV1, groupIdentifier: ObvGroupV1Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupTrustedAndPublishedDetails>)
    func finishAsyncStreamOfJoinedGroupV1Details(_ streamManager: EditGroupNameAndPictureViewAppDataSource.EditGroupNameAndPictureViewModelStreamManagerForGroupV1, streamUUID: UUID)
}


extension EditGroupNameAndPictureViewAppDataSource {
    
    fileprivate final class EditGroupNameAndPictureViewModelStreamManagerForGroupV1: ObvDataSourceStreamManagerWithOneFetchedResultsController<EditGroupNameAndPictureView.ModelOrNotFound, PersistedContactGroup>, @unchecked Sendable {
     
        private let groupV1Identifier: ObvTypes.ObvGroupV1Identifier
        private weak var delegate: EditGroupNameAndPictureViewModelStreamManagerForGroupV1Delegate?
        private var groupTrustedAndPublishedDetails: ObvGroupTrustedAndPublishedDetails?
        private var engineStreamUUID: UUID?

        init(groupV1Identifier: ObvTypes.ObvGroupV1Identifier, context: NSManagedObjectContext, delegate: EditGroupNameAndPictureViewModelStreamManagerForGroupV1Delegate) {
            self.groupV1Identifier = groupV1Identifier
            self.delegate = delegate
            let frc = PersistedContactGroup.getFetchedResultsController(groupV1Identifier: groupV1Identifier, within: context)
            super.init(frc: frc)
        }

        override func startStream() async throws -> (streamUUID: UUID, stream: AsyncStream<EditGroupNameAndPictureView.ModelOrNotFound>) {
            let result = try await super.startStream()
            Task { await streamFromEngine() }
            return result
        }

        override func finishStream() {
            if let engineStreamUUID {
                delegate?.finishAsyncStreamOfJoinedGroupV1Details(self, streamUUID: engineStreamUUID)
            }
            super.finishStream()
        }

        private func streamFromEngine() async {
            do {
                assert(engineStreamUUID == nil)
                guard let delegate else {
                    assertionFailure()
                    throw ObvError.delegateIsNil
                }
                let (engineStreamUUID, streamFromEngine) = try await delegate.getAsyncStreamOfJoinedGroupV1Details(self, groupIdentifier: groupV1Identifier)
                self.engineStreamUUID = engineStreamUUID
                for await groupTrustedAndPublishedDetails in streamFromEngine {
                    if self.groupTrustedAndPublishedDetails != groupTrustedAndPublishedDetails {
                        self.groupTrustedAndPublishedDetails = groupTrustedAndPublishedDetails
                        do {
                            try await getFetchedObjectsAndYieldModelIfNeeded()
                        } catch {
                            assertionFailure() // Continue with next value
                        }
                    }
                }
            } catch {
                assertionFailure()
            }

        }

        override func createModel(fetchedObjects: [PersistedContactGroup]) throws -> EditGroupNameAndPictureView.ModelOrNotFound {

            guard let group = fetchedObjects.first else {
                return .groupNotFound
            }
            
            let model = try EditGroupNameAndPictureView.Model(with: group, groupTrustedAndPublishedDetails: groupTrustedAndPublishedDetails)
            return .model(model)
            
        }

        enum ObvError: Error {
            case couldNotFindGroup
            case delegateIsNil
        }

    }
    
}

extension EditGroupNameAndPictureViewAppDataSource {
    
    private final class EditGroupNameAndPictureViewModelStreamManagerForGroupV2: ObvDataSourceStreamManagerWithThreeFetchedResultsController<EditGroupNameAndPictureView.ModelOrNotFound, PersistedGroupV2, PersistedGroupV2Details, PersistedGroupV2Details>, @unchecked Sendable {
        
        init(groupV2Identifier: ObvGroupV2Identifier, context: NSManagedObjectContext) {
            let frcForPersistedGroupV2 = PersistedGroupV2.getFetchedResultsController(groupV2Identifier: groupV2Identifier, within: context)
            let frcForGroupTrustedDetails = PersistedGroupV2Details.getFetchedResultsControllerForTrustedDetails(groupV2Identifier: groupV2Identifier, within: context)
            let frcForGroupPublishedDetails = PersistedGroupV2Details.getFetchedResultsControllerForPublishedDetails(groupV2Identifier: groupV2Identifier, within: context)
            super.init(frc1: frcForPersistedGroupV2, frc2: frcForGroupTrustedDetails, frc3: frcForGroupPublishedDetails)
        }
        
        override func createModel(fetchedObjects1: [PersistedGroupV2], fetchedObjects2: [PersistedGroupV2Details], fetchedObjects3: [PersistedGroupV2Details]) throws -> EditGroupNameAndPictureView.ModelOrNotFound {
            let fetchedObjects = fetchedObjects1
            assert(fetchedObjects.count <= 1)
            guard let persistedGroup = fetchedObjects.first else {
                return .groupNotFound
            }
            let model = try EditGroupNameAndPictureView.Model(with: persistedGroup)
            return .model(model)
        }
        
    }

}


extension EditGroupNameAndPictureView.Model {
    
    init(with groupV1: PersistedContactGroup, groupTrustedAndPublishedDetails: ObvGroupTrustedAndPublishedDetails?) throws {
        
        switch groupV1.category {
        case .joined:
            throw EditGroupNameAndPictureViewModelInitError.cannotEditGroupJoinedGroup
        case .owned:
            break
        }
        
        assert(groupTrustedAndPublishedDetails?.publishedDetails == nil, "This is an owned group, there should not be published details")
        
        self.init(isKeycloakManaged: false,
                  circleColors: .init(background: groupV1.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                      foreground: groupV1.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  trustedName: groupV1.groupNameSanitized ?? "",
                  publishedDetailsForValidation: nil, // Since we are the only admin, there can't be published details for validation in an owned group v1
                  trustedDescription: groupTrustedAndPublishedDetails?.trustedDetails.coreDetails.description,
                  trustedPhotoURL: groupV1.photoURL)
        
    }
    
    enum EditGroupNameAndPictureViewModelInitError: Error {
        case cannotEditGroupJoinedGroup
    }
    
}


extension EditGroupNameAndPictureView.Model {
    
    init(with persistedGroup: PersistedGroupV2) throws {
        
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

        self.init(isKeycloakManaged: persistedGroup.keycloakManaged,
                  circleColors: .init(background: persistedGroup.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                      foreground: persistedGroup.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  trustedName: persistedGroup.displayName,
                  publishedDetailsForValidation: publishedDetailsForValidation,
                  trustedDescription: persistedGroup.trustedDescription,
                  trustedPhotoURL: persistedGroup.trustedPhotoURL)
        
    }

}
