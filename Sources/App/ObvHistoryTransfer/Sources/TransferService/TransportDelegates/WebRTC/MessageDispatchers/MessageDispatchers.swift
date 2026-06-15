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


struct MessageDispatchers {
    let srcDiscussionRangesMessageDispatcher = SrcDiscussionRangesMessageDispatcher()
    let srcDiscussionListMessageDispatcher = SingleMessageDispatcher<SrcDiscussionList>()
    let dstDiscussionExpectedRangesMessageDispatcher = DstDiscussionExpectedRangesMessageDispatcher()
    let dstExpectedSha256MessageDispatcher = SingleMessageDispatcher<DstExpectedSha256>()
    let srcMessagesDispatcher = SrcMessagesDispatcher()
    let srcSha256Dispatcher = SrcSha256Dispatcher(temporaryDirectory: FileManager.default.temporaryDirectory)
    let dstRequestSha256sDispatcher = DstRequestSha256sDispatcher()
    let ackDispatcher = AckDispatcher()
}


extension MessageDispatchers {
    
    func finishAllDispatchesByThrowing(_ error: any Error) async {
        await srcDiscussionRangesMessageDispatcher.finishAllDispatchesByThrowing(error)
        await srcDiscussionListMessageDispatcher.finishAllDispatchesByThrowing(error)
        await dstDiscussionExpectedRangesMessageDispatcher.finishAllDispatchesByThrowing(error)
        await dstExpectedSha256MessageDispatcher.finishAllDispatchesByThrowing(error)
        await srcMessagesDispatcher.finishAllDispatchesByThrowing(error)
        await srcSha256Dispatcher.finishAllDispatchesByThrowing(error)
        await dstRequestSha256sDispatcher.finishAllDispatchesByThrowing(error)
        await ackDispatcher.finishAllDispatchesByThrowing(error)
    }
    
}
