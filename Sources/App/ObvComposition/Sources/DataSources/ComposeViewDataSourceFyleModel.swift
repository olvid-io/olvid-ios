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
import UIKit
import UniformTypeIdentifiers
import ObvAppTypes

public struct ComposeViewDataSourceFyleModel: Sendable, Equatable, Hashable {
    
    public enum FyleMessageJoinType: Sendable, Equatable {
        case photo
        case video
        case audio
        case other
    }
    
    public struct ContentTypeAndImage: Sendable, Equatable, Hashable {
        let contentType: UTType
        let image: UIImage?
        public init(contentType: UTType, image: UIImage?) {
            self.contentType = contentType
            self.image = image
        }
    }
    
    let contentTypeAndImage: ContentTypeAndImage
    
    let linkMetadata: ObvLinkMetadata?
    
    let audioURL: URL?
    
    let attachmentType: FyleMessageJoinType
    
    public init(attachmentType: FyleMessageJoinType, contentTypeAndImage: ContentTypeAndImage, linkMetadata: ObvLinkMetadata?, audioURL: URL?) {
        self.attachmentType = attachmentType
        self.contentTypeAndImage = contentTypeAndImage
        self.linkMetadata = linkMetadata
        self.audioURL = audioURL
    }
    
}
