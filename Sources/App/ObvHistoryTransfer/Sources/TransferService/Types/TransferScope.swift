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


/// Defines what data the user chooses to export during a history transfer.
///
/// Selected by the user in `ChooseWhatToTransferView`.
///
/// - `messagesOnly`: Only text messages are transferred. Attachments (photos, videos, files, etc.) are excluded. This is the fastest option.
/// - `messagesAndAttachments`: Both messages and all their attachments are transferred. This is the most complete option but may take significantly longer depending on the amount of data.
public enum TransferScope: Sendable {
    case messagesOnly
    case messagesAndAttachments
}
