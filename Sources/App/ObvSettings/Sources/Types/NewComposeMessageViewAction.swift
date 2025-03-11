/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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


public enum NewComposeMessageViewSortableAction: Int {
    case oneTimeEphemeralMessage = 0
    case scanDocument = 1
    case shootPhotoOrMovie = 2
    case chooseImageFromLibrary = 3
    case choseFile = 4
    case introduceThisContact = 5
    case shareLocation = 6
}

public enum NewComposeMessageViewUnsortableAction: Int {
    case composeMessageSettings = 0
}

public extension NewComposeMessageViewSortableAction {

    static let defaultOrder: [NewComposeMessageViewSortableAction] = [
        .shareLocation,
        .oneTimeEphemeralMessage,
        .shootPhotoOrMovie,
        .chooseImageFromLibrary,
        .choseFile,
        .scanDocument,
        .introduceThisContact,
    ]

    var title: String {
        switch self {
        case .oneTimeEphemeralMessage:
            return String(localizedInThisBundle: "EPHEMERAL_MESSAGE")
        case .scanDocument:
            return String(localizedInThisBundle: "SCAN_DOCUMENT")
        case .shootPhotoOrMovie:
            return String(localizedInThisBundle: "SHOOT_PHOTO_OR_MOVIE")
        case .chooseImageFromLibrary:
            return String(localizedInThisBundle: "CHOOSE_IMAGE_FROM_LIBRARY")
        case .choseFile:
            return String(localizedInThisBundle: "CHOOSE_FILE")
        case .introduceThisContact:
            return String(localizedInThisBundle: "Introduce")
        case .shareLocation:
            return String(localizedInThisBundle: "SHARE_LOCATION")
        }
    }
    
}

public extension NewComposeMessageViewUnsortableAction {
    
    static let defaultOrder: [NewComposeMessageViewUnsortableAction] = [
        .composeMessageSettings
    ]
    
    var title: String {
        switch self {
        case .composeMessageSettings:
            return String(localizedInThisBundle: "COMPOSE_MESSAGE_SETTINGS")
        }
    }
    
}
