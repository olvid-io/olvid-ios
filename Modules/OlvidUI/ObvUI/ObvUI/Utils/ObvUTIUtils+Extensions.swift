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

extension ObvUTIUtils {
    
    @available(iOS 14.0, *)
    public static func getIcon(forUTI uti: String) -> SystemIcon {
        if let utType = UTType(uti) {
            if utType.conforms(to: .image) {
                return .photoOnRectangleAngled
            } else if utType.conforms(to: .pdf) {
                return .docRichtext
            } else if utType.conforms(to: .audio) {
                return .musicNote
            } else if utType.conforms(to: .vCard) {
                return .personTextRectangle
            } else if utType.conforms(to: .calendarEvent) {
                return .calendar
            } else if utType.conforms(to: .font) {
                return .textformat
            } else if utType.conforms(to: .spreadsheet) {
                return .rectangleSplit3x3
            } else if utType.conforms(to: .presentation) {
                return .display
            } else if utType.conforms(to: .bookmark) {
                return .bookmark
            } else if utType.conforms(to: .archive) {
                return .rectangleCompressVertical
            } else if utType.conforms(to: .webArchive) {
                return .archiveboxFill
            } else if utType.conforms(to: .xml) || utType.conforms(to: .html) {
                return .chevronLeftForwardslashChevronRight
            } else if utType.conforms(to: .executable) {
                return .docBadgeGearshape
            } else if ObvUTIUtils.uti(uti, conformsTo: "org.openxmlformats.wordprocessingml.document" as CFString) || ObvUTIUtils.uti(uti, conformsTo: "com.microsoft.word.doc" as CFString) {
                    // Word (docx) document
                return .docFill
            } else {
                return .paperclip
            }
        } else {
            return .paperclip
        }
    }
}
