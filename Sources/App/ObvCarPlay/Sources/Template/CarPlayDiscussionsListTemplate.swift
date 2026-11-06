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

import Intents
import Foundation
import ObvTypes
import OlvidUtils
#if canImport(CarPlay)
import CarPlay
import UIKit

@MainActor
public final class CarPlayDiscussionsListTemplate {
    
    private let currentOwnedCryptoId: ObvCryptoId
    
    private weak var interfaceController: CPInterfaceController?
    
    private var viewModel: CarPlayDiscussionsListViewModel? = nil
    
    private let dataSource: any CarPlayDiscussionsListViewDataSource
    
    public let listTemplate: CPListTemplate
    
    private var streamOfCarPlayDiscussionsListViewModelForUUID = [UUID : AsyncStream<CarPlayDiscussionsListViewModel>]()

    private var dayChangeTask: Task<Void, Never>?

    public init(currentOwnedCryptoId: ObvCryptoId,
                effectiveAPIPermissionsOfCurrentOwnedIdentity: APIPermissions,
                dataSource: any CarPlayDiscussionsListViewDataSource,
                interfaceController: CPInterfaceController) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.dataSource = dataSource
        self.interfaceController = interfaceController

        let assistantCellConfiguration: CPAssistantCellConfiguration?
        
        if effectiveAPIPermissionsOfCurrentOwnedIdentity.contains(.canCall) {
            assistantCellConfiguration = CPAssistantCellConfiguration(position: .top, visibility: .always, assistantAction: .startCall)
        } else {
            assistantCellConfiguration = nil
        }
        
        self.listTemplate = CPListTemplate(title: "Olvid", sections: [], assistantCellConfiguration: assistantCellConfiguration)
        
        if #available(iOS 18.4, *) {
            self.listTemplate.showsSpinnerWhileEmpty = true
        }

        
        // No handler is provided on purpose: the system-default init activates Siri's
        // compose flow when tapped, which donates an INSendMessageIntent handled by
        // our Intents Extension. A custom handler would suppress that flow.
        let messageButton = CPMessageComposeBarButton()

        self.listTemplate.trailingNavigationBarButtons = [messageButton]
    }
    
    public func performFetch() async throws {

        // Stop any existing fetch
        stopFetch()
        
        // Start a fresh fetch
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfCarPlayDiscussionsListViewModel(ownedCryptoId: self.currentOwnedCryptoId)
            streamOfCarPlayDiscussionsListViewModelForUUID[streamUUID] = stream

            observeCalendarDayChanges()

            for await receivedModel in stream {
                self.viewModel = receivedModel
                self.updateTemplate()
            }
        } catch {
            presentErrorAlert(message: String(localizedInThisBundle: "CARPLAY_ERROR_LOADING_DISCUSSIONS"))
            throw error
        }

    }


    public func stopFetch() {
        dayChangeTask?.cancel()
        dayChangeTask = nil
        while let (streamUUID, _) = self.streamOfCarPlayDiscussionsListViewModelForUUID.popFirst() {
            dataSource.finishAsyncStreamOfCarPlayDiscussionsListViewModel(streamUUID: streamUUID)
        }
    }


    /// The trailing text of each item is a date formatted relative to the current calendar day, so it goes stale at each
    /// day change even though the model did not change: nothing happened in database, so the data source has no reason
    /// to yield. Rebuilding the items from the model we already have is all it takes, and it costs one wake-up a day for
    /// the whole list.
    private func observeCalendarDayChanges() {
        dayChangeTask?.cancel()
        dayChangeTask = Task { [weak self] in
            // The stream's first value is the day we just formatted for, hence the dropFirst()
            for await _ in ObvCurrentDayMonitor.shared.startOfCurrentDayStream().dropFirst() {
                guard let self else { return }
                self.updateTemplate()
            }
        }
    }


    private func presentErrorAlert(message: String) {
        guard let interfaceController else { return }
        let okAction = CPAlertAction(title: NSLocalizedString("Ok", comment: ""), style: .cancel) { _ in
            interfaceController.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(titleVariants: [message], actions: [okAction])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }
    
    private func updateTemplate() {
        guard let viewModel else { return }

        guard !viewModel.isEmpty else {
            let info = CPListItem(text: String(localizedInThisBundle: "CONTENT_UNAVAILABLE_RECENT_DISCUSSIONS_TEXT"), detailText: nil)
            info.isEnabled = false
            listTemplate.updateSections([CPListSection(items: [info])])
            return
        }

        let startOfCurrentDay = ObvCurrentDayMonitor.shared.startOfCurrentDay

        let items: [CPMessageListItem] = viewModel.discussions.compactMap { discussion in
            guard let conversationIdentifier = discussion.conversationIdentifier else { return nil }
            let leadingConfiguration = CPMessageListItemLeadingConfiguration(leadingItem: discussion.isPinned ? .pin : .none,
                                                                             leadingImage: discussion.image,
                                                                             unread: discussion.unread)
            
            let item = CPMessageListItem(conversationIdentifier: conversationIdentifier,
                                         text: discussion.title,
                                         leadingConfiguration: leadingConfiguration,
                                         trailingConfiguration: nil,
                                         detailText: discussion.subtitle,
                                         trailingText: discussion.latestMessageDate?.discussionCellFormat(relativeTo: startOfCurrentDay))
                        
            return item
        }

        let section = CPListSection(items: items)

        listTemplate.updateSections([section])
    }
    
}

#endif
