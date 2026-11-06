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


/// Says how many messages arrived since the reader last looked, and sits immediately above the first of them.
///
/// It carries no date, unlike every other row of a discussion: it marks a place in the reading rather than a moment in time. The legacy screen shows it in red
/// through `SystemMessageCell`, with the `numberOfNewMessages` category, and suppresses the date there for the same reason.
///
/// Its translations are the legacy screen's, copied into this module's catalog rather than reached for where they are: they live in `ObvUICoreData`, and this
/// module deliberately knows nothing of the persistence layer. The key carries its argument — `COUNT_NEW_MESSAGES_%lld` — because that is what SwiftUI derives
/// from the interpolated literal, and because the count has to reach the entry for its plural variations to mean anything.
struct NewMessagesMarkerView: View {

    let numberOfNewMessages: Int

    var body: some View {
        // The metrics of a message bubble, which is what the legacy screen gives it too: `SystemMessageCellContentView` insets its label by
        // `MessageCellConstants.bubbleHorizontalInsets` and `bubbleVerticalInset`, rounds it like a bubble, caps it at 80% of the width and centres it. Its
        // label is `preferredFont(forTextStyle: .body)`, centred over as many lines as it needs.
        AtMostAFractionOfTheOfferedWidth(fraction: MessageBubbleMetrics.maxWidthRatio) {
            Text("COUNT_NEW_MESSAGES_\(numberOfNewMessages)")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(UIColor.white))
                .padding(.horizontal, MessageBubbleMetrics.horizontalInset)
                .padding(.vertical, MessageBubbleMetrics.verticalInset)
                .background(Color(UIColor.red), in: RoundedRectangle(cornerRadius: MessageBubbleMetrics.cornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

}


#if DEBUG

#Preview {
    VStack(spacing: 16) {
        NewMessagesMarkerView(numberOfNewMessages: 1)
        NewMessagesMarkerView(numberOfNewMessages: 12)
    }
    .padding()
}

#endif
