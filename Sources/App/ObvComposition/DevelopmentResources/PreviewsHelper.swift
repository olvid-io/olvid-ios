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

import SwiftUI
import CoreData
import ObvDesignSystem
import ObvTypes
import ObvAppTypes


extension ObvCryptoId {
    
    @MainActor
    static let sampleDataForOwnedCryptoId: Self = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

    @MainActor
    static let sampleDataForContactCryptoId: Self = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000153c2183e6feef914ef20ae0f2ce4dd025022221b0bfdf22fb16859feac477fa0023713e65219d2c01f6feb26f9d2a390fd9afce7389f7ae22884f0efccad74c83")!)

}


extension ObvContactIdentifier {
    
    @MainActor
    static let sampleData: Self = .init(contactCryptoId: .sampleDataForContactCryptoId, ownedCryptoId: .sampleDataForOwnedCryptoId)
    
}


extension ObvDiscussionIdentifier {
    
    @MainActor
    static let sampleDataForOneToOne: Self = ObvDiscussionIdentifier.oneToOne(id: .sampleData)
    
}


@MainActor
final class DataSourceAndActionsForPreviews {}

extension DataSourceAndActionsForPreviews: ComposeViewActions {
    
    func composeViewHasChangedTextAndMentions(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws {
        print("[debug] composeViewHasChangedMentions \(discussionIdentifier)")
    }
    
    func userWantsToOpenEmojiPicker() {
        print("[debug] userWantsToOpenEmojiPicker")
    }
    
    func userWantsToDeleteDraftFyleJoin(attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async {
        print("[debug] userWantsToDeleteDraftFyleJoin")
    }

    func userDidRecordAudio(at url: URL, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws {
        print("[debug] userDidRecordAudio \(discussionIdentifier) with url: \(url)")
    }
    
    func userWantsToSendDraft(_ view: ComposeView, discussionIdentifier: ObvDiscussionIdentifier, attributedText: AttributedString) async throws {
        print("[debug] userWantstoSendDraft \(discussionIdentifier), text: \(attributedText)")
    }
        
    func actionTapped(_ view: ComposeView, for action: ComposeViewParameters.SortableAction, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, contactIdentifier: ObvContactIdentifier?) async throws {
        print("[debug] actionTappd for \(action)")
    }
    
    func actionTapped(_ view: ComposeView, for action: ComposeViewParameters.UnsortableAction, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) {
        print("[debug] actionTappd for \(action)")
    }
    
    func userDidTapOnDraftFyleJoinWithHardLink(_ view: ComposeAttachmentsView, at index: Int) {
        print("[debug] userDidTapOnDraftFyleJoinWithHardLink: \(index)")
    }
    
    func userWantstoRemoveReplyToMessage(_ view: ComposeReplyToView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws {
        print("[debug] userWantstoRemoveReplyToMessage: \(discussionIdentifier)")
    }
    
    func userWantsToAddAttachmentsToDraft(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, itemProviders: [NSItemProvider]) async throws {
        print("[debug] userWantsToAddAttachmentsToDraft: \(discussionIdentifier), providers count: \(itemProviders.count)")
    }
    
    func userWantsToDeleteDraftAttachment(_ view: ComposeAttachmentView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        print("[debugs] user wants to delete draft attachment")
    }
    
    func userWantsToDeleteDraftAttachment(_ view: ComposeLinkPreviewView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        print("[debugs] user wants to delete draft attachment")
    }
    
    func userWantsToDeleteDraftAttachment(_ view: ComposeView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        print("[debugs] user wants to delete draft attachment")
    }

}

extension DataSourceAndActionsForPreviews: ObvAvatarViewDataSource {
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    
}


extension DataSourceAndActionsForPreviews: ComposeViewDataSource {
    
    func getInitialComposeViewDataSourceModel(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) -> ComposeViewDataSourceModel? {
        return ComposeViewDataSourceModel.sampleData[0]
    }
    
    func getAsyncStreamOfComposeViewDataSourceModel(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ComposeViewDataSourceModel>) {
        let stream = AsyncStream<ComposeViewDataSourceModel> { (continuation: AsyncStream<ComposeViewDataSourceModel>.Continuation) in
            Task {
                continuation.yield(ComposeViewDataSourceModel.sampleData[0])
//                while true {
//                    continuation.yield(ComposeViewDataSourceModel.sampleData[0])
//                    try? await Task.sleep(seconds: 1)
//                    continuation.yield(ComposeViewDataSourceModel.sampleData[1])
//                    try? await Task.sleep(seconds: 1)
//                    continuation.yield(ComposeViewDataSourceModel.sampleData[0])
//                    try? await Task.sleep(seconds: 1)
//                    continuation.yield(ComposeViewDataSourceModel.sampleData[2])
//                    try? await Task.sleep(seconds: 1)
//                    //continuation.yield(ComposeViewDataSourceModel.sampleData[0])
//                    //try? await Task.sleep(seconds: 2)
//                    //continuation.yield(ComposeViewDataSourceModel.sampleData[3])
//                }

            }
        }
        
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfComposeViewDataSourceModel(_ view: ComposeView, streamUUID: UUID) {
        
    }
    
}


extension DataSourceAndActionsForPreviews: ComposeLinkPreviewViewDataSource {
    
    func getAsyncStreamOfComposeLinkPreviewViewModel(_ view: ComposeLinkPreviewView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ComposeLinkPreviewView.Model>) {
        let stream = AsyncStream<ComposeLinkPreviewView.Model> { (continuation: AsyncStream<ComposeLinkPreviewView.Model>.Continuation) in
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfComposeLinkPreviewViewModel(_ view: ComposeLinkPreviewView, streamUUID: UUID) {
        // Do nothing in previews
    }
    
}


extension DataSourceAndActionsForPreviews: ComposeAttachmentViewDataSource {
    
    func getInitialComposeViewDataSourceFyleModel(attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) -> ComposeViewDataSourceFyleModel? {
        return nil
    }
    
    func getAsyncStreamOfComposeViewDataSourceFyleModel(attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ComposeViewDataSourceFyleModel>) {
        let stream = AsyncStream<ComposeViewDataSourceFyleModel> { (continuation: AsyncStream<ComposeViewDataSourceFyleModel>.Continuation) in
        }        
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfComposeViewDataSourceFyleModel(streamUUID: UUID) {
    }
    
}

extension DataSourceAndActionsForPreviews: ComposeReplyToViewDataSource {
    
    func getInitialComposeViewDataSourceReplyToModel(messageIdentifier: ObvAppTypes.ObvMessageAppIdentifier) -> ComposeViewDataSourceReplyToModel? {
        return nil
    }
    
    func getAsyncStreamOfComposeViewDataSourceReplyToModel(_ view: ComposeReplyToView, messageIdentifier: ObvAppTypes.ObvMessageAppIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ComposeViewDataSourceReplyToModel>) {
        let stream = AsyncStream<ComposeViewDataSourceReplyToModel> { (continuation: AsyncStream<ComposeViewDataSourceReplyToModel>.Continuation) in
        }
        
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfComposeViewDataSourceReplyToModel(_ view: ComposeReplyToView, streamUUID: UUID) {
    }
    
}

extension DataSourceAndActionsForPreviews: ComposeMentionsViewDataSource {
    

    func getSuggestions(_ view: ComposeMentionsView, with query: String?, streamUUID: UUID) {
        // Nothing in previews
    }
    

    func getAsyncStreamOfComposeSuggestionsModel(_ view: ComposeMentionsView, discussionIdentifier: ObvDiscussionIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ComposeSuggestionsModel>) {
            let stream = AsyncStream<ComposeSuggestionsModel> { (continuation: AsyncStream<ComposeSuggestionsModel>.Continuation) in
                //let mention1 = ComposeMentionSuggestionModel(
                //    title: "Alice Wonderland",
                //    mentionedCryptoId: ObvCryptoId.sampleDataForContactCryptoId,
                //    avatarModel: .init(characterOrIcon: .character("A"), colors: .init(foreground: .red, background: .green), photoURL: nil))
                //let mention2 = ComposeMentionSuggestionModel(
                //    title: "Bob Morane",
                //    mentionedCryptoId: ObvCryptoId.sampleDataForContactCryptoId,
                //    avatarModel: .init(characterOrIcon: .character("B"), colors: .init(foreground: .blue, background: .yellow), photoURL: nil))
                //let model = ComposeSuggestionsModel(mentions: [mention1, mention2], range: nil)
                // Decomment to preview mentions
                //continuation.yield(model)
            }
            
            return (UUID(), stream)
    }
    
    
    func finishAsyncStreamOfComposeSuggestionsModel(_ view: ComposeMentionsView, streamUUID: UUID) {
        // Nothing in previews
    }

}

fileprivate let persistedDraftFyleJoinID: ComposeAttachmentView.AttachmentIdentifier = .persistedDraftFyleJoinObjectID(NSManagedObjectID())

fileprivate let persistedLinkPreviewDraftFyleJoinID: ComposeAttachmentView.AttachmentIdentifier = .persistedDraftFyleJoinObjectID(NSManagedObjectID())

extension ComposeViewDataSourceModel {
    @MainActor
    static let sampleData: [ComposeViewDataSourceModel] = [
        ComposeViewDataSourceModel(discussionIdentifier: .sampleDataForOneToOne,
                                   isDraftDeleted: false,
                                   hasSomeExpiration: false,
                                   isOneToOne: false,
                                   emojiButtonSpecificToDiscussion: nil,
                                   contactOriginalNameIfOneToOne: nil,
                                   contactIdentifier: nil,
                                   attachments: [],
                                   linkPreview: nil,
                                   audio: nil,
                                   replyTo: nil),
        ComposeViewDataSourceModel(discussionIdentifier: .sampleDataForOneToOne,
                                   isDraftDeleted: false,
                                   hasSomeExpiration: false,
                                   isOneToOne: false,
                                   attributedText: "coucou",
                                   emojiButtonSpecificToDiscussion: nil,
                                   contactOriginalNameIfOneToOne: nil,
                                   contactIdentifier: nil,
                                   attachments: [persistedDraftFyleJoinID],
                                   linkPreview: nil,
                                   audio: nil,
                                   replyTo: nil),
        ComposeViewDataSourceModel(discussionIdentifier: .sampleDataForOneToOne,
                                   isDraftDeleted: false,
                                   hasSomeExpiration: false,
                                   isOneToOne: false,
                                   attributedText: "coucou",
                                   emojiButtonSpecificToDiscussion: nil,
                                   contactOriginalNameIfOneToOne: nil,
                                   contactIdentifier: nil,
                                   attachments: [],
                                   linkPreview: persistedLinkPreviewDraftFyleJoinID,
                                   audio: nil,
                                   replyTo: nil),
        ComposeViewDataSourceModel(discussionIdentifier: .sampleDataForOneToOne,
                                   isDraftDeleted: false,
                                   hasSomeExpiration: false,
                                   isOneToOne: false,
                                   attributedText: "coucou",
                                   emojiButtonSpecificToDiscussion: nil,
                                   contactOriginalNameIfOneToOne: nil,
                                   contactIdentifier: nil,
                                   attachments: [persistedDraftFyleJoinID],
                                   linkPreview: persistedLinkPreviewDraftFyleJoinID,
                                   audio: nil,
                                   replyTo: nil)
        ]
}


extension DataSourceAndActionsForPreviews: ComposeViewParametersDataSource {
    
    func getAsyncStreamOfComposeViewParameters(_ view: ComposeView) async throws -> (streamUUID: UUID, stream: AsyncStream<ComposeViewParameters>) {
        let stream = AsyncStream<ComposeViewParameters> { (continuation: AsyncStream<ComposeViewParameters>.Continuation) in
            // Do nothing for now
        }
        return (UUID(), stream)
    }
    
    func finishAsyncStreamOfComposeViewParameters(streamUUID: UUID) {
        // Do nothing in previews
    }
    
}
