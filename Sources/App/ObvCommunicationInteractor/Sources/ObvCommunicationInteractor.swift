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
import UserNotifications
import Intents
import ObvAppTypes
import ObvSettings
import OlvidUtils


public final class ObvCommunicationInteractor {
    
    /// Outgoing messages and calls suggest people involved for Focus breakthrough.
    public static func suggest(communicationType: ObvCommunicationType) async throws -> INInteraction {
        // Create an INInteraction.
        let interaction = try ObvCommunicationMapper.interaction(communicationType: communicationType)
        try await donateIfAllowed(interaction, for: communicationType)
        return interaction
    }


    /// A donation shows the people and groups involved outside Olvid (share sheet, Spotlight), so it only happens when the discussion allows it,
    /// and never for a hidden profile. This holds for incoming communications too, which are the bulk of donations.
    private static func donateIfAllowed(_ interaction: INInteraction, for communicationType: ObvCommunicationType) async throws {
        let discussionKind = communicationType.discussionKind
        guard discussionKind.localConfiguration.performInteractionDonation && !discussionKind.ownedIdentity.isHidden else { return }
        try await interaction.donate()
    }
    
    
    public static func delete(with discussionIdentifier: ObvDiscussionIdentifier) {
        let groupIdentifier = discussionIdentifier.description
        INInteraction.delete(with: groupIdentifier)
    }

    
    /// Update incoming notifications with a message or call information to allow the following:
    /// - Display an avatar, if present.
    /// - Check if sender is allowed to break through.
    /// - Update notification title (sender's name) and subtitle (group information).
    public static func update(notificationContent: UNNotificationContent, communicationType: ObvCommunicationType) async throws -> UNNotificationContent {
        // What this adds cannot be removed afterwards, so it must never happen to a notification whose content the user hides
        guard ObvMessengerSettings.Privacy.hideNotificationContent == .no else {
            return notificationContent
        }
        let interaction = try ObvCommunicationMapper.interaction(communicationType: communicationType)
        // A failed donation must not cost the notification its sender and avatar
        do {
            try await donateIfAllowed(interaction, for: communicationType)
        } catch {
            ObvDisplayableLogs.shared.log("[CommunicationInteractor] Could not donate the interaction: \(error.localizedDescription)")
        }
        guard let notificationContentProvider = interaction.intent as? UNNotificationContentProviding else {
            assertionFailure()
            throw ObvError.unexpectedIntentType
        }
        
        ObvDisplayableLogs.shared.log("[CommunicationInteractor] Will update the notification content with a UNNotificationContentProviding")

        let updatedContent = try notificationContent.updating(from: notificationContentProvider)
        return updatedContent
    }

}


// MARK: - Errors

extension ObvCommunicationInteractor {
    enum ObvError: Error {
        case unexpectedIntentType
    }
}
