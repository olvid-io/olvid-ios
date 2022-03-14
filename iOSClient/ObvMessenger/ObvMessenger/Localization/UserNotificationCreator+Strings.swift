/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


extension UserNotificationCreator {
    
    struct Strings {
        
        struct NewPersistedMessageReceivedMinimal {
            static let title = NSLocalizedString("Olvid", comment: "")
            static let body = NSLocalizedString("Olvid requires your attention", comment: "")
        }
        
        struct NewPersistedMessageReceived {
            static let body = { (firstAttachmentName: String, numberOfOtherAttachments: Int) -> String in
                let s1 = String.localizedStringWithFormat(NSLocalizedString("%@ and", comment: ""), firstAttachmentName)
                let s2 = String.localizedStringWithFormat(NSLocalizedString("n more attachments", comment: "Notification body"), numberOfOtherAttachments)
                return [s1, s2].joined(separator: " ")
            }
        }
        
        struct NewPersistedMessageReceivedHiddenContent {
            static let title = NSLocalizedString("New message", comment: "")
            static let body = NSLocalizedString("Tap to see the message", comment: "")
        }

        struct NewPersistedReactionReceivedHiddenContent {
            static let title = NSLocalizedString("NEW_REACTION", comment: "")
            static let body = NSLocalizedString("TAP_TO_SEE_THE_REACTION", comment: "")
        }

        struct NewInvitationReceivedHiddenContent {
            static let title = NSLocalizedString("New invitation", comment: "")
            static let body = NSLocalizedString("Tap to see the invitation", comment: "")
        }

        struct AcceptInvite {
            static let title = NSLocalizedString("New Invitation!", comment: "Notification title")
            static let body = { (contactIdentityDisplayName: String) in
                String.localizedStringWithFormat(NSLocalizedString("You receive a new invitation from %@. You can accept or silently discard it.", comment: "Notification body"), contactIdentityDisplayName)
                
            }
        }
        
        struct SasExchange {
            static let title = NSLocalizedString("An invitation requires your attention!", comment: "Notification title")
            static let body = { (contactIdentityDisplayName: String) in
                String.localizedStringWithFormat(NSLocalizedString("Your are one step away to create a secure channel with %@!", comment: "Notification body"), contactIdentityDisplayName)
                
            }
        }
        
        struct MutualTrustConfirmed {
            static let title = NSLocalizedString("Mutual trust confirmed!", comment: "Notification title")
            static let body = { (contactIdentityDisplayName: String) in
                String.localizedStringWithFormat(NSLocalizedString("You now appear in %@'s contacts list. A secure channel is being established. When this is done, you will be able to exchange confidential messages and more!", comment: "Notification body"), contactIdentityDisplayName)
                
            }
        }
        
        struct AcceptMediatorInvite {
            static let title = CommonString.Title.newSuggestedIntroduction
            static let body = { (mediatorDisplayName: String, contactDisplayName: String) in
                String.localizedStringWithFormat(NSLocalizedString("%@ wants to introduce you to %@", comment: "Notification body"), mediatorDisplayName, contactDisplayName)
                
            }
        }
        
        struct AcceptGroupInvite {
            static let title = CommonString.Title.invitationToJoinGroup
            static let body = { (contactIdentityDisplayName: String) in
                String.localizedStringWithFormat(NSLocalizedString("You are invited to join a group created by %@.", comment: "Notification body"), contactIdentityDisplayName)
                
            }
        }

        struct AutoconfirmedContactIntroduction {
            static let title = CommonString.Title.newContact
            static let body = { (mediatorName: String, contactName: String) in
                String.localizedStringWithFormat(NSLocalizedString("%@ was added to your contacts following an introduction by %@.", comment: "Invitation details"), contactName, mediatorName)
            }
        }
        
        struct IncreaseMediatorTrustLevelRequired {
            static let title = NSLocalizedString("Invitation received", comment: "Invitation subtitle")
            static let body = { (mediatorName: String, contactName: String) in
                String.localizedStringWithFormat(NSLocalizedString("%1$@ wants to introduce you to %2$@.", comment: "Invitation details"), mediatorName, contactName)
            }
        }
        
        struct MissedCall {
            static let title = NSLocalizedString("MISSED_CALL", comment: "")
        }
        
    }
    
}
