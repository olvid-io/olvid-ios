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
import AVKit

struct CallMessageContent {
    let dateString: String?
    let isIncoming: Bool
    let participant: String?
    let othersCount: Int?
    let duration: Int? // In seconds
}

extension PersistedMessageSystem {
    
    struct Strings {
        
        static let ownedIdentityDidCaptureSensitiveMessages = NSLocalizedString("YOU_CAPTURED_SENSITIVE_CONTENT_WARNING_MESSAGE", comment: "")
        static let contactIdentityDidCaptureSensitiveMessages: (String?) -> String = { (contactDisplayName: String?) in
            if let contactDisplayName {
                return String.localizedStringWithFormat(NSLocalizedString("CONTACT_CAPTURED_SENSITIVE_CONTENT_WARNING_MESSAGE_%@", comment: ""), contactDisplayName)
            } else {
                return NSLocalizedString("CONTACT_CAPTURED_SENSITIVE_CONTENT_WARNING_MESSAGE_WHEN_CONTACT_IS_UNKNOWN", comment: "")
            }
        }
        
        static let ownedIdentityIsPartOfGroupV2Admins = NSLocalizedString("YOU_ARE_NOW_PART_OF_THE_ADMINISTRATORS_OF_THIS_GROUP_V2", comment: "")
        static let ownedIdentityIsNoLongerPartOfGroupV2Admins = NSLocalizedString("YOU_ARE_NO_LONGER_PART_OF_THE_ADMINISTRATORS_OF_THIS_GROUP_V2", comment: "")

        static let membersOfGroupV2WereUpdated = NSLocalizedString("MEMBERS_OF_GROUP_V2_WERE_UPDATED_SYSTEM_MESSAGE", comment: "")
        
        static let contactJoinedGroup: (String, String?) -> String = { (contactDisplayName: String, dateString: String?) in
            if let dateString = dateString {
                return String.localizedStringWithFormat(NSLocalizedString("%@_ACCEPTED_TO_JOIN_THIS_GROUP_AT_%@", comment: "System message displayed within a group discussion"), contactDisplayName, dateString)
            } else {
                return String.localizedStringWithFormat(NSLocalizedString("%@_ACCEPTED_TO_JOIN_THIS_GROUP", comment: "System message displayed within a group discussion"), contactDisplayName)
            }
        }
        
        static let contactLeftGroup: (String, String?) -> String = { (contactDisplayName: String, dateString: String?) in
            if let dateString = dateString {
                return String.localizedStringWithFormat(NSLocalizedString("%@_LEFT_THIS_GROUP_AT_%@", comment: "System message displayed within a group discussion"), contactDisplayName, dateString)
            } else {
                return String.localizedStringWithFormat(NSLocalizedString("%@_LEFT_THIS_GROUP", comment: "System message displayed within a group discussion"), contactDisplayName)
            }
        }
        
        static let numberOfNewMessages = { (count: Int) in
            return String.localizedStringWithFormat(NSLocalizedString("count new messages", comment: "Number of new messages"), count)
        }

        static let discussionIsEndToEndEncrypted = NSLocalizedString("Messages posted in this discussion are protected using end-to-end encryption. Their confidentiality, their authenticity, and the identity of their sender are guaranteed through cryptography.", comment: "System message displayed at the top of each conversation.")
        
        static let contactWasDeleted = NSLocalizedString("This contact was deleted from your contacts, either because you did or because this contact deleted you.", comment: "System message displayed within a group discussion")

        private static func callMessageContent(content: CallMessageContent, title: String) -> String {
            var result = title
            if let participant = content.participant {
                result += " "
                if content.isIncoming {
                    result += String.localizedStringWithFormat(NSLocalizedString("FROM_%@", comment: ""), participant)
                } else {
                    result += String.localizedStringWithFormat(NSLocalizedString("WITH_%@", comment: ""), participant)
                }
                if let otherCount = content.othersCount, otherCount >= 1 {
                    result += " "
                    if otherCount == 1 {
                        result += NSLocalizedString("AND_ONE_OTHER", comment: "")
                    } else {
                        result += String.localizedStringWithFormat(NSLocalizedString("AND_%@_OTHERS", comment: ""), String(otherCount))
                    }
                }
            } else if let otherCount = content.othersCount, otherCount >= 1 {
                result += " "
                if otherCount == 1 {
                    result += NSLocalizedString("WITH_ONE_PARTICIPANT", comment: "")
                } else {
                    result += String.localizedStringWithFormat(NSLocalizedString("WITH_%@_PARTICIPANTS", comment: ""), String(otherCount))
                }
            }
            if let dateString = content.dateString {
                result += " - "
                result += dateString
            }
            return result
        }

        static let missedIncomingCall = { (content: CallMessageContent) in
            callMessageContent(content: content,
                               title: NSLocalizedString("MISSED_CALL", comment: ""))
        }

        static let filteredIncomingCall = { (content: CallMessageContent) in
            callMessageContent(content: content,
                               title: NSLocalizedString("MISSED_CALL_FILTERED", comment: ""))
        }

        static let acceptedOutgoingCall = { (content: CallMessageContent) in
            callMessageContent(content: content,
                               title: NSLocalizedString("ACCEPTED_OUTGOING_CALL", comment: ""))
        }

        static let acceptedIncomingCall = { (content: CallMessageContent) in
            callMessageContent(content: content,
                               title: NSLocalizedString("ACCEPTED_INCOMING_CALL", comment: ""))
        }

        static let rejectedOutgoingCall = { (content: CallMessageContent) in
            callMessageContent(content: content,
                               title: NSLocalizedString("REJECTED_OUTGOING_CALL", comment: ""))
        }

        static let rejectedIncomingCall = { (content: CallMessageContent) in
            callMessageContent(content: content,
                               title: NSLocalizedString("REJECTED_INCOMING_CALL", comment: ""))
        }

        static let busyOutgoingCall = { (content: CallMessageContent) in
            callMessageContent(content: content,
                               title: NSLocalizedString("BUSY_OUTGOING_CALL", comment: ""))
        }

        static let unansweredOutgoingCall = { (content: CallMessageContent) in
            callMessageContent(content: content,
                               title: NSLocalizedString("UNANSWERED_OUTGOING_CALL", comment: ""))
        }

        static let uncompletedOutgoingCall = { (content: CallMessageContent) in
            callMessageContent(content: content,
                               title: NSLocalizedString("UNCOMPLETED_OUTGOING_CALL", comment: ""))
        }

        static let anyIncomingCall = { (content: CallMessageContent) in
            callMessageContent(content: content,
                               title: NSLocalizedString("ANY_INCOMING_CALL", comment: ""))
        }

        static let anyOutgoingCall = { (content: CallMessageContent) in
            callMessageContent(content: content,
                               title: NSLocalizedString("ANY_OUTGOING_CALL", comment: ""))
        }
        
        static let contactRevokedByIdentityProvider = NSLocalizedString("CONTACT_REVOKED_BY_COMPANY_IDENTITY_PROVIDER", comment: "")
        
        static let notPartOfTheGroupAnymore = NSLocalizedString("NOT_PART_OF_THE_GROUP_ANYMORE", comment: "")
        
        static let rejoinedGroup = NSLocalizedString("REJOINED_GROUP", comment: "")
        
        static func contactIsOneToOneAgain(contactName: String) -> String {
            return String.localizedStringWithFormat(NSLocalizedString("CONTACT_%@_IS_ONE_TO_ONE_AGAIN", comment: ""), contactName)
        }

        static let rejectedIncomingCallBecauseOfDeniedRecordPermission = { (content: CallMessageContent) -> String in
            let title: String
            switch AVAudioSession.sharedInstance().recordPermission {
            case .undetermined:
                title = NSLocalizedString("REJECTED_INCOMING_CALL_BECAUSE_RECORD_PERMISSION_IS_UNDETERMINED", comment: "")
            case .granted:
                title = NSLocalizedString("REJECTED_INCOMING_CALL_BECAUSE_RECORD_PERMISSION_IS_GRANTED", comment: "")
            case .denied:
                title = NSLocalizedString("REJECTED_INCOMING_CALL_BECAUSE_RECORD_PERMISSION_IS_DENIED", comment: "")
            @unknown default:
                assertionFailure()
                title = NSLocalizedString("REJECTED_INCOMING_CALL", comment: "")
            }
            return callMessageContent(content: content, title: title)
        }

        static let updatedDiscussionSettings =  NSLocalizedString("DISCUSSION_SHARED_SETTINGS_WERE_UPDATED", comment: "")
        
        static let discussionWasRemotelyWiped: (String, String?) -> String = { (contactDisplayName: String, dateString: String?) in
            if let dateString = dateString {
                return String.localizedStringWithFormat(NSLocalizedString("This discussion was remotely wiped by %@ on %@", comment: "System message displayed within a group discussion"), contactDisplayName, dateString)
            } else {
                return String.localizedStringWithFormat(NSLocalizedString("This discussion was remotely wiped by %@", comment: "System message displayed within a group discussion"), contactDisplayName)
            }
        }

    }
    
}
