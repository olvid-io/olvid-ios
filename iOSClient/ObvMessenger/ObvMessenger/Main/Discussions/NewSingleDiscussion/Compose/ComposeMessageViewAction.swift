/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

enum NewComposeMessageViewAction: Int {
    case oneTimeEphemeralMessage = 1
    case scanDocument = 2
    case shootPhotoOrMovie = 3
    case chooseImageFromLibrary = 4
    case choseFile = 5
    case introduceThisContact = 6
    case changeActionsOrder = 7
}

extension NewComposeMessageViewAction {

    static let defaultActions: [NewComposeMessageViewAction] = [
        .oneTimeEphemeralMessage,
        .shootPhotoOrMovie,
        .chooseImageFromLibrary,
        .choseFile,
        .scanDocument,
        .introduceThisContact,
        .changeActionsOrder
    ]

    var icon: ObvSystemIcon {
        switch self {
        case .oneTimeEphemeralMessage:
            return .flameFill
        case .scanDocument:
            return .scanner
        case .shootPhotoOrMovie:
            return .camera
        case .chooseImageFromLibrary:
            return .photo
        case .choseFile:
            return .paperclip
        case .introduceThisContact:
            return .person2Circle
        case .changeActionsOrder:
            return .arrowUpArrowDownCircle
        }
    }

    var title: String {
        switch self {
        case .oneTimeEphemeralMessage:
            return NSLocalizedString("EPHEMERAL_MESSAGE", comment: "")
        case .scanDocument:
            return NSLocalizedString("SCAN_DOCUMENT", comment: "")
        case .shootPhotoOrMovie:
            return NSLocalizedString("SHOOT_PHOTO_OR_MOVIE", comment: "")
        case .chooseImageFromLibrary:
            return NSLocalizedString("CHOOSE_IMAGE_FROM_LIBRARY", comment: "")
        case .choseFile:
            return NSLocalizedString("CHOOSE_FILE", comment: "")
        case .introduceThisContact:
            return NSLocalizedString("Introduce", comment: "")
        case .changeActionsOrder:
            return NSLocalizedString("CHANGE_ACTION_ORDER", comment: "")
        }
    }
    
    var canBeReordered: Bool {
        switch self {
        case .changeActionsOrder:
            return false
        case .oneTimeEphemeralMessage,
                .scanDocument,
                .shootPhotoOrMovie,
                .chooseImageFromLibrary,
                .choseFile,
                .introduceThisContact:
            return true
        }
    }
    
}
