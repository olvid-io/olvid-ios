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
import ObvSystemIcon


public struct ComposeViewParameters: Sendable, Equatable {

    let defaultEmojiButton: String // Global to all discussions
    let sendMessageShortcutType: SendMessageShortcutType
    
    public init(defaultEmojiButton: String,
                sendMessageShortcutType: SendMessageShortcutType) {
        self.defaultEmojiButton = defaultEmojiButton
        self.sendMessageShortcutType = sendMessageShortcutType
    }
    
}


extension ComposeViewParameters {
 
    public enum SendMessageShortcutType: Int, CaseIterable, Sendable, Equatable {
        case enter
        case commandEnter
    }

}


extension ComposeViewParameters {
    
    /// An entry of the `+` card.
    public enum Action: Int, Identifiable, Sendable, Equatable, CaseIterable {
        
        case oneTimeEphemeralMessage = 0
        case scanDocument = 1
        case shootPhotoOrMovie = 2
        case chooseImageFromLibrary = 3
        case choseFile = 4
        case introduceThisContact = 5
        case shareLocation = 6
        case createPoll = 7
        case pasteContent = 8
        case composeMessageSettings = 9
        
        public var id: Int { self.rawValue }
     
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
            case .createPoll:
                return String(localizedInThisBundle: "CREATE_POLL")
            case .pasteContent:
                return String(localizedInThisBundle: "PASTE_CONTENT")
            case .composeMessageSettings:
                return String(localizedInThisBundle: "COMPOSE_MESSAGE_SETTINGS")
            }
        }

        var icon: SystemIcon {
            switch self {
            case .oneTimeEphemeralMessage:
                return .flame
            case .scanDocument:
                return .scanner
            case .shootPhotoOrMovie:
                return .camera()
            case .chooseImageFromLibrary:
                return .photo
            case .choseFile:
                return .paperclip
            case .introduceThisContact:
                return .person2
            case .shareLocation:
                return .location
            case .createPoll:
                return .chartBarYaxis
            case .pasteContent:
                return .docOnDoc
            case .composeMessageSettings:
                return .gearshape
            }
        }

        /// The kind of an action, which is all the menu needs in order to group them: it draws the actions in the
        /// order ``orderShownInPanel`` states and cuts a section wherever the kind changes. The order the cases are
        /// written in below therefore decides nothing.
        enum Kind {
            case contact
            case ephemeral
            case insert
            case capture
            case attach
            /// The settings of the bar itself, the one entry that does not put anything into the draft.
            case settings
        }
        
        var kind: Kind {
            switch self {
            case .introduceThisContact:
                return .contact
            case .oneTimeEphemeralMessage:
                return .ephemeral
            case .shareLocation, .createPoll:
                return .insert
            case .shootPhotoOrMovie, .scanDocument:
                return .capture
            case .chooseImageFromLibrary, .choseFile, .pasteContent:
                return .attach
            case .composeMessageSettings:
                return .settings
            }
        }

    }

}
