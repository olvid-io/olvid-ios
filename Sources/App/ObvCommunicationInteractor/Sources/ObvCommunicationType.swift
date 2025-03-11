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
import ObvTypes
import ObvUICoreDataStructs


public enum ObvCommunicationType {
    
    case incomingReaction(reactor: PersistedObvContactIdentityStructure, sentMessageReactedTo: PersistedMessageSentStructure)

    case incomingMessage(contact: PersistedObvContactIdentityStructure, discussionKind: PersistedDiscussionAbstractStructure.StructureKind, messageRepliedTo: RepliedToMessageStructure?, mentions: [ObvCryptoId])
    case outgoingMessage(sentMessage: PersistedMessageSentStructure)
    
    case callLog(callLog: PersistedCallLogItemStructure)
    
//    public func peopleInvolved(_ peopleInvolved: ObvPeopleInvolved) -> ObvCommunicationInformation {
//        return ObvCommunicationInformation(type: self, peopleInvolved: peopleInvolved)
//    }

}


//public enum ObvPeopleInvolved {
//    
//    case group(GroupInformation)
//    case oneOnOne(OneOnOneInformation)
//    
//    public struct GroupInformation {
//        let sender: ObvUserIdentity
//        let relevantRecipients: [ObvUserIdentity]
//        let recipientCount: Int
//        let groupIdentifier: ObvGroupIdentifier
//        let groupName: String
//        let photoURL: URL?
//        let isReplyToCurrentUser: Bool
//        let mentionsCurrentUser: Bool
//    }
//    
//    public struct OneOnOneInformation {
//        
//        let sender: ObvUserIdentity
//        let recipient: ObvUserIdentity
//        
//        public init(sender: ObvUserIdentity, recipient: ObvUserIdentity) {
//            self.sender = sender
//            self.recipient = recipient
//        }
//        
//    }
//    
//}


//public struct ObvCommunicationInformation {
//    
//    let type: ObvCommunicationType
//    let peopleInvolved: ObvPeopleInvolved
//
//    var conversationIdentifier: String {
//        switch peopleInvolved {
//        case .group(let groupInformation):
//            switch groupInformation.groupIdentifier {
//            case .groupV1(let groupIdentifier):
//                return groupIdentifier.description
//            case .groupV2(let groupIdentifier):
//                return groupIdentifier.description
//            }
//        case .oneOnOne(let oneOnOneInformation):
//            switch oneOnOneInformation.sender {
//            case .owned(_):
//                break
//            case .contact(let obvContactIdentity):
//                return obvContactIdentity.contactIdentifier.description
//            }
//            switch oneOnOneInformation.recipient {
//            case .owned(_):
//                break
//            case .contact(let obvContactIdentity):
//                return obvContactIdentity.contactIdentifier.description
//            }
//            assertionFailure("We expect either the sender or the recipient to be a contact")
//            return ""
//        }
//    }
//    
//}
