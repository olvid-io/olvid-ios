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
import Combine
import CoreData
import ObvDiscussionsList
import ObvDesignSystem
import ObvTypes
import ObvUICoreData
import ObvProfilePictureBarButtonItem
import OlvidUtils
import ObvSystemIcon
import ObvOwnedIdentityChooser



/// This data source is used when displaying the main list of recent discussions.
@MainActor
final class ObvDiscussionsListViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var discussionsListViewModelStreamManagerForStreamUUID = [UUID: DiscussionsListViewModelStreamManager]()
    private var discussionCellViewModelStreamManagerForStreamUUID = [UUID: DiscussionCellViewModelStreamManager]()
    private var userActivityDiscussionIdentifierContinuationForStreamUUID = [UUID: AsyncStream<ObvDiscussionsList.ObvDiscussionsListViewModel.DiscussionIdentifier?>.Continuation]()

    private var cancellables: Set<AnyCancellable> = []
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        produceStreamsOnChangeOfDiscussionID()
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
    }

}


// MARK: - Implementing ObvDiscussionsListViewDataSource

extension ObvDiscussionsListViewAppDataSource: ObvDiscussionsListViewDataSource {

    // For the list of recent discussion's identifiers
    
    func getAsyncStreamOfObvDiscussionsListViewModel(_ view: ObvDiscussionsListView, ownedCryptoId: ObvCryptoId, initialSearchText: String?) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionsListViewModel>) {
        let manager = DiscussionsListViewModelStreamManager(ownedCryptoId: ownedCryptoId, initialSearchText: initialSearchText, context: backgroundContext)
        discussionsListViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }

    
    func finishAsyncStreamOfObvDiscussionsListViewModel(_ view: ObvDiscussionsListView, streamUUID: UUID) {
        guard let manager = discussionsListViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    
    func filterAsyncStreamOfObvDiscussionsListViewModel(_ view: ObvDiscussionsListView, streamUUID: UUID, searchStatus: ObvDiscussionsListViewModel.SearchStatus) {
        guard let manager = discussionsListViewModelStreamManagerForStreamUUID[streamUUID] else { return }
        manager.updateWithSearchText(searchStatus: searchStatus, doPerformFetch: true)
    }
    
    func getIdentifiersOfCurrentlyPinnedDiscussions(ownedCryptoId: ObvCryptoId) async throws -> [ObvDiscussionsListViewModel.DiscussionIdentifier] {
        let pinnedDiscussions = try PersistedDiscussion.getAllPinnedDiscussions(ownedCryptoId: ownedCryptoId, with: viewContext)
        let viewIdentifiers: [ObvDiscussionsListViewModel.DiscussionIdentifier] = pinnedDiscussions.map { .persistedDiscussionObjectID($0.objectID) }
        return viewIdentifiers
    }

    // For an individual cell, showing a recent discussion
    
    func getAsyncStreamOfObvDiscussionCellViewModel(_ view: DiscussionCellView, discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionCellViewModel>) {
        let manager = try DiscussionCellViewModelStreamManager(discussionIdentifier: discussionIdentifier, context: backgroundContext)
        discussionCellViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    
    func finishAsyncStreamOfObvDiscussionCellViewModel(_ view: DiscussionCellView, streamUUID: UUID) {
        guard let manager = discussionCellViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }

    func getInitialObvDiscussionCellViewModel(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) -> ObvDiscussionCellViewModel? {
        guard let discussionObjectID = discussionIdentifier.objectID else { assertionFailure(); return nil }
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: viewContext) else { return nil }
        guard let model = try? ObvDiscussionCellViewModel(discussion: discussion) else { assertionFailure(); return nil }
        return model
    }
    
    
    // On mac/iPad: Highlighting the discussion the user is in
    
    func getAsyncStreamOfUserActivityDiscussionIdentifier(_ view: DiscussionCellView) throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionsListViewModel.DiscussionIdentifier?>) {
        let streamUUID = UUID()
        let stream = AsyncStream(ObvDiscussionsList.ObvDiscussionsListViewModel.DiscussionIdentifier?.self) { [weak self] (continuation: AsyncStream<ObvDiscussionsList.ObvDiscussionsListViewModel.DiscussionIdentifier?>.Continuation) in
            guard let self else { continuation.finish(); return }
            userActivityDiscussionIdentifierContinuationForStreamUUID[streamUUID] = continuation
            // Send the latest version of the stream
            if let objectID = OlvidUserActivitySingleton.shared.currentDiscussionID?.objectID.objectID {
                continuation.yield(.persistedDiscussionObjectID(objectID))
            } else {
                continuation.yield(nil)
            }
        }
        return (streamUUID, stream)
    }
    
    
    func finishAsyncStreamOfUserActivityDiscussionIdentifier(_ view: DiscussionCellView, streamUUID: UUID) {
        if let continuation = userActivityDiscussionIdentifierContinuationForStreamUUID.removeValue(forKey: streamUUID) {
            continuation.finish()
        }
    }

    private func produceStreamsOnChangeOfDiscussionID() {
        OlvidUserActivitySingleton.shared.$currentDiscussionID
            .sink { [weak self] newValue in
                self?.userActivityDiscussionIdentifierContinuationForStreamUUID.values.forEach { continuation in
                    if let newValue {
                        continuation.yield(.persistedDiscussionObjectID(newValue.objectID.objectID))
                    } else {
                        continuation.yield(nil)
                    }
                }
            }
            .store(in: &cancellables)
    }

    
    enum ObvError: Error {
        case delegateNotSet
    }

}




// MARK: - Internal managers

extension ObvDiscussionsListViewAppDataSource {
    
    /// This manager produces the stream of the discussion identifiers shown on the "home page" of the app, i.e., the list of recent discussions shown in the left-most tab.
    /// When not performing a search, this manager stream the identifiers of pinned and unpinned discussions that are *not* archived, and not deleted.
    /// During a search, it adds the archived and deleted discussions to the list.
    private final class DiscussionsListViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvDiscussionsList.ObvDiscussionsListViewModel, PersistedDiscussion>, @unchecked Sendable {
        
        private let ownedCryptoId: ObvCryptoId
        let initialPredicateWhenUserDoesNotPerformSearch: NSPredicate
        let initialPredicateWhenUserPerformsSearch: NSPredicate
        private let contentUnavailableViewModel: ObvContentUnavailableView.Model = .init(title: String(localized: "CONTENT_UNAVAILABLE_RECENT_DISCUSSIONS_TEXT"),
                                                                                         systemIcon: .bubbleLeftAndBubbleRight,
                                                                                         description: String(localized: "CONTENT_UNAVAILABLE_RECENT_DISCUSSIONS_SECONDARY_TEXT_WHEN_USING_FLOATING_BUTTON"))

        init(ownedCryptoId: ObvCryptoId, initialSearchText: String?, context: NSManagedObjectContext) {
            self.ownedCryptoId = ownedCryptoId
            // Note that `createModel()` expects the frc to contain two sections (so the splitPinnedDiscussionsIntoSections must be set to true here)
            self.initialPredicateWhenUserDoesNotPerformSearch = PersistedDiscussion.getPredicateForUnarchivedNotDeletedDiscussionsForOwnedIdentity(ownedCryptoId: ownedCryptoId)
            self.initialPredicateWhenUserPerformsSearch = PersistedDiscussion.getPredicateForAllDiscussionsForOwnedIdentity(ownedCryptoId: ownedCryptoId)
            let frc = PersistedDiscussion.getFetchedResultsControllerWithPinnedDiscussionsSplitIntoSections(predicate: self.initialPredicateWhenUserDoesNotPerformSearch, within: context)
            super.init(frc: frc)
            self.updateWithSearchText(searchStatus: .notPerformingSearch, doPerformFetch: false)
        }

        func updateWithSearchText(searchStatus: ObvDiscussionsListViewModel.SearchStatus, doPerformFetch: Bool) {
            let newPredicate: NSPredicate
            switch searchStatus {
            case .notPerformingSearch:
                newPredicate = self.initialPredicateWhenUserDoesNotPerformSearch
            case .performingSearch(searchText: let searchText):
                let searchPredicate = PersistedDiscussion.getSearchPredicate(searchText)
                newPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    self.initialPredicateWhenUserPerformsSearch,
                    searchPredicate,
                ])
            }
            self.frc.fetchRequest.predicate = newPredicate
            if doPerformFetch {
                do {
                    try frc.performFetch()
                } catch {
                    assertionFailure()
                }
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await getFetchedObjectsAndYieldModelIfNeeded()
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
            }
        }

        
        override func createModel(fetchedObjects: [PersistedDiscussion]) throws -> ObvDiscussionsListViewModel {
            
            guard let sections = frc.sections else {
                assertionFailure()
                throw ObvError.noSections
            }
            
            var identifiersOfPinnedDiscussions = [ObvDiscussionsListViewModel.DiscussionIdentifier]()
            var identifiersOfUnpinnedDiscussions = [ObvDiscussionsListViewModel.DiscussionIdentifier]()

            for section in sections {
                guard let objects = section.objects as? [PersistedDiscussion] else { assertionFailure(); continue }
                guard let sectionIdentifier = PersistedDiscussion.PinnedSectionKeyPathValue(rawValue: section.name) else { assertionFailure(); continue }
                switch sectionIdentifier {
                case .pinned:
                    identifiersOfPinnedDiscussions = objects.map { .persistedDiscussionObjectID($0.objectID) }
                case .unpinned:
                    identifiersOfUnpinnedDiscussions = objects.map { .persistedDiscussionObjectID($0.objectID) }
                }
            }
            
            let model = ObvDiscussionsList.ObvDiscussionsListViewModel(
                ownedCryptoId: ownedCryptoId,
                identifiersOfPinnedDiscussions: identifiersOfPinnedDiscussions,
                identifiersOfUnpinnedDiscussions: identifiersOfUnpinnedDiscussions,
                contentUnavailableViewModel: contentUnavailableViewModel)
            
            return model
            
        }

        enum ObvError: Error {
            case couldNotFetchObjects
            case ownedCryptoIdNotFound
            case noSections
        }

        
    }
        
}


extension ObvDiscussionsListViewAppDataSource {
    
    private final class DiscussionCellViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvDiscussionsList.ObvDiscussionCellViewModel, PersistedDiscussion, PersistedDiscussionLocalConfiguration>, @unchecked Sendable {
        
        init(discussionIdentifier: ObvDiscussionsList.ObvDiscussionsListViewModel.DiscussionIdentifier, context: NSManagedObjectContext) throws {
            let persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
            switch discussionIdentifier {
            case .obvDiscussionIdentifier:
                assertionFailure()
                throw ObvError.unexpectedIdentifierKind
            case .persistedDiscussionObjectID(let objectID):
                persistedDiscussionObjectID = .init(objectID: objectID)
            }
            let frc = PersistedDiscussion.getFetchedResultsController(objectID: persistedDiscussionObjectID, within: context)
            let frcForLocalConfigurations = PersistedDiscussionLocalConfiguration.getFetchedResultsController(persistedDiscussionObjectID: persistedDiscussionObjectID, within: context)
            super.init(frc1: frc, frc2: frcForLocalConfigurations)
        }
        
        
        override func createModel(fetchedObjects1: [PersistedDiscussion], fetchedObjects2: [PersistedDiscussionLocalConfiguration]) throws -> ObvDiscussionCellViewModel {
            
            // The frcForLocalConfigurations is only required to be notified of a change that could result in a new view model value
            
            let fetchedObjects = fetchedObjects1
            
            assert(fetchedObjects.count < 2)
            
            guard let firstObject = fetchedObjects.first else {
                // This happens when the discussion gets deleted
                throw ObvError.objectDoesNotExist
            }
            
            let model = try ObvDiscussionCellViewModel(discussion: firstObject)
            
            return model
            
        }


        enum ObvError: Error {
            case unexpectedIdentifierKind
            case couldNotFetchObjects
            case objectDoesNotExist
        }
        

    }
        
}


extension ObvDiscussionCellViewModel.Message {
    
    init(illustrativeMessage: PersistedMessage) throws {
        
        let kind: ObvDiscussionCellViewModel.Message.Kind
        if let sentMessage = illustrativeMessage as? PersistedMessageSent {
            kind = .sent(status: SentStatus.init(status: sentMessage.status),
                         messageHasMoreThanOneRecipient: sentMessage.hasMoreThanOneRecipient)
        } else if illustrativeMessage is PersistedMessageReceived {
            kind = .received
        } else if illustrativeMessage is PersistedMessageSystem {
            kind = .system
        } else {
            assertionFailure()
            throw ObvErrorCoreDataInitializers.unexpectedIllustrativeMessageType
        }

        self.init(body: illustrativeMessage.subtitle,
                  kind: kind)
        
    }
    
    enum ObvErrorCoreDataInitializers: Error {
        case contactNotFound
        case unexpectedIllustrativeMessageType
    }
    
}


extension ObvDiscussionCellViewModel.Message.SentStatus {
    
    init(status: PersistedMessageSent.MessageStatus) {
        switch status {
        case .sentFromAnotherOwnedDevice: self = .sentFromAnotherOwnedDevice
        case .hasNoRecipient: self = .hasNoRecipient
        case .couldNotBeSentToOneOrMoreRecipients: self = .couldNotBeSentToOneOrMoreRecipients
        case .fullyDeliveredAndFullyRead: self = .fullyDeliveredAndFullyRead
        case .fullyDeliveredAndPartiallyRead: self = .fullyDeliveredAndPartiallyRead
        case .fullyDeliveredAndNotRead: self = .fullyDeliveredAndNotRead
        case .partiallyDeliveredAndPartiallyRead: self = .partiallyDeliveredAndPartiallyRead
        case .partiallyDeliveredNotRead: self = .partiallyDeliveredNotRead
        case .sent: self = .sent
        case .processing: self = .processing
        case .unprocessed: self = .unprocessed
        }
    }
    
}


extension ObvDiscussionCellViewModel {
    
    init(discussion: PersistedDiscussion) throws {
        
        let message: ObvDiscussionCellViewModel.Message?
        if let illustrativeMessage = discussion.illustrativeMessage {
            message = try Message(illustrativeMessage: illustrativeMessage)
        } else {
            message = nil
        }
        
        let avatarViewModel: ObvAvatarViewModel
        do {
            avatarViewModel = try discussion.avatarViewModel
        } catch {
            assertionFailure(error.localizedDescription)
            avatarViewModel = .init(characterOrIcon: .icon(.lock(.fill, .none)),
                                    colors: .init(foreground: .secondaryLabel, background: .secondarySystemBackground),
                                    photoURL: nil)
        }
        
        self.init(avatarModel: avatarViewModel,
                  title: discussion.title,
                  date: discussion.sortDate,
                  message: message,
                  numberOfNewReceivedMessages: discussion.numberOfNewMessages,
                  showGreenShield: discussion.circledInitialsConfiguration?.showGreenShield ?? false,
                  showRedShield: discussion.circledInitialsConfiguration?.showRedShield ?? false,
                  aNewReceivedMessageDoesMentionOwnedIdentity: discussion.aNewReceivedMessageDoesMentionOwnedIdentity,
                  shouldMuteNotifications: discussion.hasNotificationsMuted,
                  isArchived: discussion.isArchived,
                  isPinned: discussion.isPinned,
                  isMuted: discussion.hasNotificationsMuted)
    }
    
}


extension ObvProfilePictureBarButtonItemViewModel {
    
    init(ownedIdentity: PersistedObvOwnedIdentity, showRedDot: Bool) {
        self.init(ownedCryptoId: ownedIdentity.cryptoId,
                  avatarModel: ObvAvatarViewModel(ownedIdentity: ownedIdentity),
                  showGreenShield: ownedIdentity.isKeycloakManaged,
                  showRedDot: showRedDot)
    }
    
}


// MARK: Computing a cell subtitle from a PersistedMessage

public extension PersistedMessage {

    var statusIcon: (any SymbolIcon)? {

        if let sentMessage = self as? PersistedMessageSent {
            switch try? self.discussion?.kind {
            case .groupV1(withContactGroup: let contactGroup):
                return sentMessage.status.getSymbolIcon(messageHasMoreThanOneRecipient: (contactGroup?.contactIdentities.count ?? 0) > 1)
            case .groupV2(withGroup: let group):
                return sentMessage.status.getSymbolIcon(messageHasMoreThanOneRecipient: (group?.otherMembers.count ?? 0) > 1)
            default:
                return sentMessage.status.getSymbolIcon(messageHasMoreThanOneRecipient: false)
            }
        }

        return nil
    }

    /// This is typically used to obtain the appropriate text and style for a message in order to show in the list of recent discussions.
    var subtitle: AttributedString {

        let text: AttributedString
        let isSystemMessage: Bool

        if isLocallyWiped {

            text = AttributedString(PersistedMessage.Strings.messageWasWiped)
            isSystemMessage = true

        } else if isRemoteWiped {

            text = AttributedString(PersistedMessage.Strings.messageWasWiped)
            isSystemMessage = true

        } else if self is PersistedMessageSystem {

            text = displayableAttributedBody ?? AttributedString(textBody ?? "")
            isSystemMessage = true

        } else if !readOnce && initialExistenceDuration == nil && visibilityDuration == nil {

            if isLocationMessage {
                if let sentMessage = self as? PersistedMessageSent {
                    if let location = sentMessage.locationOneShotSent {
                        if let address = location.address {
                            text = AttributedString(PersistedMessage.Strings.youSharedAPlace + ": \(address)")
                        } else {
                            text = AttributedString(PersistedMessage.Strings.youSharedAPlace)
                        }
                    } else if sentMessage.locationContinuousSent != nil {
                        text = AttributedString(PersistedMessage.Strings.youStartedSharingLocation)
                    } else {
                        text = AttributedString(PersistedMessage.Strings.youStoppedSharingLocation)
                    }
                } else if let receivedMessage = self as? PersistedMessageReceived {
                    let contactName = receivedMessage.contactIdentity?.customOrShortDisplayName ?? PersistedMessage.Strings.someone
                    if let location = receivedMessage.locationOneShotReceived {
                        if let address = location.address {
                            text = AttributedString(PersistedMessage.Strings.someoneSharedAPlace(contactName) + ": \(address)")
                        } else {
                            text = AttributedString(PersistedMessage.Strings.someoneSharedAPlace(contactName))
                        }
                    } else if receivedMessage.locationContinuousReceived != nil {
                        text = AttributedString(PersistedMessage.Strings.someoneStartedSharingLocation(contactName))
                    } else {
                        text = AttributedString(PersistedMessage.Strings.someoneStoppedSharingLocation(contactName))
                    }
                } else {
                    text = ""
                }
                isSystemMessage = true
            }
            // If the subtitle is empty, there might be attachments
            else if let fyleMessageJoinWithStatus = fyleMessageJoinWithStatus, (textBody ?? "").isEmpty, fyleMessageJoinWithStatus.count > 0 {
                text = AttributedString(PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count))
                isSystemMessage = true
            } else {
                text = displayableAttributedBody ?? AttributedString(textBody ?? "")
                isSystemMessage = false
            }

        } else {

            if let sentMessage = self as? PersistedMessageSent {

                assert(!sentMessage.isWiped)

                // If the message is a location message
                if sentMessage.isLocationMessage {
                    if let location = sentMessage.locationOneShotSent {
                        if let address = location.address {
                            text = AttributedString(PersistedMessage.Strings.youSharedAPlace + ": \(address)")
                        } else {
                            text = AttributedString(PersistedMessage.Strings.youSharedAPlace)
                        }
                    } else if sentMessage.locationContinuousSent != nil {
                        text = AttributedString(PersistedMessage.Strings.youStartedSharingLocation)
                    } else {
                        text = AttributedString(PersistedMessage.Strings.youStoppedSharingLocation)
                    }

                    isSystemMessage = true
                }
                // If the subtitle is empty, there might be attachments
                else if let fyleMessageJoinWithStatus = sentMessage.fyleMessageJoinWithStatus, (sentMessage.textBody ?? "").isEmpty, fyleMessageJoinWithStatus.count > 0 {
                    text = AttributedString(PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count))
                    isSystemMessage = true
                } else {
                    text = displayableAttributedBody ?? AttributedString(textBody ?? "")
                    isSystemMessage = false
                }

            } else if let receivedMessage = self as? PersistedMessageReceived {

                if readOnce || visibilityDuration != nil {

                    // Ephemeral received message with readOnce or limited visibility
                    switch receivedMessage.status {
                    case .new, .unread:
                        text = AttributedString(PersistedMessage.Strings.unreadEphemeralMessage)
                        isSystemMessage = true
                    case .read:
                        assert(!isWiped)
                        // If the subtitle is empty, there might be attachments
                        if let fyleMessageJoinWithStatus = fyleMessageJoinWithStatus, (textBody ?? "").isEmpty, fyleMessageJoinWithStatus.count > 0 {
                            text = AttributedString(PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count))
                            isSystemMessage = true
                        } else {
                            text = displayableAttributedBody ?? AttributedString(textBody ?? "")
                            isSystemMessage = false
                        }
                    }

                } else {

                    // Ephemeral received message with limited existence only
                    assert(!isWiped)
                    // If the message is a location message
                    if receivedMessage.isLocationMessage {

                        let contactName = receivedMessage.contactIdentity?.customOrShortDisplayName ?? PersistedMessage.Strings.someone
                        if let location = receivedMessage.locationOneShotReceived {
                            if let address = location.address {
                                text = AttributedString(PersistedMessage.Strings.someoneSharedAPlace(contactName) + ": \(address)")
                            } else {
                                text = AttributedString(PersistedMessage.Strings.someoneSharedAPlace(contactName))
                            }
                        } else if receivedMessage.locationContinuousReceived != nil {
                            text = AttributedString(PersistedMessage.Strings.someoneStartedSharingLocation(contactName))
                        } else {
                            text = AttributedString(PersistedMessage.Strings.someoneStoppedSharingLocation(contactName))
                        }

                        isSystemMessage = true
                    }
                    // If the subtitle is empty, there might be attachments
                    else if let fyleMessageJoinWithStatus = fyleMessageJoinWithStatus, (textBody ?? "").isEmpty, fyleMessageJoinWithStatus.count > 0 {
                        text = AttributedString(PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count))
                        isSystemMessage = true
                    } else {
                        text = displayableAttributedBody ?? AttributedString(textBody ?? "")
                        isSystemMessage = false
                    }

                }

            } else {

                assertionFailure()
                text = AttributedString("")
                isSystemMessage = true

            }
        }

        let prefixContent: AttributedString?

        if let receivedMessage = self as? PersistedMessageReceived {
            switch try? self.discussion?.kind {
            case .groupV1, .groupV2:
                if let sender = receivedMessage.contactIdentity?.customOrShortDisplayName {
                    prefixContent = AttributedString("\(sender): ")
                } else {
                    prefixContent = nil
                }
            default:
                prefixContent = nil
            }
        } else {
            prefixContent = nil
        }

        // Note that we don't need to apply a special style for emphasized, strong, etc.
        // as the SwiftUI view will do the job for us.
        let prefixedContent: AttributedString
        if let prefixContent {
            prefixedContent = prefixContent + text
        } else {
            prefixedContent = text
        }

        return prefixedContent
            .withStyleForInlinePresentationIntents(isSystemMessage: isSystemMessage)
            .removingLinkAttributes()
    }
}


// MARK: - AttributedString helper used when computing a cell subtitle from a PersistedMessage

private extension AttributedString {

    func withStyleForInlinePresentationIntents(isSystemMessage: Bool) -> AttributedString {
        let textStyle: UIFont.TextStyle = .subheadline
        var output = self
        if isSystemMessage {
            output.font = .italic(forTextStyle: textStyle)
        } else {
            output.font = UIFont.preferredFont(forTextStyle: textStyle)
        }
        return output
    }


    /// Remove the links from the AttributedString since we don't want to let the user interact with them from the list of recent discussions.
    func removingLinkAttributes() -> AttributedString {
        var output = self
        output.link = .none
        return output
    }

}
