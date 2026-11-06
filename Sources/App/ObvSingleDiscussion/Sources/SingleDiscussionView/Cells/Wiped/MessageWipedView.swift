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


/// What is left of a message that has been wiped: one sentence, in italics, in a bubble.
///
/// `WipedView` of the legacy screen, which is an italic `.body` label and nothing else — no attachments, no body, no reactions, and nothing to tap. See
/// ``WipedMessage`` for the three sentences it can be, and for the fourth that cannot.
struct MessageWipedView: View {

    let wiped: WipedMessage
    let style: MessageBubbleStyle

    var body: some View {
        MessageBubbleView(style: style) {
            sentence
                .font(.body.italic())
        }
    }


    private var sentence: Text {
        switch wiped {
        case .byTheExpiryOfItsOwnVisibility:
            return Text("WIPED_MESSAGE")
        case .byAContact(named: let name):
            guard let name else { return Text("Remotely wiped") }
            // The one interpolated string on this screen so far, and the reason `Text(_:comment:)` of this module takes a `LocalizedStringKey`: the interpolation is
            // resolved by SwiftUI against the module's own catalogue.
            return Text("WIPED_MESSAGE_BY_\(name)")
        }
    }

}
