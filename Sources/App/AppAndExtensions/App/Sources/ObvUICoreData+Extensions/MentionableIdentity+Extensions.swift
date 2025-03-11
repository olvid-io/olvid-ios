/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvUICoreData

extension Sequence where Element: PersistedUserMentionInMessage {
    
    /// - Attention: This is supposed to be run within the view context
    /// This is a _quick_ workaround to ship this feature, will refactor once shipped
    var mentionableIdentityTypesFromRange_WARNING_VIEW_CONTEXT: MentionableIdentityTypes.MentionableIdentityFromRange {
        assert(Thread.isMainThread, "expected to be run from the main thread…")

        return ObvStack.shared.viewContext.performAndWait {
            return reduce(into: [:]) { accumulator, item in
                guard let mentionRange = try? item.mentionRange else {
                    return
                }

                if let displayablePersistedObvIdentity = try? item.fetchMentionableIdentity() {
                    accumulator[mentionRange] = displayablePersistedObvIdentity
                }
                
            }
        }
    }
}

extension Sequence where Element: PersistedUserMentionInDraft {
    
    /// - Attention: This is supposed to be run within the view context
    /// This is a _quick_ workaround to ship this feature, will refactor once shipped
    var mentionableIdentityTypesFromRange_WARNING_VIEW_CONTEXT: MentionableIdentityTypes.MentionableIdentityFromRange {
        assert(Thread.isMainThread, "expected to be run from the main thread…")

        return ObvStack.shared.viewContext.performAndWait {
            return reduce(into: [:]) { accumulator, item in
                guard let mentionRange = try? item.mentionRange else {
                    return
                }

                if let displayablePersistedObvIdentity = try? item.fetchMentionableIdentity() {
                    accumulator[mentionRange] = displayablePersistedObvIdentity
                }

            }
        }
    }
}
