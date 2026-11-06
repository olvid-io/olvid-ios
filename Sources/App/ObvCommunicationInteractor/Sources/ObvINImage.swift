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
import Intents
import ObvDesignSystem


/// Shared factory for `INImage` instances used by SiriKit donations and the IntentsExtension.
/// Centralized here so both the main-app donation path (`ObvCommunicationMapper`) and the
/// IntentsExtension's INPerson/discussion conversions produce identically sized and encoded
/// images.
public enum ObvINImage {

    /// Diameter (in points) used when rendering the circled-character fallback drawn behind an
    /// identity that has no profile photo.
    public static let circleDiameter: CGFloat = 192

    /// Builds an `INImage` from a profile photo URL, falling back to a pre-rendered image (typically
    /// a circled character or symbol). Always downsizes to roughly 300×300 before encoding so the
    /// Intents framework can carry it cheaply across XPC boundaries.
    ///
    /// We do not use `INImage(url:)`: that initializer has been observed to drop images in the
    /// standard share-sheet API. We always go through `INImage(imageData:)` with a downsized PNG.
    /// The downsizing is intentionally aggressive because this method is also called from the
    /// notification extension, which has a tight memory budget — keep callers aware that they
    /// should only build one `INImage` per notification when possible.
    public static func make(photoURL: URL?, fallbackImage: UIImage?) -> INImage? {

        guard photoURL != nil || fallbackImage != nil else { return nil }

        let imageSideSize = CGFloat(300)

        if let photoURL,
           FileManager.default.fileExists(atPath: photoURL.path),
           let image = UIImage(contentsOfFile: photoURL.path),
           let downSizedImage = image.downsizeIfRequired(maxWidth: imageSideSize, maxHeight: imageSideSize),
           let imageData = downSizedImage.pngData() {
            return INImage(imageData: imageData)
        }

        if let fallbackImage,
           let downSizedImage = fallbackImage.downsizeIfRequired(maxWidth: imageSideSize, maxHeight: imageSideSize),
           let imageData = downSizedImage.pngData() {
            return INImage(imageData: imageData)
        }

        assertionFailure("Since at least one image source was provided, we expect to be able to return an INImage")

        return nil

    }

}
