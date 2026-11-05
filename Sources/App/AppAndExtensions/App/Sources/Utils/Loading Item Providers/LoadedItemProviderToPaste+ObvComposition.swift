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
import ObvComposition


extension LoadedItemProviderToPaste {

    /// The same answer, said in the composition bar's own vocabulary — see ``ObvComposition/TextToPasteIntoTheDraft``.
    ///
    /// **The whole of the boundary, in one place.** Both discussion screens ask the same question and get this answer back,
    /// so the conversion is here rather than at each of them: two copies of a two-case mapping is two things to forget when
    /// a third case is added. The two types are deliberate twins — the composition bar knows nothing of `NSItemProvider`
    /// loading, and the helper that does knows nothing of the bar.
    var forTheComposeView: TextToPasteIntoTheDraft {
        switch self {
        case .text(let content): return .text(content: content)
        case .url(let content): return .url(content: content)
        }
    }

}
