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


/// Why a file the engine reported as complete cannot be used, when it cannot.
///
/// The two ways `Fyle.updateFyle(obvAttachmentStatus:)` refuses a downloaded attachment, and the only two: anything else it is handed, it accepts.
///
/// **For every attachment this device downloads**, whichever of the two kinds it is — one attached to a message from a contact, and one attached to a message
/// the owner sent from another of her devices. They are the same download arriving through the same inbox, and differ only in which join records them; see
/// ``ObvAttachmentOrOwnedAttachment``, which is what the repair is addressed by. Nothing here is about an *upload*, which has no downloaded file to be wrong.
///
/// Reported out of the operations that meet these rather than acted upon there — see
/// `PersistedDiscussionsUpdatesCoordinator.repairAttachmentWhoseFileCannotBeUsed(_:whatWasWrong:)`, which says why — and they are one type because the repair
/// is one repair: the engine is told to forget the attachment is complete, and it is fetched again, bounded.
enum WhatWasWrongWithADownloadedFile {

    /// There is no file at the URL the engine gave, although it says the attachment is complete.
    ///
    /// Reachable whenever something removes the file behind the engine's back — the inbox's orphan sweep did exactly that, on every return to the foreground,
    /// until 2026-08-31.
    case thereIsNoFileAtAll

    /// The file is there and its sha256 is not the one the sender stated, so some part of it holds bytes no successful chunk write put there.
    case theFileDoesNotHashAsExpected

}
