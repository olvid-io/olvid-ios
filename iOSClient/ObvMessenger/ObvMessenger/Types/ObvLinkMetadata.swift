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
import os.log
import UniformTypeIdentifiers
import ObvCrypto
import ObvEncoder
import ObvUICoreData
import UIKit

/// Represents an "url preview" metadata. This is the type to use to send/receive and store links metadatas.
final class ObvLinkMetadata: NSObject, ObvFailableEncodable, NSSecureCoding {

    let title: String?
    let desc: String?
    let url: URL?
    let pngData: Data?

    lazy var image: UIImage? = {
        guard let pngData else { return nil }
        return UIImage(data: pngData)
    }()

    
    //MARK: Extension - NSSecureCoding
    static var supportsSecureCoding: Bool { return true }
    
    func encode(with coder: NSCoder) {
        do {
            let obvEncoded = try self.obvEncode()
            coder.encode(obvEncoded.rawData)
        } catch {
            debugPrint("Cannot encode ObvLinkMetadata")
        }
    }
    
    init?(coder: NSCoder) {
        if let obvEncodedData = coder.decodeData(), let obvEncoded = ObvEncoded(withRawData: obvEncodedData), let linkMetadata = ObvLinkMetadata(obvEncoded) {
            self.pngData = linkMetadata.pngData
            self.title = linkMetadata.title
            self.desc = linkMetadata.desc
            self.url = linkMetadata.url
        } else {
            return nil
        }
    }

    //MARK: Extension - ObvFailableCodable
    func obvEncode() throws -> ObvEncoder.ObvEncoded {
        var obvDic = ObvDictionary()
        
        try obvDic.obvEncodeIfPresent(title, forKey: ObvLinkMetadata.MetadataKeys.title)
        try obvDic.obvEncodeIfPresent(desc, forKey: ObvLinkMetadata.MetadataKeys.desc)
        try obvDic.obvEncodeIfPresent(url, forKey: ObvLinkMetadata.MetadataKeys.url)
        try obvDic.obvEncodeIfPresent(pngData, forKey: ObvLinkMetadata.MetadataKeys.image)
                
        return obvDic.obvEncode()
    }
    
    private init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
        guard let obvDic = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
        do {
            self.title = try obvDic.obvDecodeIfPresent(String.self, forKey: ObvLinkMetadata.MetadataKeys.title)
            self.desc = try obvDic.obvDecodeIfPresent(String.self, forKey: ObvLinkMetadata.MetadataKeys.desc)
            self.url = try obvDic.obvDecodeIfPresent(URL.self, forKey: ObvLinkMetadata.MetadataKeys.url)
            self.pngData = try obvDic.obvDecodeIfPresent(Data.self, forKey: ObvLinkMetadata.MetadataKeys.image)
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
    }
    
    
    private static var log: OSLog {
        return OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    }
    
    
    init(title: String?, desc: String?, url: URL?, pngData: Data?) {
        self.title = title
        self.desc = desc
        self.url = url
        self.pngData = pngData
    }
    
    
    /// If the encoded link metadata does not provide an URL, the ``fallbackURL`` is used instead.
    static func decode(_ obvEncoded: ObvEncoded, fallbackURL: URL?) -> ObvLinkMetadata? {
        guard let obvDictionary = ObvDictionary(obvEncoded) else {
            return nil
        }
        
        let title: String?
        let desc: String?
        let pngData: Data?
        let url: URL?

        //let preview = ObvLinkMetadata()
        
        if let titleEncoded = obvDictionary[MetadataKeys.title.asKey] {
            title = String(titleEncoded)
        } else {
            title = nil
        }
        
        if let descriptionEncoded = obvDictionary[MetadataKeys.desc.asKey] {
            let description = String(descriptionEncoded)
            desc = description
        } else {
            desc = nil
        }
        
        if let imageEncoded = obvDictionary[MetadataKeys.image.asKey], let imageData = Data(imageEncoded) {
            pngData = imageData
        } else {
            pngData = nil
        }

        if let urlEncoded = obvDictionary[MetadataKeys.url.asKey], let _url = URL(urlEncoded) {
            url = _url
        } else {
            url = fallbackURL
        }

        return Self.init(
            title: title,
            desc: desc,
            url: url,
            pngData: pngData)
        
    }
}

// MARK: extension - Equatable
extension ObvLinkMetadata {
    static func == (lhs: ObvLinkMetadata, rhs: ObvLinkMetadata) -> Bool {
        return lhs.title == rhs.title
        && lhs.desc == rhs.desc
        && lhs.url == rhs.url
        && lhs.pngData == rhs.pngData
    }
}

extension ObvLinkMetadata {
    
    private enum MetadataKeys:String, CodingKey {
        case title  = "title"
        case image  = "image"
        case url    = "url"
        case desc   = "desc"
        
        var asKey: Data {
            rawValue.data(using: .utf8)!
        }
    }
    
}

