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
import ObvSystemIcon


/// Says that messages are **missing** above this one, and how many — the legacy `MissedMessageBubble`.
///
/// The one part of a cell whose absence a reader could be harmed by: everything else this step adds is a small extra, and this says that something they were sent is not
/// here. At the very top of the cell, above the forwarded badge and everything else.
///
/// Its hand icon is not decoration — the bubble is **tappable**, and answers with what the gap means: a message whose sending was cancelled, or a large one still
/// being uploaded. So the tap is wired here rather than left to Step 22 with the gestures of the cell: an icon inviting a tap that does nothing is worse than no
/// icon at all, and this is a control of its own, as a poll's answers and a recording's play button are.
struct MissedMessagesBubbleView: View {

    /// How many messages are missing. Never drawn for zero — the caller decides that, as the legacy cell does.
    let count: Int

    let actions: any SingleDiscussionCellViewActions

    var body: some View {
        Button {
            Task { await actions.userWantsToKnowWhyMessagesAreMissing() }
        } label: {
            // Baseline-aligned, as `MissedMessageBubble` aligns the icon's first baseline with the label's last one.
            HStack(alignment: .lastTextBaseline, spacing: MessageBubbleMetrics.horizontalInset / 2) {
                Text("COUNT_MISSING_MESSAGES_\(count)")
                    .italic()
                Image(systemIcon: .handTap)
            }
            .font(.footnote)
            // The label colour at half strength, on the received bubble's colour at half strength — both as they are there.
            .foregroundStyle(Color(UIColor.label).opacity(Self.strengthOfTheInk))
            .padding(.horizontal, MessageBubbleMetrics.horizontalInset)
            .padding(.vertical, MessageBubbleMetrics.verticalInset)
            .background(MessageBubbleStyle.received.backgroundColor.opacity(Self.strengthOfTheInk),
                        in: RoundedRectangle(cornerRadius: MessageBubbleMetrics.cornerRadius, style: .continuous))
        }
        // Without this the tap is the *row's* rather than the button's, and the action never runs.
        .buttonStyle(.plain)
    }


    /// The `withAlphaComponent(0.5)` the legacy bubble gives both its ink and its background.
    private static let strengthOfTheInk: CGFloat = 0.5

}


#if DEBUG

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        MissedMessagesBubbleView(count: 1, actions: singleDiscussionCellViewDataSourceForPreviews)
        MissedMessagesBubbleView(count: 12, actions: singleDiscussionCellViewDataSourceForPreviews)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
}

#endif
