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
import ObvTypes
import ObvDesignSystem
import ObvCircleAndTitlesView


// MARK: - ReactionCellView's model

public struct ReactionCellViewModel: Sendable, Equatable {
    
    let avatar: ObvAvatarViewModel
    let displayName: String
    let date: Date
    let positionAndCompany: String?
    let reaction: Character
    let isOwnReaction: Bool
    let reactionIsPartOfPreferedReactions: Bool
    
    public init(avatar: ObvAvatarViewModel, displayName: String, date: Date, positionAndCompany: String?, reaction: Character, isOwnReaction: Bool, reactionIsPartOfPreferedReactions: Bool) {
        self.avatar = avatar
        self.displayName = displayName
        self.date = date
        self.positionAndCompany = positionAndCompany
        self.reaction = reaction
        self.isOwnReaction = isOwnReaction
        self.reactionIsPartOfPreferedReactions = reactionIsPartOfPreferedReactions
    }
    
    static func emptyModel() -> Self {
        .init(avatar: .init(characterOrIcon: .character(" "), colors: .init(foreground: .clear, background: .clear), photoURL: nil),
              displayName: " ",
              date: .now,
              positionAndCompany: " ",
              reaction: " ",
              isOwnReaction: false,
              reactionIsPartOfPreferedReactions: false)
    }
    
    var textViewModel: TextView.Model {
        .init(titlePart1: displayName,
              titlePart2: nil,
              subtitle: positionAndCompany,
              subsubtitle: date.formatted(.dateTime.year().month().day().hour().minute()))
    }

}


// MARK: - ReactionCellView's data source

@MainActor
public protocol ReactionCellViewDataSource {
    func getAsyncStreamOfReactionCellViewModel(reactionIdentifier: ObvMessageReactionsViewModel.ReactionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ReactionCellViewModel>)
    func finishAsyncStreamOfReactionCellViewModel(streamUUID: UUID)
}


@MainActor
protocol ReactionCellViewActionsProtocol {
    func userWantsToRemoveReaction(reactionIdentifier: ObvMessageReactionsViewModel.ReactionIdentifier) async throws
    func userWantsToAddReactionToFavorites(emoji: Character) async throws
    func userWantsToRemoveReactionFromFavorites(emoji: Character) async throws
}



// MARK: - ReactionCellView

struct ReactionCellView: View {
    
    let reactionIdentifier: ObvMessageReactionsViewModel.ReactionIdentifier
    let dataSource: ReactionCellViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: ReactionCellViewActionsProtocol

    @State private var model: ReactionCellViewModel?

    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfReactionCellViewModel(reactionIdentifier: reactionIdentifier)
            for await receivedModel in stream {
                withAnimation {
                    self.model = receivedModel
                }
            }
            dataSource.finishAsyncStreamOfReactionCellViewModel(streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    private func userWantsToRemoveReaction() {
        Task {
            do {
                try await actions.userWantsToRemoveReaction(reactionIdentifier: reactionIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func userWantsToAddReactionToFavorites() {
        guard let emoji = model?.reaction else { return }
        Task {
            do {
                try await actions.userWantsToAddReactionToFavorites(emoji: emoji)
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func userWantsToRemoveReactionFromFavorites() {
        guard let emoji = model?.reaction else { return }
        Task {
            do {
                try await actions.userWantsToRemoveReactionFromFavorites(emoji: emoji)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    @ViewBuilder
    private func swipeActions(model: ReactionCellViewModel) -> some View {
        if model.isOwnReaction {
            Button(action: userWantsToRemoveReaction) {
                Text("BUTTON_REMOVE_OWN_REACTION_FROM_MESSAGE")
            }.tint(.red)
        }
        if model.reactionIsPartOfPreferedReactions {
            Button(action: userWantsToRemoveReactionFromFavorites) {
                Text("BUTTON_REMOVE_REACTION_FROM_FAVORITES")
            }
        } else {
            Button(action: userWantsToAddReactionToFavorites) {
                Text("BUTTON_ADD_REACTION_FROM_FAVORITES")
            }
        }
    }
    
    
    @ViewBuilder
    private func menuActions(model: ReactionCellViewModel) -> some View {
        if model.isOwnReaction {
            Button(role: .destructive, action: userWantsToRemoveReaction) {
                Label {
                    Text("BUTTON_REMOVE_OWN_REACTION_FROM_MESSAGE")
                } icon: {
                    Image(systemIcon: .trash)
                }
            }.tint(.red)
        }
        if model.reactionIsPartOfPreferedReactions {
            Button(action: userWantsToRemoveReactionFromFavorites) {
                Label {
                    Text("BUTTON_REMOVE_REACTION_FROM_FAVORITES")
                } icon: {
                    Image(systemIcon: .starSlash)
                }

            }
        } else {
            Button(action: userWantsToAddReactionToFavorites) {
                Label {
                    Text("BUTTON_ADD_REACTION_FROM_FAVORITES")
                } icon: {
                    Image(systemIcon: .star)
                }
            }
        }
    }


    
    var body: some View {
        ReactionCellContentView(model: model ?? .emptyModel(),
                                avatarViewDataSource: avatarViewDataSource)
        .task(onTask)
        .swipeActions(allowsFullSwipe: false) {
            if let model {
                swipeActions(model: model)
            }
        }
        .contextMenu {
            if let model {
                menuActions(model: model)
            }
        }
    }
    
}


// MARK: - Internal view: ReactionCellContentView

private struct ReactionCellContentView: View {
    
    let model: ReactionCellViewModel
    let avatarViewDataSource: ObvAvatarViewDataSource

    var body: some View {
        HStack(alignment: .top) {
            ObvAvatarView(model: model.avatar,
                          style: .circle,
                          size: .normal,
                          dataSource: avatarViewDataSource)
            HStack(alignment: .center) {
                
                if #available(iOS 16, *) {
                    // Under iOS16+, we align the leading edge of the separator (required, as it otherwise automatically aligns on the character in the avatar view)
                    TextView(model: model.textViewModel)
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
                } else {
                    // Under iOS15, the separators are hidden (see `ObvMessageReactionsView`)
                    TextView(model: model.textViewModel)
                }

                Spacer()
                Text(String(model.reaction))
                    .font(.title)
            }
        }
    }
    
}


#if DEBUG

// - MARK: Previews

private final class ReactionCellViewDataSourceForPreviews: ReactionCellViewDataSource, ObvAvatarViewDataSource {
    
    func getAsyncStreamOfReactionCellViewModel(reactionIdentifier: ObvMessageReactionsViewModel.ReactionIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ReactionCellViewModel>) {
        let stream = AsyncStream<ReactionCellViewModel> { (continuation: AsyncStream<ReactionCellViewModel>.Continuation) in
            switch reactionIdentifier {
            case .objectID:
                assertionFailure("Not expected in previews")
                return
            case .forPreviews(let cryptoId):
                switch cryptoId {
                case ObvCryptoId.sampleDatasForOwnedCryptoId:
                    let model = ReactionCellViewModel.sampleDataForOwnedCryptoId(cryptoId)
                    continuation.yield(model)
                default:
                    let model = ReactionCellViewModel.sampleDataForContactCryptoId(cryptoId)
                    continuation.yield(model)
                }
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfReactionCellViewModel(streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    // ObvAvatarViewDataSource
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        return UIImage.sampleImageForURL(photoURL)
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return UIImage.sampleImageForURL(photoURL)
    }
    
}


@MainActor
private final class ActionsForPreviews: ReactionCellViewActionsProtocol {
    func userWantsToRemoveReaction(reactionIdentifier: ObvMessageReactionsViewModel.ReactionIdentifier) async throws {}
    func userWantsToAddReactionToFavorites(emoji: Character) async throws {}
    func userWantsToRemoveReactionFromFavorites(emoji: Character) async throws {}
}


private let dataSourceForPreviews = ReactionCellViewDataSourceForPreviews()
private let actionsForPreviews = ActionsForPreviews()

#Preview("Owned") {
    ZStack {
        Color(UIColor.secondarySystemBackground).ignoresSafeArea()
        ReactionCellView(reactionIdentifier: .forPreviews(ObvCryptoId.sampleDatasForOwnedCryptoId),
                         dataSource: dataSourceForPreviews,
                         avatarViewDataSource: dataSourceForPreviews,
                         actions: actionsForPreviews)
        .background(Color(UIColor.systemBackground))
    }
}

#Preview("Contact") {
    ReactionCellView(reactionIdentifier: .forPreviews(ObvCryptoId.sampleDatasForContactCryptoId[0]),
                     dataSource: dataSourceForPreviews,
                     avatarViewDataSource: dataSourceForPreviews,
                     actions: actionsForPreviews)
}


#Preview("Multiple") {
    List {
        ReactionCellView(reactionIdentifier: .forPreviews(ObvCryptoId.sampleDatasForOwnedCryptoId),
                         dataSource: dataSourceForPreviews,
                         avatarViewDataSource: dataSourceForPreviews,
                         actions: actionsForPreviews)
        ForEach(ObvCryptoId.sampleDatasForContactCryptoId, id: \.self) { contactCryptoId in
            ReactionCellView(reactionIdentifier: .forPreviews(contactCryptoId),
                             dataSource: dataSourceForPreviews,
                             avatarViewDataSource: dataSourceForPreviews,
                             actions: actionsForPreviews)
        }
    }
    .listStyle(.plain)
}

#endif
