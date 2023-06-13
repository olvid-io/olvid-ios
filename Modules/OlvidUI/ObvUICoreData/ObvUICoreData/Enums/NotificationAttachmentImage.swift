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
  

import CoreGraphics
import Foundation
import UIKit


public enum NotificationAttachmentImage {

    case cgImage(attachmentNumber: Int, CGImage)
    case data(attachmentNumber: Int, Data)
    case url(attachmentNumber: Int, URL)

    
    public var attachmentNumber: Int {
        switch self {
        case .cgImage(let attachmentNumber, _),
                .data(let attachmentNumber, _),
                .url(let attachmentNumber, _):
            return attachmentNumber
        }
    }

    
    public enum DataOrURL {
        case data(Data)
        case url(URL)
    }

    
    public var dataOrURL: DataOrURL? {
        switch self {
        case .cgImage(_, let cgImage):
            let image = UIImage(cgImage: cgImage)
            guard let jpegData = image.jpegData(compressionQuality: 1.0) else {
                assertionFailure(); return nil
            }
            return .data(jpegData)
        case .data(_, let data):
            return .data(data)
        case .url(_, let url):
            return .url(url)
        }
    }

    
    public var quality: String {
        switch self {
        case .cgImage, .data:
            return "small"
        case .url:
            return "large"
        }
    }
    
}
