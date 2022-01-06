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

extension InvitationsCollectionViewController {
    
    struct Strings {
        
        struct InviteSent {
            static let subtitle = NSLocalizedString("Your invitation was sent", comment: "Invitation subtitle")
            static let details = { (name: String) in
                String.localizedStringWithFormat(NSLocalizedString("If %@ accepts your invitation, you will be notified here.", comment: "Invitation details"), name)
            }
        }
        
        struct AcceptInvite {
            static let subtitle = NSLocalizedString("Invitation received", comment: "Invitation subtitle")
            static let details = { (name: String) in
                String.localizedStringWithFormat(NSLocalizedString("The invitation appears to come from %@. If you accept this invitation you will guided through the process allowing to make sure that this is the case.", comment: "Invitation details"), name)
            }
            static let buttonTitle2 = NSLocalizedString("Ignore", comment: "Button title")
        }

        struct InvitationAccepted {
            static let subtitle = NSLocalizedString("Invitation accepted", comment: "Invitation subtitle")
            static let details = { (name: String) in
                String.localizedStringWithFormat(NSLocalizedString("We are bootstraping the secure channel between you and %@. Please note that this requires %@'s device to be online.", comment: "Invitation details"), name, name)
            }
        }

        struct SasExchange {
            static let subtitle = NSLocalizedString("Exchange digits", comment: "Invitation subtitle")
            static let details = { (name: String, sas: String) in
                String.localizedStringWithFormat(NSLocalizedString("You should communicate your four digits to %@. Your digits are %@. You should also enter the 4 digits of %@.", comment: "Invitation details"), name, sas, name)
            }
        }

        struct SasConfirmed {
            static let subtitle = NSLocalizedString("Digits confirmed", comment: "Invitation subtitle")
            static let details = { (name: String, sas: String) in
                String.localizedStringWithFormat(NSLocalizedString("You have successfully entered the 4 digits of %1$@. You should communicate your four digits to %1$@. Your digits are %2$@.", comment: "Invitation details"), name, sas)
            }
        }

        struct MutualTrustConfirmed {
            static let subtitle = NSLocalizedString("Mutual Trust Confirmed", comment: "Invitation subtitle")
            static let details = { (name: String) in
                String.localizedStringWithFormat(NSLocalizedString("Well done! You trust %@'s identity and %@ now trusts yours back. A secure channel between you and %@ is being established. As soon as it will be, %@ will appear in your contacts. Please note that this requires %@'s device to be online.", comment: "Invitation details"), name, name, name, name, name)
            }

        }

        static let showContactButtonTitle = NSLocalizedString("Show Contact", comment: "Button title allowing to navigation towards a contact")

        struct AutoconfirmedContactIntroduction {
            static let subtitle = CommonString.Title.newContact
            static let details = { (mediatorName: String, contactName: String) in
                String.localizedStringWithFormat(NSLocalizedString("%@ was added to your contacts following an introduction by %@.", comment: "Invitation details"), contactName, mediatorName)
            }
        }

        struct AcceptMediatorInvite {
            static let subtitle = CommonString.Title.newSuggestedIntroduction
            static let details = { (mediatorName: String, contactName: String) in
                String.localizedStringWithFormat(NSLocalizedString("%@ wants to introduce you to %@. If you do trust %@ for this, you may accept this invitation and %@ will soon appear in your contacts, with no further actions from your part (provided that %@ also accepts the invitation). If you don't trust %@ or if you simply do not want to be introduced to %@ you can ignore this invitation (neither %@ nor %@ will be notified of this).", comment: "Invitation details"), mediatorName, contactName, mediatorName, contactName, contactName, mediatorName, contactName, contactName, mediatorName)
            }
            static let buttonTitle2 = NSLocalizedString("Ignore", comment: "Button title")
        }

        struct MediatorInviteAccepted {
            static let subtitle = NSLocalizedString("Introduction Accepted", comment: "Invitation subtitle")
            static let details = { (mediatorName: String, contactName: String) in
                String.localizedStringWithFormat(NSLocalizedString("You accepted to be introduced to %@ by %@. Please wait until %@ also accepts this invitation.", comment: "Invitation details"), contactName, mediatorName, contactName)
            }
        }
        
        struct IncreaseMediatorTrustLevelRequired {
            static let subtitle = AcceptInvite.subtitle
            static let details = { (mediatorName: String, contactName: String) in
                String.localizedStringWithFormat(NSLocalizedString("%1@ wants to introduce you to %2@.\n\nOlvid\'s security policy requires you to re-validate the identity of %2@ by exchanging 4-digit codes with them, or to invite %1@ directly.", comment: "Invitation details"), contactName, mediatorName, contactName)
            }
            static let buttonTitle1 = { (mediatorName: String) in String.localizedStringWithFormat(NSLocalizedString("Exchange digits with %@", comment: "Button title"), mediatorName) }
            static let buttonTitle2 = { (contactName: String) in String.localizedStringWithFormat(NSLocalizedString("Invite %@", comment: "Button title"), contactName) }
        }

        struct AcceptGroupInvite {
            static let subtitle = CommonString.Title.invitationToJoinGroup
            static let details = { (groupOwnerName: String) in
                String.localizedStringWithFormat(NSLocalizedString("You are invited to join a group created by %@. You may silently discard this invitation or accept it. In the latter case, each of the group member will appear in your contacts.", comment: "Invitation details"), groupOwnerName)
            }
            static let subsubTitle = NSLocalizedString("Group Members:", comment: "Title before the list of group members.")
        }

        struct GroupJoined {
            static let subtitle = NSLocalizedString("New Group Joined", comment: "Invitation subtitle")
            static let details = { (groupOwnerName: String) in
                String.localizedStringWithFormat(NSLocalizedString("You have joined a group created by %@.", comment: "Invitation details"), groupOwnerName)
            }
            static let showGroupButtonTitle = NSLocalizedString("Show Group", comment: "Button title allowing to navigation towards a contact group")
        }
        
        struct IncreaseGroupOwnerTrustLevelRequired {
            static let subtitle = AcceptInvite.subtitle
            static let details = { (groupOwnerName: String) in
                String.localizedStringWithFormat(NSLocalizedString("%1$@ is inviting you to a discussion group.\n\nOlvid\'s security policy requires you to re-validate the identity of %1$@ by exchanging 4-digit codes with them.", comment: "Invitation details"), groupOwnerName)
            }
            static let buttonTitle = { (groupOwnerName: String) in String.localizedStringWithFormat(NSLocalizedString("Exchange digits with %@", comment: "Button title"), groupOwnerName) }
        }

        struct GroupCreated {
            static let subtitle = NSLocalizedString("Group Created", comment: "Invitation subtitle")
            static let details = { (groupOwnerName: String) in
                String.localizedStringWithFormat(NSLocalizedString("All the members of the group created by %@ have accepted the invitation.", comment: "Invitation details"), groupOwnerName)
            }
            static let subsubTitle = NSLocalizedString("Confirmed Group Members:", comment: "Title before the list of group members.")
        }
        
        struct AbandonInvitation {
            static let title = NSLocalizedString("Discard this invitation?", comment: "Action title")
            static let actionTitleDiscard = NSLocalizedString("Discard invitation", comment: "Action title")
            static let actionTitleDontDiscard = NSLocalizedString("Do not discard invitation", comment: "Action title")
        }
        
        struct AbandonGroupCreation {
            static let title = NSLocalizedString("Discard this group creation?", comment: "Action title")
            static let message = NSLocalizedString("The other group members will not be notified.", comment: "Action message")
            static let actionTitleDiscard = NSLocalizedString("Discard group creation", comment: "Action title")
            static let actionTitleDontDiscard = NSLocalizedString("Do not discard group creation", comment: "Action title")
        }
                
        static let chipTitleActionRequired = NSLocalizedString("Action Required", comment: "Chip title")
        static let chipTitleNew = NSLocalizedString("New", comment: "Chip title")
        static let chipTitleUpdated = NSLocalizedString("Updated", comment: "Chip title")
        
        struct IncorrectSASAlert {
            static let title = NSLocalizedString("Incorrect code", comment: "Title of an alert")
            static let message = NSLocalizedString("The core you entered is incorrect. The code you need to enter is the one displayed on your contact's device.", comment: "Message of an alert")
        }
        
    }
    
}
