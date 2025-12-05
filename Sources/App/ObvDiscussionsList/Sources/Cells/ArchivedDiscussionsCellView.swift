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

import SwiftUI
import ObvDesignSystem
import ObvTypes


public struct ObvArchivedDiscussionsCellModel: Sendable, Equatable {
    let atLeastOneDiscussionIsArchived: Bool
    let numberOfArchivedPersistedDiscussionsWithNewMessages: Int
    public init(atLeastOneDiscussionIsArchived: Bool, numberOfArchivedPersistedDiscussionsWithNewMessages: Int) {
        self.atLeastOneDiscussionIsArchived = atLeastOneDiscussionIsArchived
        self.numberOfArchivedPersistedDiscussionsWithNewMessages = numberOfArchivedPersistedDiscussionsWithNewMessages
    }
    
}


@MainActor
protocol ArchivedDiscussionsCellActionsProtocol: AnyObject, Sendable {
    func userWantsToNavigateToListOfArchivedDiscussions()
}


@MainActor
public protocol ArchivedDiscussionsCellDataSource: AnyObject, Sendable {
    func getAsyncStreamOfObvArchivedDiscussionsCellModel(_ view: ObvDiscussionsListView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvArchivedDiscussionsCellModel>)
    func finishAsyncStreamOfObvArchivedDiscussionsCellModel(_ view: ObvDiscussionsListView, streamUUID: UUID)
}




struct ArchivedDiscussionsCellView: View {

    let viewModel: ObvArchivedDiscussionsCellModel
    let actions: ArchivedDiscussionsCellActionsProtocol

    private func cellTapped() {
        actions.userWantsToNavigateToListOfArchivedDiscussions()
    }
    
    private let avatarViewModel = ObvAvatarViewModel(
        characterOrIcon: .icon(.archivebox),
        colors: .init(foreground: .secondaryLabel, background: .quaternarySystemFill),
        photoURL: nil)
    
    public var body: some View {
        Button(action: cellTapped) {
            HStack(alignment: .firstTextBaseline) {
                ObvAvatarView(model: avatarViewModel, style: .iconOnly, size: .normal, dataSource: nil)
                Text("ARCHIVED_CELL_TITLE")
                    .foregroundStyle(.primary)
                    .font(.system(.headline, design: .rounded))
                    .badge(viewModel.numberOfArchivedPersistedDiscussionsWithNewMessages > 0 ? Text(String(viewModel.numberOfArchivedPersistedDiscussionsWithNewMessages)).font(.headline).foregroundColor(.blue) : nil)
                    .contentTransitionOniOS16(.numericText(value: Double(viewModel.numberOfArchivedPersistedDiscussionsWithNewMessages)))
            }
        }
    }
    
}
