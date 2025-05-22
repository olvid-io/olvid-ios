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
import OSLog
import ObvAppCoreConstants
import ObvUICoreData
import ObvUICoreDataStructs
import ObvCommunicationInteractor
import ObvAppTypes
import ObvSettings
import ObvTypes


/// The purpose of this manager is to donate intents.
///
/// Certain intents are donated by other part of the system. This is for example the case for the intents donated when receiving a message, which are donated by the
/// notification extension or by the user notification coordinator. This manager is used in all other cases, like when sending a message from the app.
actor IntentManager {
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: IntentManager.self))
    
    private var cancellables = Set<AnyCancellable>()
    
    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    func performPostInitialization() async {
        
        await PersistedMessageSent.addObserver(self)
        await PersistedDiscussion.addObvObserver(self)
        await PersistedDiscussionLocalConfiguration.addObvObserver(self)
        await PersistedCallLogItem.addObserver(self)
        
        ObvMessengerSettingsObservableObject.shared.$performInteractionDonation
            .dropFirst()
            .sink { [weak self] performInteractionDonation in
                Task { [weak self] in await self?.obvMessengerSettingsDiscussionsPerformInteractionDonationDidChange(performInteractionDonation: performInteractionDonation)  }
            }
            .store(in: &cancellables)
        
    }
    
}


// MARK: - Implementing PersistedCallLogItemDelegate

extension IntentManager: PersistedCallLogItemObserver {
    
    func aPersistedCallLogItemCallReportKindHasChanged(callLog: PersistedCallLogItemStructure) async {
        
        // The user notification coordinator also listens to this notification.
        // Make sure **we** are in charge
        
        switch callLog.notificationKind {
        case .none:
            return
        case .userNotificationAndStartCallIntent:
            // The user notification is in charge of scheduling a local user notification and of the intent suggestion
            return
        case .startCallItentOnly:
            // We are in charge of suggesting the intent
            break
        }
        
        let communicationType: ObvCommunicationType = .callLog(callLog: callLog)

        do {
            _ = try await ObvCommunicationInteractor.suggest(communicationType: communicationType)
        } catch {
            Self.logger.fault("Failed to suggest call donation: \(error.localizedDescription)")
            assertionFailure()
        }

    }
    
}


// MARK: - Implementing PersistedMessageSentObserver

extension IntentManager: PersistedMessageSentObserver {
    
    /// When a message is sent from the app, this delegate method is called. We use it to donate the appropriate intent.
    func aPersistedMessageSentWasInserted(messageSent: ObvUICoreDataStructs.PersistedMessageSentStructure) async {
        
        let communicationType: ObvCommunicationType = .outgoingMessage(sentMessage: messageSent)
        
        do {
            _ = try await ObvCommunicationInteractor.suggest(communicationType: communicationType)
        } catch {
            Self.logger.fault("Failed to suggest outgoing message donation: \(error.localizedDescription)")
            assertionFailure()
        }
        
    }
    
}


// MARK: - Implementing PersistedDiscussionDelegate

extension IntentManager: PersistedDiscussionObserver {
    
    func aPersistedDiscussionStatusChanged(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, status: ObvUICoreData.PersistedDiscussion.Status) async {
        guard status == .locked else { return }
        ObvCommunicationInteractor.delete(with: discussionIdentifier)
    }
    
    func aPersistedDiscussionIsArchivedChanged(discussionIdentifier: ObvDiscussionIdentifier, isArchived: Bool) async {
        guard isArchived else { return }
        ObvCommunicationInteractor.delete(with: discussionIdentifier)
    }
    
    func aPersistedDiscussionWasDeleted(discussionIdentifier: ObvDiscussionIdentifier) async {
        ObvCommunicationInteractor.delete(with: discussionIdentifier)
    }
    
    func aPersistedDiscussionWasRead(discussionIdentifier: ObvDiscussionIdentifier, localDateWhenDiscussionRead: Date) async {
        // Nothing to do
    }
    

    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedDiscussionChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        // Nothing to do
    }

    func aPersistedDiscussionWasInsertedOrReactivated(discussionIdentifier: ObvDiscussionIdentifier) async {
        // Nothing to do
    }

}


// MARK: - Implementing PersistedDiscussionLocalConfigurationDelegate

extension IntentManager: PersistedDiscussionLocalConfigurationObserver {
    
    func aPersistedDiscussionLocalConfigurationWasUpdated(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, value: ObvUICoreData.PersistedDiscussionLocalConfigurationValue) async {
     
        guard case .performInteractionDonation(let performInteractionDonation) = value else { return }

        // Check whether the user locally disabled interaction donations
        let donationDisabledLocally = performInteractionDonation == false

        // Check whether the user locally set the interaction donation to `default` AND disabled the global interaction donation setting
        let donationDisabledGlobally = performInteractionDonation == nil && ObvMessengerSettings.Discussions.performInteractionDonation == false

        // If one of the two above conditions holds, we should delete all donations for the discussion
        guard donationDisabledLocally || donationDisabledGlobally else { return }

        ObvCommunicationInteractor.delete(with: discussionIdentifier)
        
    }

    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedDiscussionLocalConfigurationChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        // We do nothing in this manager
    }

}


// MARK: - Reacting to global settings changes

extension IntentManager {

    /// If the global interaction donation setting is disabled, we remove donations for all discussions for which the local interaction donation setting is set to `default`
    private func obvMessengerSettingsDiscussionsPerformInteractionDonationDidChange(performInteractionDonation: Bool) async {

        guard !performInteractionDonation else { return }

        do {
            
            let discussionIdentifiers = try await getIdentifiersOfActiveDiscussionsWithDefaultPerformInteractionDonation()
            
            for discussionIdentifier in discussionIdentifiers {
                ObvCommunicationInteractor.delete(with: discussionIdentifier)
            }
            
        } catch {
            Self.logger.fault("Failed to process global settings change: \(error)")
            assertionFailure()
        }
        
    }
    
    
    private func getIdentifiersOfActiveDiscussionsWithDefaultPerformInteractionDonation() async throws -> [ObvDiscussionIdentifier] {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvDiscussionIdentifier], any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let discussionIdentifiers = try PersistedDiscussion.getIdentifiersOfActiveDiscussionsWithDefaultPerformInteractionDonation(within: context)
                    return continuation.resume(returning: discussionIdentifiers)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
}
