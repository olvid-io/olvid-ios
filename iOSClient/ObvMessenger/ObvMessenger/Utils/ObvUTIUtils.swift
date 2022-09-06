/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


final class ObvUTIUtils {
    
    static let kUTTypeOlvidBackup = "io.olvid.type.olvidbackup" as CFString
    
    enum TagClass {
        case FilenameExtension
        case MIMEType
        
        fileprivate var cfString: CFString {
            switch self {
            case .FilenameExtension:
                return kUTTagClassFilenameExtension
            case .MIMEType:
                return kUTTagClassMIMEType
            }
        }
    }
    
    static func utiOfFile(atURL url: URL) -> String? {
        let fileExtension = url.pathExtension
        return utiOfFile(withExtension: fileExtension)
    }
    
    
    static func utiOfFile(withExtension fileExtension: String) -> String? {
        guard !fileExtension.isEmpty else { return nil }
        guard let utiFromExtension = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension as CFString, nil)?.takeRetainedValue() else { return nil }
        return String(utiFromExtension)
    }

    static func utiOfFile(withName fileName: String) -> String? {
        let fileExtension = NSString.init(string: fileName).pathExtension
        return utiOfFile(withExtension: fileExtension)
    }
    
    static func preferredTagWithClass(inUTI uti: String, inTagClass tagClass: TagClass) -> String? {
        guard let _tag = UTTypeCopyPreferredTagWithClass(uti as CFString, tagClass.cfString) else { return nil }
        let tag = _tag.takeRetainedValue()
        return String(tag)
    }
    
    
    static func utiOfMIMEType(_ mimeType: String) -> String? {
        guard let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType as CFString, nil)?.takeRetainedValue() else { return nil }
        return String(uti)
    }
    
    static func preferredMIMEType(forUTI uti: String) -> String? {
        let _tag = UTTypeCopyPreferredTagWithClass(uti as CFString, kUTTagClassMIMEType)!
        let tag = _tag.takeRetainedValue()
        return String(tag)
    }
    
    
    static func uti(_ uti: String, conformsTo conformingUTI: CFString) -> Bool {
        return UTTypeConformsTo(uti as CFString, conformingUTI)
    }
    
    
    static func jpegExtension() -> String {
        let _tag = UTTypeCopyPreferredTagWithClass(kUTTypeJPEG, kUTTagClassFilenameExtension)!
        let tag = _tag.takeRetainedValue()
        return String(tag)
    }


    static func pngExtension() -> String {
        let _tag = UTTypeCopyPreferredTagWithClass(kUTTypePNG, kUTTagClassFilenameExtension)!
        let tag = _tag.takeRetainedValue()
        return String(tag)
    }
    
    static func pdfExtension() -> String {
        let _tag = UTTypeCopyPreferredTagWithClass(kUTTypePDF, kUTTagClassFilenameExtension)!
        let tag = _tag.takeRetainedValue()
        return String(tag)
    }
    
    static func guessUTIOfBinaryFile(atURL url: URL) -> String? {
        
        let jpegPrefix = Data([0xff, 0xd8])
        let pngPrefix = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let pdfPrefix = Data([0x25, 0x50, 0x44, 0x46, 0x2D])
        let mp4Signatures = ["ftyp", "mdat", "moov", "pnot", "udta", "uuid", "moof", "free", "skip", "jP2 ", "wide", "load", "ctab", "imap", "matt", "kmat", "clip", "crgn", "sync", "chap", "tmcd", "scpt", "ssrc", "PICT"].map { Data([UInt8]($0.utf8)) }
        
        guard let fileData = try? Data(contentsOf: url) else {
            return nil
        }
        
        if fileData.starts(with: jpegPrefix) {
            return kUTTypeJPEG as String
        } else if fileData.starts(with: pngPrefix) {
            return kUTTypePNG as String
        } else if fileData.starts(with: pdfPrefix) {
            return kUTTypePDF as String
        } else if mp4Signatures.contains(fileData.advanced(by: 4)[0..<4]) {
            return kUTTypeMPEG4 as String
        } else {
            return nil
        }

    }
    
    
    static func getHumanReadableType(forUTI uti: String) -> String? {
        switch uti {
        case String(kUTTypeGIF): return "GIF"
        case String(kUTTypeJPEG): return "JPEG"
        case String(kUTTypeBMP): return "BMP"
        case String(kUTTypePDF): return "PDF"
        case String(kUTTypePNG): return "PNG"
        case String(kUTTypeRTF): return "RTF"
        case String(kUTTypeData): return "Data"
        case String(kUTTypeZipArchive): return "Zip"
        case "org.openxmlformats.wordprocessingml.document": return "Word"
        default: return nil
        }
    }

    @available(iOS 14.0, *)
    static func getIcon(forUTI uti: String) -> ObvSystemIcon {
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
