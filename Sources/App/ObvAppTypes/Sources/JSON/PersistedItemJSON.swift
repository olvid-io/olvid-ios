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
import OSLog
import ObvTypes
import ObvCrypto
import OlvidUtils
import ObvTypes


public struct PersistedItemJSON: Codable {
    
    public let message: MessageJSON?
    public let returnReceipt: ReturnReceiptJSON?
    public let webrtcMessage: WebRTCMessageJSON?
    public let discussionSharedConfiguration: DiscussionSharedConfigurationJSON?
    public let deleteMessagesJSON: DeleteMessagesJSON?
    public let deleteDiscussionJSON: DeleteDiscussionJSON?
    public let querySharedSettingsJSON: QuerySharedSettingsJSON?
    public let updateMessageJSON: UpdateMessageJSON?
    public let reactionJSON: ReactionJSON?
    public let pollVoteJSON: PollVoteJSON?
    public let screenCaptureDetectionJSON: ScreenCaptureDetectionJSON?
    public let limitedVisibilityMessageOpenedJSON: LimitedVisibilityMessageOpenedJSON?
    public let discussionRead: DiscussionReadJSON?
    public let webrtcHistoryTransferMessageJSON: WebRTCHistoryTransferMessageJSON?
    public let webRTCHistoryTransferControlJSON: WebRTCHistoryTransferControlJSON?

    enum CodingKeys: String, CodingKey {
        case message = "message"
        case returnReceipt = "rr"
        case webrtcMessage = "rtc"
        case discussionSharedConfiguration = "settings"
        case deleteMessagesJSON = "delm"
        case deleteDiscussionJSON = "deld"
        case querySharedSettingsJSON = "qss"
        case updateMessageJSON = "upm"
        case reactionJSON = "reacm"
        case pollVoteJSON = "pvm"
        case screenCaptureDetectionJSON = "scd"
        case limitedVisibilityMessageOpenedJSON = "lvo"
        case discussionRead = "dr"
        case webrtcHistoryTransferMessageJSON = "ht"
        case webRTCHistoryTransferControlJSON = "htc"
    }
    
    public init(messageJSON: MessageJSON) {
        self.message = messageJSON
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }
    
    public init(returnReceiptJSON: ReturnReceiptJSON) {
        self.message = nil
        self.returnReceipt = returnReceiptJSON
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }
    
    public init(messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON) {
        self.message = messageJSON
        self.returnReceipt = returnReceiptJSON
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }
    
    public init(webrtcMessage: WebRTCMessageJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = webrtcMessage
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }
    
    public init(discussionSharedConfiguration: DiscussionSharedConfigurationJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = discussionSharedConfiguration
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }
    
    public init(deleteMessagesJSON: DeleteMessagesJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = deleteMessagesJSON
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }

    public init(deleteDiscussionJSON: DeleteDiscussionJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = deleteDiscussionJSON
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }
    
    public init(querySharedSettingsJSON: QuerySharedSettingsJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = querySharedSettingsJSON
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }

    public init(updateMessageJSON: UpdateMessageJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = updateMessageJSON
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }

    public init(reactionJSON: ReactionJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = reactionJSON
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }
    
    public init(pollVoteJSON: PollVoteJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = pollVoteJSON
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }

    public init(screenCaptureDetectionJSON: ScreenCaptureDetectionJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = screenCaptureDetectionJSON
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }

    public init(limitedVisibilityMessageOpenedJSON: LimitedVisibilityMessageOpenedJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = limitedVisibilityMessageOpenedJSON
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }

    public init(discussionRead: DiscussionReadJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = discussionRead
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = nil
    }
    
    public init(webrtcHistoryTransferMessageJSON: WebRTCHistoryTransferMessageJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = webrtcHistoryTransferMessageJSON
        self.webRTCHistoryTransferControlJSON = nil
    }

    public init(webRTCHistoryTransferControlJSON: WebRTCHistoryTransferControlJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.pollVoteJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
        self.webrtcHistoryTransferMessageJSON = nil
        self.webRTCHistoryTransferControlJSON = webRTCHistoryTransferControlJSON
    }

    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    public static func jsonDecode(_ data: Data) throws -> PersistedItemJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(PersistedItemJSON.self, from: data)
    }

}
