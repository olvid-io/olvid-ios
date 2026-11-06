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


/// Someone named in the body of a message, and the one thing this screen and its app have to agree on about them: **a mention is a link**.
///
/// The legacy screen does the same, and for the same reason — a mention has to be *tappable*, and text that carries a link is the only text a reader can tap.
/// There it is a `mention://n` whose number is resolved by re-reading the attributed string in the cell; here the link has to carry the person, because the
/// attribute saying who they are lives in an attribute scope this module cannot see.
///
/// So the vocabulary is defined here and the meaning is not: the app writes whoever was mentioned into ``url(forWhoeverIsMentioned:)`` and reads them back out of
/// it, while this module only tells a mention from an ordinary link and draws it differently. Neither knows what the other put in it.
public enum MentionInAMessage {

    /// What a mention's link is a link to. Nothing can open it: it exists to be caught.
    public static let scheme = "olvid-mention"

    /// The link standing for whoever is mentioned, `whoTheyAre` being whatever the app needs to find them again.
    public static func url(forWhoeverIsMentioned whoTheyAre: String) -> URL? {
        URL(string: "\(scheme):\(whoTheyAre)")
    }

    /// Whoever a mention's link stands for, and nil for a link that is not a mention at all.
    public static func whoeverIsMentioned(in url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return String(url.absoluteString.dropFirst(scheme.count + 1))
    }

}


extension AttributedString {

    /// Everything tappable in a body drawn so that a reader can see it is tappable, exactly as the legacy screen draws it.
    ///
    /// **A link and a mention are not drawn the same**, and the difference is not decorative — it is what tells them apart:
    ///
    /// - a **link** is coloured and **underlined** — `withStyleForLinks` sets `underlineStyle = .single`;
    /// - a **mention** is coloured and **bold**, and is *not* underlined. That is not an oversight of the legacy screen but a consequence of its order:
    ///   `withStyleForMentions` runs after `withStyleForLinks` and sets an underline *colour* without a style, so nothing is drawn.
    ///
    /// The colour has to be given rather than left to the tint, and this is what made data detection invisible before: on a message *sent*, a link is white on
    /// Olvid blue — the same white as the words around it — so a telephone number that was only tinted looked exactly like the rest of the sentence. What marks it
    /// out there is the underline.
    func withLinksAndMentionsEmphasised(inTheColour colour: Color) -> AttributedString {
        var result = self
        for (link, range) in result.runs[\.link] {
            guard let link else { continue }
            result[range].foregroundColor = colour
            if MentionInAMessage.whoeverIsMentioned(in: link) == nil {
                result[range].underlineStyle = .single
            } else {
                result[range].font = .body.bold()
            }
        }
        return result
    }

}
