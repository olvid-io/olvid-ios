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
import ObvUIGroupV1
import ObvUIGroupSharedBetweenV1AndV2
import ObvTypes
import OlvidUtils
import ObvUICoreData
import ObvDesignSystem


protocol SingleGroupV1MainViewAppDataSourceDelegate: AnyObject {
    func getAsyncStreamOfJoinedGroupV1Details(_ dataSource: SingleGroupV1MainViewAppDataSource, groupIdentifier: ObvGroupV1Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupTrustedAndPublishedDetails>)
    func finishAsyncStreamOfJoinedGroupV1Details(_ dataSource: SingleGroupV1MainViewAppDataSource, streamUUID: UUID)
}



final class SingleGroupV1MainViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    private weak var delegate: SingleGroupV1MainViewAppDataSourceDelegate?

    private var singleGroupV1MainViewModelOrNotFoundStreamManagerForStreamUUID = [UUID: SingleGroupV1MainViewModelOrNotFoundStreamManager]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext, delegate: SingleGroupV1MainViewAppDataSourceDelegate) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.delegate = delegate
    }
 
    enum ObvError: Error {
        case couldNotFetchGroup
        case delegateIsNil
    }

}


extension SingleGroupV1MainViewAppDataSource: SingleGroupV1MainViewDataSource {
    
    func getAsyncSequenceOfSingleGroupV1MainViewModel(_ view: SingleGroupV1MainView, groupIdentifier: ObvGroupV1Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV1MainViewModelOrNotFound>) {
        let streamManager = SingleGroupV1MainViewModelOrNotFoundStreamManager(groupIdentifier: groupIdentifier, context: backgroundContext, delegate: self)
        let (streamUUID, stream) = try await streamManager.startStream()
        self.singleGroupV1MainViewModelOrNotFoundStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    func finishAsyncSequenceOfSingleGroupV1MainViewModel(_ view: SingleGroupV1MainView, streamUUID: UUID) {
        guard let streamManager = singleGroupV1MainViewModelOrNotFoundStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }
    
}


extension SingleGroupV1MainViewAppDataSource: SingleGroupV1MainViewModelOrNotFoundStreamManagerDelegate {
    
    fileprivate func getAsyncStreamOfJoinedGroupV1Details(_ streamManager: SingleGroupV1MainViewModelOrNotFoundStreamManager, groupIdentifier: ObvGroupV1Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupTrustedAndPublishedDetails>) {
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        return try await delegate.getAsyncStreamOfJoinedGroupV1Details(self, groupIdentifier: groupIdentifier)
    }
    
    fileprivate func finishAsyncStreamOfJoinedGroupV1Details(_ streamManager: SingleGroupV1MainViewModelOrNotFoundStreamManager, streamUUID: UUID) {
        guard let delegate else { assertionFailure(); return }
        delegate.finishAsyncStreamOfJoinedGroupV1Details(self, streamUUID: streamUUID)
    }
        
}


private protocol SingleGroupV1MainViewModelOrNotFoundStreamManagerDelegate: AnyObject {
    func getAsyncStreamOfJoinedGroupV1Details(_ streamManager: SingleGroupV1MainViewAppDataSource.SingleGroupV1MainViewModelOrNotFoundStreamManager, groupIdentifier: ObvGroupV1Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupTrustedAndPublishedDetails>)
    func finishAsyncStreamOfJoinedGroupV1Details(_ streamManager: SingleGroupV1MainViewAppDataSource.SingleGroupV1MainViewModelOrNotFoundStreamManager, streamUUID: UUID)
}

extension SingleGroupV1MainViewAppDataSource {
    
    fileprivate final class SingleGroupV1MainViewModelOrNotFoundStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvUIGroupV1.SingleGroupV1MainViewModelOrNotFound, PersistedContactGroup>, @unchecked Sendable {
        
        private let groupIdentifier: ObvTypes.ObvGroupV1Identifier
        private weak var delegate: SingleGroupV1MainViewModelOrNotFoundStreamManagerDelegate?
        private var groupTrustedAndPublishedDetails: ObvGroupTrustedAndPublishedDetails? // Only for joined groups, nil for owned groups
        private var engineStreamUUID: UUID?

        init(groupIdentifier: ObvTypes.ObvGroupV1Identifier, context: NSManagedObjectContext, delegate: SingleGroupV1MainViewModelOrNotFoundStreamManagerDelegate) {
            self.groupIdentifier = groupIdentifier
            self.delegate = delegate
            let frc = PersistedContactGroup.getFetchedResultsController(groupV1Identifier: groupIdentifier, within: context)
            super.init(frc: frc)
        }
        
        override func startStream() async throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV1MainViewModelOrNotFound>) {
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
                let (engineStreamUUID, streamFromEngine) = try await delegate.getAsyncStreamOfJoinedGroupV1Details(self, groupIdentifier: groupIdentifier)
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
        
        override func createModel(fetchedObjects: [PersistedContactGroup]) throws -> SingleGroupV1MainViewModelOrNotFound {

            guard let group = fetchedObjects.first else {
                return .groupNotFound
            }
            
            let model = try SingleGroupV1MainView.Model(group: group, groupTrustedAndPublishedDetails: groupTrustedAndPublishedDetails)
            return .model(model: model)
            
        }
                
        enum ObvError: Error {
            case couldNotFindGroup
            case delegateIsNil
        }
        
    }
    
}


// MARK: - SingleGroupV1MainView.Model from a PersistedContactGroup

extension SingleGroupV1MainView.Model {
    
    init(group: PersistedContactGroup, groupTrustedAndPublishedDetails: ObvGroupTrustedAndPublishedDetails?) throws {
        
        let nickname: String?
        let customPhotoURL: URL?
        let ownedIdentityIsAdmin: Bool
        if let groupJoined = group as? PersistedContactGroupJoined {
            nickname = groupJoined.groupNameCustom
            customPhotoURL = groupJoined.customPhotoURL
            ownedIdentityIsAdmin = false
        } else if group is PersistedContactGroupOwned {
            nickname = nil
            customPhotoURL = nil
            ownedIdentityIsAdmin = true
        } else {
            assertionFailure()
            throw ObvSingleGroupV1MainViewModelError.unexpectedPersistedContactGroupType
        }
        
        let publishedDetailsForValidation: PublishedDetailsValidationViewModel?
        switch (groupTrustedAndPublishedDetails?.trustedDetails, groupTrustedAndPublishedDetails?.publishedDetails) {
        case (.some(let trustedDetails), .some(let publishedDetails)):
            var differences = DifferencesBetweenTrustedAndPublished()
            if publishedDetails.coreDetails.name != trustedDetails.coreDetails.name {
                differences.insert(.name)
            }
            if publishedDetails.coreDetails.description != trustedDetails.coreDetails.description {
                differences.insert(.description)
            }
            if !publishedDetails.hasIdenticalPhoto(than: trustedDetails) {
                differences.insert(.photo)
            }
            if differences.isEmpty {
                publishedDetailsForValidation = nil
            } else {
                publishedDetailsForValidation = .init(
                    groupIdentifier: .groupV1(try group.obvGroupIdentifier),
                    publishedName: publishedDetails.coreDetails.name,
                    publishedDescription: publishedDetails.coreDetails.description,
                    publishedPhotoURL: publishedDetails.photoURL,
                    circleColors: .init(background: group.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                        foreground: group.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                    differences: differences,
                    isKeycloakManaged: false)
            }
        default:
            // This is the only applicable case for an owned group
            publishedDetailsForValidation = nil
        }
        
        let trustedDescription: String? = groupTrustedAndPublishedDetails?.trustedDetails.coreDetails.description
        
        self.init(groupIdentifier: try group.obvGroupIdentifier,
                  trustedName: group.groupNameSanitizedOrDefaultName,
                  trustedDescription: trustedDescription,
                  circleColors: .init(background: group.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                      foreground: group.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  nickname: nickname,
                  trustedPhotoURL: group.photoURL,
                  customPhotoURL: customPhotoURL,
                  personalNote: group.note,
                  publishedDetailsForValidation: publishedDetailsForValidation,
                  ownedIdentityIsAdmin: ownedIdentityIsAdmin)
    }
    
    enum ObvSingleGroupV1MainViewModelError: Error {
        case unexpectedPersistedContactGroupType
    }
    
}
