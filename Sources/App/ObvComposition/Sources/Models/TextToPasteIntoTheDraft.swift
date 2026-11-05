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

import Foundation


/// A part of what the reader put into the composition bar that belongs in the **text** rather than as an attachment.
///
/// **The other half of an answer this protocol could not give.** When something is pasted, typed as a Genmoji or dropped
/// into the bar, the app hands the whole of it to one operation which decides, item by item, what becomes an attachment
/// and what is inserted as text — and one `NSItemProvider` can be both: a pasted link is added as a link *preview*
/// attachment **and** leaves its URL in the text. Until this existed,
/// ``ComposeViewActions/userWantsToAddAttachmentsToDraft(_:discussionIdentifier:itemProviders:)`` returned nothing, so the
/// half of the answer that says *"this part was text, insert it"* had nowhere to go. The legacy screen worked around that
/// by reaching back into the bar through a public method on its hosting controller; a screen that owns the shared state
/// has no controller to reach through, which is why the answer comes back as a value instead.
///
/// A twin of the app's own `LoadedItemProviderToPaste`, deliberately: this module knows nothing of `NSItemProvider`
/// loading, of the helper that does it, or of the other cases that helper distinguishes. The app maps one to the other at
/// the boundary, and ``textToPaste`` is spelt as it is there so that the two ends of the trip grep together.
public enum TextToPasteIntoTheDraft: Sendable {

    case text(content: String)
    case url(content: URL)

    /// What actually goes into the text editor. A URL is inserted as it was written, which is what the reader pasted.
    public var textToPaste: String {
        switch self {
        case .text(let text): return text
        case .url(let url): return url.absoluteString
        }
    }

}
