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
import ObvOwnedIdentityChooser
import ObvAppTypes
import ObvDiscussionChooser
import ObvTypes

@MainActor
public protocol ShareExtensionViewActions: OwnedIdentityChooserNavigationStackActions, DiscussionChooserNavigationStackActions, ShareComposeViewActions {
    func userWantsToCloseShare(from view: ShareExtensionView)
    /// Called when the user switches between HD and SD, so that the choice is remembered for the next share.
    /// The view has already applied it to the shared state; this is only about keeping it.
    func userChoseMediaQuality(_ mediaQuality: ObvMediaQuality)
}

@MainActor
public protocol ShareExtensionViewDataSource: OwnedIdentityChooserViewDataSource, DiscussionChooserViewDataSource, DiscussionItemViewDataSource, SingleRecipientSummaryViewDataSource {
    func getInitialShareExtensionViewModel(currentOwnedCryptoId: ObvCryptoId?) -> ShareExtensionView.Model
    func getAsyncSequenceOfShareExtensionViewModel(_ view: ShareExtensionView, currentOwnedCryptoId: ObvCryptoId?) async throws -> (streamUUID: UUID, stream: AsyncStream<ShareExtensionView.Model>)
    func finishAsyncSequenceOfShareExtensionViewModel(_ view: ShareExtensionView, streamUUID: UUID)
}
