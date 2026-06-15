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

    let sortableActions: [SortableAction]
    let unsortableActions: [UnsortableAction]
    let defaultEmojiButton: String // Global to all discussions
    let sendMessageShortcutType: SendMessageShortcutType
    
    public init(sortableActions: [SortableAction],
                unsortableActions: [UnsortableAction],
                defaultEmojiButton: String,
                sendMessageShortcutType: SendMessageShortcutType) {
        self.sortableActions = sortableActions
        self.unsortableActions = unsortableActions
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
    
    public enum SortableAction: Int, Identifiable, Sendable, Equatable, CaseIterable {
        
        case oneTimeEphemeralMessage = 0
        case scanDocument = 1
        case shootPhotoOrMovie = 2
        case chooseImageFromLibrary = 3
        case choseFile = 4
        case introduceThisContact = 5
        case shareLocation = 6
        case createPoll = 7
        case pasteContent = 8
        
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
            }
        }

        var icon: SystemIcon {
            switch self {
            case .oneTimeEphemeralMessage:
                return .flameFill
            case .scanDocument:
                return .scanner
            case .shootPhotoOrMovie:
                return .camera()
            case .chooseImageFromLibrary:
                return .photo
            case .choseFile:
                return .paperclip
            case .introduceThisContact:
                return .person2Circle
            case .shareLocation:
                return .locationCircle
            case .createPoll:
                return .chartBarYaxis
            case .pasteContent:
                return .docOnDoc
            }
        }

    }

    public enum UnsortableAction: Int, Identifiable, Sendable, Equatable, CaseIterable {
        case composeMessageSettings = 0
        public var id: Int { self.rawValue }
        
        var title: String {
            switch self {
            case .composeMessageSettings:
                return String(localizedInThisBundle: "COMPOSE_MESSAGE_SETTINGS")
            }
        }

        var icon: SystemIcon {
            switch self {
            case .composeMessageSettings:
                return .gearshapeFill
            }
        }
        
    }

}
