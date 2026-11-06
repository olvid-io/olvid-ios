/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvShareExtension
import OlvidUtils
import ObvUICoreData
import ObvOwnedIdentityChooser
import ObvDiscussionChooser
import ObvTypes
import ObvAppTypes
import ObvDesignSystem
import ObvSharedDataSources

/// Main data source for the Share Extension view.
/// Manages the lifecycle of stream managers for various view models and provides
/// data from Core Data contexts to the Share Extension UI.
@MainActor
public final class ShareExtensionViewAppDataSource {

    /// Main queue context for UI-related operations
    private let viewContext: NSManagedObjectContext

    /// Background queue context for heavy data operations
    private let backgroundContext: NSManagedObjectContext

    /// Active stream managers for share extension view models, keyed by stream UUID
    private var shareExtensionViewModelStreamManagerForStreamUUID = [UUID: ShareExtensionViewModelStreamManager]()

    /// Active stream managers for the discussion chooser's list of identifiers, keyed by stream UUID
    private var discussionIdentifiersStreamManagerForStreamUUID = [UUID: DiscussionIdentifiersStreamManager]()

    /// Active stream managers for per-discussion display models (one per visible cell/chip), keyed by stream UUID
    private var discussionItemViewModelStreamManagerForStreamUUID = [UUID: DiscussionItemViewModelStreamManager]()

    /// Active stream managers for the "To:" row's single-recipient model, keyed by stream UUID
    private var singleRecipientSummaryViewModelStreamManagerForStreamUUID = [UUID: SingleRecipientSummaryViewModelStreamManager]()

    /// Shared data source backing the owned-identity chooser, reused instead of a share-extension-specific
    /// copy. See the `OwnedIdentityChooserViewDataSource` conformance for why hidden identities are never
    /// shown here.
    private let ownedIdentityChooserViewAppDataSource: OwnedIdentityChooserViewAppDataSource

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.ownedIdentityChooserViewAppDataSource = OwnedIdentityChooserViewAppDataSource(viewContext: viewContext, anyContext: backgroundContext)
    }

    enum ObvError: Error {
        case discussionNotFound
    }
}

// MARK: - ShareExtensionViewDataSource

extension ShareExtensionViewAppDataSource: ShareExtensionViewDataSource {

    /// Provides the initial view model for the Share Extension view.
    /// Fetches all non-hidden owned identities and determines which one should be selected.
    /// - Parameter currentOwnedCryptoId: Optional crypto ID of the currently selected owned identity
    /// - Returns: Initial view model with owned identities, selected identity, and whether that identity has
    ///   at least one discussion available.
    public func getInitialShareExtensionViewModel(currentOwnedCryptoId: ObvCryptoId?) -> ShareExtensionView.Model {
        let ownedIdentities = (try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: self.viewContext)) ?? []

        // `currentOwnedCryptoId` is resolved up front by the caller, so the selected identity is simply
        // the fetched one that matches it.
        let selectedPersistedOwnedIdentity = ownedIdentities.first(where: { $0.cryptoId == currentOwnedCryptoId })

        // We only need to know whether at least one discussion is available for the selected identity.
        let hasAtLeastOneDiscussionAvailable: Bool
        if let selectedPersistedOwnedIdentity {
            let discussions = (try? PersistedDiscussion.getAllActiveDiscussionsForOwnedIdentity(with: selectedPersistedOwnedIdentity.cryptoId, within: self.viewContext)) ?? []
            hasAtLeastOneDiscussionAvailable = !discussions.isEmpty
        } else {
            hasAtLeastOneDiscussionAvailable = false
        }

        return ShareExtensionView.Model(persistedOwnedIdentities: ownedIdentities,
                                        selectedPersistedIdentity: selectedPersistedOwnedIdentity,
                                        hasAtLeastOneDiscussionAvailable: hasAtLeastOneDiscussionAvailable)
    }

    /// Creates and starts an async stream of Share Extension view models.
    /// The stream will emit updated models whenever the underlying data changes.
    /// - Parameters:
    ///   - view: The Share Extension view requesting the stream
    ///   - currentOwnedCryptoId: Optional crypto ID of the currently selected owned identity
    /// - Returns: A tuple containing the stream UUID and the async stream of view models
    public func getAsyncSequenceOfShareExtensionViewModel(_ view: ObvShareExtension.ShareExtensionView, currentOwnedCryptoId: ObvCryptoId?) async throws -> (streamUUID: UUID, stream: AsyncStream<ShareExtensionView.Model>) {

        let manager = ShareExtensionViewModelStreamManager(currentOwnedCryptoId: currentOwnedCryptoId, context: backgroundContext)
        shareExtensionViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }

    /// Finishes and cleans up an async stream of Share Extension view models.
    /// - Parameters:
    ///   - view: The Share Extension view that owned the stream
    ///   - streamUUID: The UUID of the stream to finish
    public func finishAsyncSequenceOfShareExtensionViewModel(_ view: ObvShareExtension.ShareExtensionView, streamUUID: UUID) {
        guard let manager = shareExtensionViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }

}

// MARK: - OwnedIdentityChooserViewDataSource

extension ShareExtensionViewAppDataSource: OwnedIdentityChooserViewDataSource {

    /// Creates and starts an async stream of owned identity chooser view models by forwarding to the
    /// shared `OwnedIdentityChooserViewAppDataSource`.
    ///
    /// - Note: In the share extension, `currentOwnedCryptoId` is always a **non-hidden** identity (the
    ///   selection is resolved from the non-hidden identities only). The shared data source lists all
    ///   non-hidden identities plus the current one — and since the current one is non-hidden, its
    ///   "keep the current even if hidden" clause never applies, so a hidden identity is never shown here.
    public func getAsyncStreamOfOwnedIdentityChooserViewModel(
        _ view: ObvOwnedIdentityChooser.OwnedIdentityChooserInnerView,
        currentOwnedCryptoId: ObvTypes.ObvCryptoId
    ) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvOwnedIdentityChooser.OwnedIdentityChooserViewModel>) {
        return try await ownedIdentityChooserViewAppDataSource.getAsyncStreamOfOwnedIdentityChooserViewModel(view, currentOwnedCryptoId: currentOwnedCryptoId)
    }

    /// Finishes and cleans up an async stream of owned identity chooser view models.
    public func finishAsyncStreamOfOwnedIdentityChooserViewModel(_ view: ObvOwnedIdentityChooser.OwnedIdentityChooserInnerView, streamUUID: UUID) {
        ownedIdentityChooserViewAppDataSource.finishAsyncStreamOfOwnedIdentityChooserViewModel(view, streamUUID: streamUUID)
    }


}

// MARK: - DiscussionChooserViewDataSource

extension ShareExtensionViewAppDataSource: DiscussionChooserViewDataSource {

    /// Creates and starts an async stream of the (search-filtered) discussion **identifiers** to display.
    /// Only identifiers are streamed; each row/chip resolves its own display model via
    /// `DiscussionItemViewDataSource`, so memory stays bounded even with a very large number of discussions.
    /// - Parameters:
    ///   - view: The discussion chooser view requesting the stream
    ///   - currentOwnedCryptoId: The crypto ID of the currently selected owned identity
    /// - Returns: A tuple containing the stream UUID and the async stream of discussion identifiers
    public func getAsyncStreamOfDiscussionIdentifiers(
        _ view: ObvDiscussionChooser.DiscussionChooserInnerView,
        currentOwnedCryptoId: ObvTypes.ObvCryptoId
    ) async throws -> (streamUUID: UUID, stream: AsyncStream<[ObvDiscussionIdentifier]>) {
        let manager = DiscussionIdentifiersStreamManager(currentOwnedCryptoId: currentOwnedCryptoId, context: backgroundContext)
        discussionIdentifiersStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }

    /// Updates the discussion filter based on search text.
    /// - Parameters:
    ///   - view: The discussion chooser view requesting the filter
    ///   - streamUUID: The UUID of the stream to filter
    ///   - searchTerm: The search text to filter discussions (nil for no filter)
    public func filterAsyncStreamOfDiscussionIdentifiers(
        _ view: DiscussionChooserInnerView,
        streamUUID: UUID,
        searchTerm: String?
    ) {
        guard let manager = discussionIdentifiersStreamManagerForStreamUUID[streamUUID] else { return }
        manager.updateWithSearchText(searchTerm: searchTerm, doPerformFetch: true)
    }

    /// Finishes and cleans up an async stream of discussion identifiers.
    /// - Parameters:
    ///   - view: The discussion chooser view that owned the stream
    ///   - streamUUID: The UUID of the stream to finish
    public func finishAsyncStreamOfDiscussionIdentifiers(_ view: ObvDiscussionChooser.DiscussionChooserInnerView, streamUUID: UUID) {
        guard let manager = discussionIdentifiersStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }

}

// MARK: - DiscussionItemViewDataSource

extension ShareExtensionViewAppDataSource: DiscussionItemViewDataSource {

    /// Creates and starts an async stream of the display model for a single discussion (a list row, a
    /// selected chip, or the "To:" row). The stream emits an updated model whenever the discussion changes.
    /// - Parameter discussionIdentifier: The identifier of the discussion to resolve
    /// - Returns: A tuple containing the stream UUID and the async stream of the discussion's display model
    public func getAsyncStreamOfDiscussionItemViewModel(discussionIdentifier: ObvDiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<DiscussionItemView.Model>) {
        // Resolve the identifier to an objectID on the main-queue `viewContext` (safe to fetch synchronously
        // here), then hand the objectID to a manager that observes it on the background context.
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: viewContext) else {
            throw ObvError.discussionNotFound
        }
        let objectID = TypeSafeManagedObjectID<PersistedDiscussion>(objectID: discussion.objectID)
        let manager = DiscussionItemViewModelStreamManager(objectID: objectID, context: backgroundContext)
        discussionItemViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }

    /// Finishes and cleans up an async stream of a discussion's display model.
    /// - Parameters:
    ///   - discussionIdentifier: The identifier of the discussion the stream was resolving
    ///   - streamUUID: The UUID of the stream to finish
    public func finishAsyncStreamOfDiscussionItemViewModel(discussionIdentifier: ObvDiscussionIdentifier, streamUUID: UUID) {
        guard let manager = discussionItemViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }

}

// MARK: - SingleRecipientSummaryViewDataSource

extension ShareExtensionViewAppDataSource: SingleRecipientSummaryViewDataSource {

    /// Creates and starts an async stream of the "To:" row model for a single selected discussion.
    public func getAsyncStreamOfSingleRecipientSummaryViewModel(discussionIdentifier: ObvDiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SingleRecipientSummaryView.Model>) {
        // Resolve the identifier to an objectID on the main-queue `viewContext`, then observe it on the
        // background context (same approach as the per-cell discussion item stream).
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: viewContext) else {
            throw ObvError.discussionNotFound
        }
        let objectID = TypeSafeManagedObjectID<PersistedDiscussion>(objectID: discussion.objectID)
        let manager = SingleRecipientSummaryViewModelStreamManager(objectID: objectID, context: backgroundContext)
        singleRecipientSummaryViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }

    public func finishAsyncStreamOfSingleRecipientSummaryViewModel(discussionIdentifier: ObvDiscussionIdentifier, streamUUID: UUID) {
        guard let manager = singleRecipientSummaryViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }

}

// MARK: - ShareExtensionViewModelStreamManager

extension ShareExtensionViewAppDataSource {

    /// Stream manager for Share Extension view models.
    /// Observes changes in owned identities and discussions to provide real-time updates.
    private final class ShareExtensionViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ShareExtensionView.Model, PersistedObvOwnedIdentity, PersistedDiscussion>, @unchecked Sendable {

        let currentOwnedCryptoId: ObvCryptoId?
        let context: NSManagedObjectContext

        init(currentOwnedCryptoId: ObvCryptoId?, context: NSManagedObjectContext) {

            self.currentOwnedCryptoId = currentOwnedCryptoId
            self.context = context

            // Setup fetched results controller for owned identities
            let frc1 = PersistedObvOwnedIdentity.getFetchedResultsControllerForAllNonHiddenOwnedIdentities(within: context)

            let frcModel: FetchRequestControllerModel<PersistedDiscussion>

            if let currentOwnedCryptoId {
                // Fetch discussions for the specified identity
                frcModel = PersistedDiscussion.getFetchRequestForAllActiveRecentDiscussionsForOwnedIdentity(with: currentOwnedCryptoId)
            } else {
                // Create an FRC with a predicate that never returns results
                frcModel = PersistedDiscussion.getFetchRequestForNoDiscussions()
            }

            // Setup fetched results controller for discussions
            let fetchRequest = frcModel.fetchRequest
            let frc2 = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                  managedObjectContext: context,
                                                  sectionNameKeyPath: nil,
                                                  cacheName: nil)

            super.init(frc1: frc1, frc2: frc2)
        }

        /// Creates a view model from the fetched objects. The selected identity is the fetched one matching
        /// `currentOwnedCryptoId`, and `frc2` is configured to observe exactly that identity's discussions, so
        /// its (non-)emptiness tells us whether at least one discussion is available.
        override func createModel(fetchedObjects1: [PersistedObvOwnedIdentity], fetchedObjects2: [PersistedDiscussion]) throws -> ShareExtensionView.Model {
            let selectedPersistedOwnedIdentity = fetchedObjects1.first(where: { $0.cryptoId == currentOwnedCryptoId })
            return ShareExtensionView.Model(persistedOwnedIdentities: fetchedObjects1,
                                            selectedPersistedIdentity: selectedPersistedOwnedIdentity,
                                            hasAtLeastOneDiscussionAvailable: selectedPersistedOwnedIdentity != nil && !fetchedObjects2.isEmpty)
        }
    }

}

// MARK: - DiscussionIdentifiersStreamManager

extension ShareExtensionViewAppDataSource {

    /// Stream manager for the discussion chooser's list of identifiers.
    /// Observes changes in discussions and supports filtering via search text.
    private final class DiscussionIdentifiersStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<[ObvDiscussionIdentifier], PersistedDiscussion>, @unchecked Sendable {

        let initialPredicate: NSPredicate

        init(currentOwnedCryptoId: ObvCryptoId, context: NSManagedObjectContext) {

            self.initialPredicate = PersistedDiscussion.getPredicateForActiveDiscussionsForOwnedIdentity(ownedCryptoId: currentOwnedCryptoId)

            // Reuse the home-page recent-discussions controller so the chooser is ordered exactly like the
            // app's discussion list (pinned first, then most recent). The chooser is a flat list: the stream
            // manager reads `frc.fetchedObjects` and ignores the pinned/unpinned sections.
            let frc = PersistedDiscussion.getFetchedResultsControllerWithPinnedDiscussionsSplitIntoSections(predicate: self.initialPredicate,
                                                                                                            within: context)
            super.init(frc: frc)
            self.updateWithSearchText(searchTerm: nil, doPerformFetch: false)
        }

        /// Updates the fetch predicate based on search text.
        /// Combines the base predicate with the search predicate if a search term is provided.
        /// - Parameters:
        ///   - searchTerm: Optional search text to filter discussions
        ///   - doPerformFetch: Whether to perform the fetch immediately
        func updateWithSearchText(searchTerm: String?, doPerformFetch: Bool) {
            let newPredicate: NSPredicate
            if let searchTerm {
                let searchPredicate = PersistedDiscussion.getSearchPredicate(searchTerm)
                newPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    self.initialPredicate,
                    searchPredicate,
                ])
            } else {
                newPredicate = self.initialPredicate
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

        /// Maps the fetched discussions to their identifiers, in fetch order.
        override func createModel(fetchedObjects: [PersistedDiscussion]) throws -> [ObvDiscussionIdentifier] {
            return fetchedObjects.compactMap { try? $0.discussionIdentifier }
        }

    }

}

// MARK: - DiscussionItemViewModelStreamManager

extension ShareExtensionViewAppDataSource {

    /// Stream manager for a single discussion's display model, backed by a single-object fetched results
    /// controller so the row/chip updates live and stops yielding once the discussion is deleted.
    private final class DiscussionItemViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<DiscussionItemView.Model, PersistedDiscussion>, @unchecked Sendable {

        init(objectID: TypeSafeManagedObjectID<PersistedDiscussion>, context: NSManagedObjectContext) {
            let frc = PersistedDiscussion.getFetchedResultsController(objectID: objectID, within: context)
            super.init(frc: frc)
        }

        override func createModel(fetchedObjects: [PersistedDiscussion]) throws -> DiscussionItemView.Model {
            guard let discussion = fetchedObjects.first else {
                // The discussion no longer exists (e.g. it was deleted): stop yielding.
                throw ObvError.discussionDoesNotExist
            }
            return try DiscussionItemView.Model(persistedDiscussion: discussion)
        }

        enum ObvError: Error {
            case discussionDoesNotExist
        }

    }

}

// MARK: - SingleRecipientSummaryViewModelStreamManager

extension ShareExtensionViewAppDataSource {

    /// Stream manager for the "To:" row's single-recipient model, backed by a single-object fetched results
    /// controller so the row updates live and stops yielding once the discussion is deleted.
    private final class SingleRecipientSummaryViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<SingleRecipientSummaryView.Model, PersistedDiscussion>, @unchecked Sendable {

        init(objectID: TypeSafeManagedObjectID<PersistedDiscussion>, context: NSManagedObjectContext) {
            let frc = PersistedDiscussion.getFetchedResultsController(objectID: objectID, within: context)
            super.init(frc: frc)
        }

        override func createModel(fetchedObjects: [PersistedDiscussion]) throws -> SingleRecipientSummaryView.Model {
            guard let discussion = fetchedObjects.first else {
                throw ObvError.discussionDoesNotExist
            }
            return try SingleRecipientSummaryView.Model(persistedDiscussion: discussion)
        }

        enum ObvError: Error {
            case discussionDoesNotExist
        }

    }

}

// MARK: - SingleRecipientSummaryView.Model Extension

extension SingleRecipientSummaryView.Model {

    /// Builds the "To:" row model from a persisted discussion (avatar + title only).
    init(persistedDiscussion: PersistedDiscussion) throws {
        self.init(avatarViewModel: try ObvAvatarViewModel(persistedDiscussion: persistedDiscussion),
                  title: persistedDiscussion.title)
    }

}

// MARK: - DiscussionItemView.Model Extension

extension DiscussionItemView.Model {

    /// Initializer to create a discussion item view model from a Core Data entity.
    /// - Parameter persistedDiscussion: The persisted discussion
    /// - Throws: If required properties cannot be extracted from the persisted discussion
    init(persistedDiscussion: PersistedDiscussion) throws {

        // Determine shield status (security indicators)
        let showGreenShield = (try? persistedDiscussion.showGreenShield) ?? false
        let showRedShield = (try? persistedDiscussion.showRedShield) ?? false

        self.init(identifier: try persistedDiscussion.discussionIdentifier,
                  avatarViewModel: try ObvAvatarViewModel(persistedDiscussion: persistedDiscussion),
                  title: persistedDiscussion.title,
                  subtitle: persistedDiscussion.subtitle,
                  showGreenShield: showGreenShield,
                  showRedShield: showRedShield)
    }
}

// MARK: - ShareExtensionView.Model Extension

extension ShareExtensionView.Model {

    /// Initializer to create a Share Extension view model from Core Data entities.
    /// - Parameters:
    ///   - persistedOwnedIdentities: All non-hidden owned identities
    ///   - selectedPersistedIdentity: The currently selected owned identity (if any)
    ///   - hasAtLeastOneDiscussionAvailable: Whether the selected identity has at least one discussion to pick
    init(persistedOwnedIdentities: [PersistedObvOwnedIdentity],
         selectedPersistedIdentity: PersistedObvOwnedIdentity?,
         hasAtLeastOneDiscussionAvailable: Bool) {
        let ownedIdentities = persistedOwnedIdentities.map { OwnedIdentityChooserViewModel.OwnedIdentity(ownedIdentity: $0) }
        let selectedOwnedIdentity = selectedPersistedIdentity.map { OwnedIdentityChooserViewModel.OwnedIdentity(ownedIdentity: $0) }
        self.init(allOwnedIdentities: ownedIdentities,
                  selectedOwnedIdentity: selectedOwnedIdentity,
                  hasAtLeastOneDiscussionAvailable: hasAtLeastOneDiscussionAvailable)
    }

}
