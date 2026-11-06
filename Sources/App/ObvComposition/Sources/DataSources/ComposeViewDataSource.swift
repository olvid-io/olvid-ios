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
import ObvAppTypes

@MainActor
public protocol ComposeViewDataSource: AnyObject {
    
    func getInitialComposeViewDataSourceModel(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) -> ComposeViewDataSourceModel?
    func getAsyncStreamOfComposeViewDataSourceModel(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ComposeViewDataSourceModel>)
    func finishAsyncStreamOfComposeViewDataSourceModel(_ view: ComposeView, streamUUID: UUID)

    /// How far the exports of the draft's videos have got, between 0 and 1, or nil when none is running: the current value, then every
    /// change. A new stream per call, which ends when its consumer stops iterating it.
    func getAsyncStreamOfTheProgressOfTheVideosBeingPrepared(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) -> AsyncStream<Double?>

}

