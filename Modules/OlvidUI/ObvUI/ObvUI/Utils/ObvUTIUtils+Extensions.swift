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
import UniformTypeIdentifiers
import UI_SystemIcon

extension UTType {
    
    public var systemIcon: SystemIcon {
        if self.conforms(to: .image) {
            return .photoOnRectangleAngled
        } else if self.conforms(to: .pdf) {
            return .docRichtext
        } else if self.conforms(to: .audio) {
            return .musicNote
        } else if self.conforms(to: .vCard) {
            return .personTextRectangle
        } else if self.conforms(to: .calendarEvent) {
            return .calendar
        } else if self.conforms(to: .font) {
            return .textformat
        } else if self.conforms(to: .spreadsheet) {
            return .rectangleSplit3x3
        } else if self.conforms(to: .presentation) {
            return .display
        } else if self.conforms(to: .bookmark) {
            return .bookmark
        } else if self.conforms(to: .archive) {
            return .rectangleCompressVertical
        } else if self.conforms(to: .webArchive) {
            return .archiveboxFill
        } else if self.conforms(to: .xml) || self.conforms(to: .html) {
            return .chevronLeftForwardslashChevronRight
        } else if self.conforms(to: .executable) {
            return .docBadgeGearshape
        } else if self.conforms(to: UTType.OpenXML.docx) || self.conforms(to: .doc) {
            // Word (docx or doc) document
            return .docFill
        } else if self.conforms(to: UTType.olvidLinkPreview) {
            return .safari
        } else {
            return .paperclip
        }
    }
    
}
