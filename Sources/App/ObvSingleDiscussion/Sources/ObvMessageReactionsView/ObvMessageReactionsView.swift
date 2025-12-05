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
import CoreData
import ObvTypes
import ObvDesignSystem
import ObvAppCoreConstants


// MARK: - ObvMessageReactionsView's model

public struct ObvMessageReactionsViewModel: Equatable, Sendable {

    let reactionsIdentifiers: [ReactionIdentifier]
    
    public init(reactionsIdentifiers: [ReactionIdentifier]) {
        self.reactionsIdentifiers = reactionsIdentifiers
    }
    
    public enum MessageIdentifier: Equatable {
        case objectID(_ objectID: NSManagedObjectID) // NSManagedObjectID of a PersistedMessage (enforced by the datasource)
        case forPreview(_ uuid: UUID)
    }

    public enum ReactionIdentifier: Equatable, Identifiable, Sendable {
        case objectID(_ objectID: NSManagedObjectID) // NSManagedObjectID of a PersistedMessageReaction (enforced by the datasource)
        case forPreviews(_ fromCryptoId: ObvCryptoId)
        public var id: Data {
            switch self {
            case .objectID(let objectID):
                return objectID.uriRepresentation().dataRepresentation
            case .forPreviews(let fromCryptoId):
                return fromCryptoId.getIdentity()
            }
        }
    }
    
}



@MainActor
public protocol ObvMessageReactionsViewDataSource: AnyObject, ReactionCellViewDataSource, ReactionsCountViewDataSource {
    func getAsyncStreamOfObvMessageReactionsViewModel(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvMessageReactionsViewModel>)
    func finishAsyncStreamOfObvMessageReactionsViewModel(streamUUID: UUID)
}


@MainActor
protocol ObvMessageReactionsViewActionsProtocol: AnyObject, ReactionCellViewActionsProtocol {
    func userWantsToDismissObvMessageReactionsView()
}


public struct ObvMessageReactionsView: View {
    
    let messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier
    let dataSource: ObvMessageReactionsViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: ObvMessageReactionsViewActionsProtocol

    @State private var model: ObvMessageReactionsViewModel?

    @State private var showInfoPopover: Bool = false
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfObvMessageReactionsViewModel(messageIdentifier: messageIdentifier)
            for await receivedModel in stream {
                withAnimation {
                    self.model = receivedModel
                }
            }
            dataSource.finishAsyncStreamOfObvMessageReactionsViewModel(streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    private func okButtonTapped() {
        actions.userWantsToDismissObvMessageReactionsView()
    }
    
    
    public var body: some View {
        ObvMessageReactionsContentView(messageIdentifier: messageIdentifier,
                                       dataSource: dataSource,
                                       avatarViewDataSource: avatarViewDataSource,
                                       actions: actions,
                                       model: model)
        .task(onTask)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                ObvButtonWithCancelRole(action: okButtonTapped)
            }
            ToolbarItem {
                Menu {
                    Label { Text(ObvAppCoreConstants.targetEnvironmentIsMacCatalyst ? "DOUBLE_CLICK_A_MESSAGE_TO_ADD_A_REACTION" : "DOUBLE_TAP_A_MESSAGE_TO_ADD_A_REACTION") } icon: { Image(systemIcon: ObvAppCoreConstants.targetEnvironmentIsMacCatalyst ? .cursorarrowClick2 : .handTap) }
                    Divider()
                    if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
                        Label { Text("RIGHT_CLICK_ON_A_REACTION_TO_SHOW_MORE_OPTIONS") } icon: { Image(systemIcon: .cursorarrowClick) }
                    } else {
                        Label { Text("SWIPE_RIGHT_ON_A_REACTION_TO_SHOW_MORE_OPTIONS") } icon: { Image(systemIcon: .appwindowSwipeRectangle) }
                    }
                } label: {
                    Image(systemIcon: .infoCircle)
                }
            }
        }
        .navigationTitle(Text("REACTIONS"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
}


private struct ObvMessageReactionsContentView: View {
    
    let messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier
    let dataSource: ObvMessageReactionsViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let actions: ObvMessageReactionsViewActionsProtocol
    let model: ObvMessageReactionsViewModel?

    var body: some View {
        
        VStack {
            
            // List of reactions
            
            if let model {
                List {
                    ForEach(model.reactionsIdentifiers) { reactionIdentifier in
                        ReactionCellView(reactionIdentifier: reactionIdentifier,
                                         dataSource: dataSource,
                                         avatarViewDataSource: avatarViewDataSource,
                                         actions: actions)
                    }
                }
                .contentMarginsOniOS17(.top, .init(top: 0, leading: 0, bottom: 0, trailing: 0))
            } else {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            
            Spacer(minLength: 0)
            
            // Bottom view showing the reactions/counts
            
            Group {
                ViewThatFits {
                    HStack {
                        Spacer(minLength: 0)
                        ReactionsCountView(messageIdentifier: messageIdentifier,
                                           dataSource: dataSource)
                        Spacer(minLength: 0)
                    }
                    ScrollView(.horizontal) {
                        ReactionsCountView(messageIdentifier: messageIdentifier,
                                           dataSource: dataSource)
                    }
                }
            }
            .background(Color(UIColor.systemBackground))

        }
    }
    
}








#if DEBUG

// MARK - Previews

@MainActor
private final class ObvMessageReactionsViewDataSourceForPreviews: ObvMessageReactionsViewDataSource, ObvAvatarViewDataSource {
    
    func getAsyncStreamOfObvMessageReactionsViewModel(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvMessageReactionsViewModel>) {
        let stream = AsyncStream<ObvMessageReactionsViewModel> { (continuation: AsyncStream<ObvMessageReactionsViewModel>.Continuation) in
            let model = ObvMessageReactionsViewModel.sampleData
            continuation.yield(model)
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfObvMessageReactionsViewModel(streamUUID: UUID) {
        // Nothing to finish in previews
    }
    
    // ReactionCellViewDataSource
    
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

    // ReactionsCountViewDataSource
    
    func getAsyncStreamOfReactionsCountViewModel(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvReactionsCountViewModel>) {
        let stream = AsyncStream { (continuation: AsyncStream<ObvReactionsCountViewModel>.Continuation) in
            Task {
                let model = ObvReactionsCountViewModel.sampleData
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfReactionsCountViewModel(streamUUID: UUID) {
        // Nothing to finish in previews
    }

}


@MainActor
private final class ActionsForPreviews: ObvMessageReactionsViewActionsProtocol {
    func userWantsToRemoveReaction(reactionIdentifier: ObvMessageReactionsViewModel.ReactionIdentifier) async throws {}
    func userWantsToAddReactionToFavorites(emoji: Character) async throws {}
    func userWantsToRemoveReactionFromFavorites(emoji: Character) async throws {}
    func userWantsToDismissObvMessageReactionsView() {}
}


private let dataSourceForPreviews = ObvMessageReactionsViewDataSourceForPreviews()
private let actionsForPreviews = ActionsForPreviews()

private struct PreviewView: View {

    let messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier
    let dataSource: ObvMessageReactionsViewDataSource
    
    @State private var showSheet = false
    
    var body: some View {
        //        ObvMessageReactionsView(messageIdentifier: messageIdentifier, dataSource: dataSourceForPreviews)
        Button {
            showSheet.toggle()
        } label: {
            Text(verbatim: "Show")
        }
        .sheet(isPresented: $showSheet) {
            NavigationView {
                ObvMessageReactionsView(messageIdentifier: messageIdentifier, dataSource: dataSourceForPreviews, avatarViewDataSource: dataSourceForPreviews, actions: actionsForPreviews)
            }
        }
    }
    
}


#Preview {
    PreviewView(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier.forPreview(UUID()), dataSource: dataSourceForPreviews)
}


#endif
