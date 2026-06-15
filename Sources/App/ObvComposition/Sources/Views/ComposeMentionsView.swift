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
import ObvDesignSystem
import ObvAppTypes


public struct ComposeMentionsView: View {

    @ObservedObject var sharedState: ComposeMentionsView.SharedState
    let dataSource: any ComposeMentionsViewDataSource
    let avatarViewDataSource: any ObvAvatarViewDataSource
    
    static var cellHeight: CGFloat = 35.0

    private func onChangeOfCurrentMentionString(_ currentMentionString: String?) {
        guard let currentStreamUUID = sharedState.currentStreamUUID else { assertionFailure(); return }
        let query = currentMentionString?.filter({ $0 != "@" })
        self.dataSource.getSuggestions(self, with: query, streamUUID: currentStreamUUID)
    }
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try dataSource.getAsyncStreamOfComposeSuggestionsModel(self, discussionIdentifier: sharedState.discussionIdentifier)
            self.sharedState.currentStreamUUID = streamUUID
            for await receivedDataSourceViewModel in stream {
                self.sharedState.setStreamedModel(to: receivedDataSourceViewModel)
            }
            dataSource.finishAsyncStreamOfComposeSuggestionsModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    private var isMentionsEmpty: Bool {
        guard let streamedModel = sharedState.streamedModel else { return true }
        return streamedModel.mentions.isEmpty
    }
    
    private var numberOfMentions: Int {
        guard let streamedModel = sharedState.streamedModel else { return 0 }
        return streamedModel.mentions.count
    }
    
    private var maxVisibleHeight: CGFloat {
        guard let streamedModel = sharedState.streamedModel else { return 0 }
        return maxVisibleHeight(for: streamedModel.mentions.count, maximumCount: 5)
    }
    
    private func onMentionSelectedByUser(_ mention: ComposeMentionSuggestionModel) {
        guard let currentStreamUUID = sharedState.currentStreamUUID else { assertionFailure(); return }
        self.dataSource.getSuggestions(self, with: nil, streamUUID: currentStreamUUID) // This eventually dismisses the list of mentions shown by this view
        sharedState.onMentionSelectedByUser(mention)
    }
    
    private func isSelected(_ index: Int) -> Bool {
        sharedState.suggestionSelectedIndex == index
    }
    
    /// Computes the maximum visible height for displaying a limited number of contacts in a mentions list.
    ///
    /// - Parameter mentionsCount: The number of contacts that could potentially be displayed.
    /// - Parameter maximumCount: The maximum number of contacts allowed to be displayed.
    /// - Returns: The maximum height (in points) required to display the contacts without exceeding the limit.
    private func maxVisibleHeight(for mentionsCount: Int, maximumCount: Int) -> CGFloat {
        let actualItems = CGFloat(min(mentionsCount, maximumCount))
        return CGFloat(actualItems) * Self.cellHeight
    }
    
    @ViewBuilder
    private var content: some View {
        if let streamedModel = sharedState.streamedModel, !streamedModel.mentions.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0.0) {
                        ForEach(Array(streamedModel.mentions.enumerated()), id: \.element) { index, mention in
                            Button {
                                onMentionSelectedByUser(mention)
                            } label: {
                                VStack(alignment: .leading, spacing: 0.0) {
                                    HStack(alignment: .center) {
                                        ObvAvatarView(model: mention.avatarModel, style: .squircle, size: .small, dataSource: avatarViewDataSource)
                                        
                                        Text("@" + mention.title)
                                            .font(.subheadline)
                                            .fontWeight(isSelected(index) ? .semibold : .regular)
                                            .fontWeight(.regular)
                                            .lineLimit(1)
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 4.0)
                                    .padding(.leading, 12.0)
                                    
                                    if index < streamedModel.mentions.count - 1 {
                                        Divider()
                                            .opacity(0.75)
                                            .padding(.leading, 12.0)
                                    }
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 12.0)
                                .background(
                                    Capsule().padding(1).foregroundStyle(isSelected(index) ? Color.accentColor.opacity(0.05) : Color.clear)
                                )
                            }
                            .id(index)
                            .foregroundStyle(Color(uiColor: .label))
                            .frame(height: Self.cellHeight)
                        }
                    }
                }
                .frame(maxHeight: maxVisibleHeight)
                .onChange(of: sharedState.suggestionSelectedIndex) { newValue in
                    guard sharedState.streamedModel?.mentions.indices.contains(newValue) == true else { return }
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .bottom)
                    }
                }
            }
        } else {
            Rectangle()
                .frame(height: 0)
        }
    }
    
    public var body: some View {
        content
            .frame(maxHeight: maxVisibleHeight)
            .animation(.linear(duration: 0.25), value: isMentionsEmpty)
            .onChange(of: sharedState.currentMentionString, perform: onChangeOfCurrentMentionString)
            .task(onTask)
    }
    
}
