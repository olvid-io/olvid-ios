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
import ObvAppTypes


public struct ComposeReplyToView: View {
    
    let replyToMessageIdentifier: ObvAppTypes.ObvMessageAppIdentifier
    let dataSource: ComposeReplyToViewDataSource
    let actions: any ComposeViewActions
    let hasReplyViewDisplayedAbove: Bool
    
    let initialDataSourceViewModel: ComposeViewDataSourceReplyToModel?
    @State private var streamedDataSourceViewModel: ComposeViewDataSourceReplyToModel?
    var dataSourceViewModel: ComposeViewDataSourceReplyToModel? {
        streamedDataSourceViewModel ?? initialDataSourceViewModel
    }
    
    init(replyToMessageIdentifier: ObvAppTypes.ObvMessageAppIdentifier,
         dataSource: ComposeReplyToViewDataSource,
         hasReplyViewDisplayedAbove: Bool,
         actions: any ComposeViewActions) {
        self.replyToMessageIdentifier = replyToMessageIdentifier
        self.dataSource = dataSource
        self.hasReplyViewDisplayedAbove = hasReplyViewDisplayedAbove
        self.actions = actions
        
        if let initialDataSourceModel = dataSource.getInitialComposeViewDataSourceReplyToModel(messageIdentifier: replyToMessageIdentifier) {
            self.initialDataSourceViewModel = initialDataSourceModel
        } else {
            self.initialDataSourceViewModel = nil
        }
    }
    
    private enum GlassEffectID: String {
        case trashButton
    }
    
    private var discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier {
        replyToMessageIdentifier.discussionIdentifier
    }
    
    @ViewBuilder
    public var content: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                
                if let dataSourceViewModel {
                    VStack(alignment: .leading) {
                        Text(dataSourceViewModel.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color(uiColor: dataSourceViewModel.textColor))
                        if let body = dataSourceViewModel.body, !hasReplyViewDisplayedAbove {
                            Text(body)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: hasReplyViewDisplayedAbove)
                } else {
                    ProgressView()
                }
                
                Spacer()
                
                if !hasReplyViewDisplayedAbove, let image = dataSourceViewModel?.image {
                    ZStack(alignment: .center) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        
                        if let attachmentLeft = dataSourceViewModel?.attachmentLeft, attachmentLeft > 0 {
                            // Semi-opaque overlay bar at the top to improve text readability
                            Rectangle()
                                .fill(Color.black.opacity(0.4))
                            
                            Text(verbatim: "+\(attachmentLeft)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 40, height: 40.0)
                    .clipShape(RoundedRectangle(cornerRadius: 8.0))
                    .transition(.scale.combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: hasReplyViewDisplayedAbove)
                }
                
                AsyncButton(action: {
                    try? await self.actions.userWantstoRemoveReplyToMessage(self, discussionIdentifier: discussionIdentifier)
                }) {
                    Image(systemIcon: .xmark)
                        .imageScale(.small)
                        .padding(10.0)
                }
                .glassButtonStyle(glassEffectID: GlassEffectID.trashButton.rawValue)
            }
            
            Divider()
        }
        .padding(.horizontal, 12.0)
    }
    
    public var body: some View {
        content
            .task(id: replyToMessageIdentifier, onTaskForAsyncStreamOfComposeViewDataSourceReplyToModel)
    }
}

extension ComposeReplyToView {

    private func onTaskForAsyncStreamOfComposeViewDataSourceReplyToModel() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfComposeViewDataSourceReplyToModel(self, messageIdentifier: replyToMessageIdentifier)
            for await receivedDataSourceViewModel in stream {
                self.streamedDataSourceViewModel = receivedDataSourceViewModel
            }
            dataSource.finishAsyncStreamOfComposeViewDataSourceReplyToModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
}
