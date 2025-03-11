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
import MobileCoreServices
import UniformTypeIdentifiers


// MARK: - Declaring the UTType for Olvid's backup files

extension UTType {
    
    /// The type for Olvid's backup files. Since we created this type, we export it.
    /// See https://developer.apple.com/videos/play/tech-talks/10696
    public static let olvidBackup = UTType(exportedAs: "io.olvid.type.olvidbackup")
    
    /// The type for Olvid's link previews files sent as attachments to the messages containing the link.
    public static let olvidLinkPreview = UTType(mimeType:"olvid/link-preview") ?? UTType(exportedAs: "io.olvid.type.olvidlinkpreview")
    public static let olvidPreviewUti = "olvid.link-preview"
    
    public struct OpenXML {
        public static let docx = UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
        public static let pptx = UTType(importedAs: "org.openxmlformats.presentationml.presentation")
        public static let xlsx = UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet")
    }
        
    // Since we don't own the type and the system doesn't declare it, we added this type as an imported type identifier.
    public static let doc = UTType(importedAs: "com.microsoft.word.doc")
    
    public static let m4a = UTType(importedAs: "com.apple.m4a-audio")
    
    // The sytem declares com.apple.internet-location but performing a drag and drop of a web location resulted in the following type. Since we don't own the type and the system doesn't declare it, we added this type as an imported type identifier.
    public static let webInternetLocation = UTType(importedAs: "com.apple.web-internet-location")
    
    public static let chromiumInitiatedDrag = UTType(importedAs: "org.chromium.chromium-initiated-drag")
    
}
