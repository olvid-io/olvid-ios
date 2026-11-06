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
import ObvSingleDiscussion
import ObvUICoreData


// MARK: - Why a forward was refused, said twice

/// The one place the discussion screen's vocabulary for a refused forward and the app's are put side by side.
///
/// The sibling of `WhatCanBeDeleted+DeletionType.swift`, and it exists for the identical reason: `ObvSingleDiscussion` does not depend on `ObvUICoreData` and
/// should not, so ``WhatCanBeForwarded/Reason`` is a fourth enum the module has had to say for itself. One function, and the compiler names the omission if
/// either side gains a case.
///
/// **One direction only, unlike the deletion's mapping.** A deletion kind travels both ways — the app answers which are open and the screen sends one back — where
/// a reason only ever travels *outward*: the screen is told why, and has nothing to say back about it. A second function would be an unused one.
extension WhatCanBeForwarded.Reason {

    init(_ why: WhyAMessageCannotBeForwarded) {
        switch why {
        case .itIsASystemMessage:
            self = .aSystemMessageWasChosen
        case .itHasBeenDeleted:
            self = .oneHasBeenDeleted
        case .itHasNotBeenOpenedYet:
            self = .oneHasNotBeenOpenedYet
        case .itIsEphemeral:
            self = .oneIsEphemeral
        case .itIsALocation:
            self = .oneIsALocation
        case .itIsAPoll:
            self = .oneIsAPoll
        case .oneOfItsAttachmentsIsNotAvailableYet:
            self = .oneHasAnAttachmentStillArriving
        case .theQuestionCouldNotBeAsked:
            self = .theyCouldNotBeChecked
        }
    }

}
