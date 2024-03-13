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
import LinkPresentation

/// Makes it possible to create an ``ObvLinkMetadata`` from a standard ``LPLinkMetadata``
extension ObvLinkMetadata {
    
    public static let maxIconSize = CGSize(width: 1080, height: 1080)
    
    public static func from(linkMetadata: LPLinkMetadata) async -> ObvLinkMetadata {
        return await withCheckedContinuation { (continuation: CheckedContinuation<ObvLinkMetadata, Never>) in

            let title = linkMetadata.title
            let url = linkMetadata.url
            let desc = linkMetadata.value(forKey: "summary") as? String
            
            let imageProvider = linkMetadata.imageProvider ?? linkMetadata.iconProvider
            if let imageProvider = imageProvider {
                imageProvider.loadObject(ofClass: UIImage.self, completionHandler: { image, error in
                    guard error == nil, let image = image as? UIImage else {
                        let preview = ObvLinkMetadata(title: title, desc: desc, url: url, pngData: nil)
                        return continuation.resume(returning: preview)
                    }
                    let downSizedImage = image.downsizeIfRequired(maxWidth: maxIconSize.width, maxHeight: maxIconSize.height)
                    let preview = ObvLinkMetadata(title: title, desc: desc, url: url, pngData: downSizedImage?.pngData())
                    return continuation.resume(returning: preview)
                })

            }
            else {
                let preview = ObvLinkMetadata(title: title, desc: desc, url: url, pngData: nil)
                return continuation.resume(returning: preview)
            }
        }
        
    }
        
}
