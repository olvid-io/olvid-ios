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

import UIKit

extension UIImage {
    convenience init?(color: UIColor, height: CGFloat) {
        let size = CGSize.init(width: 12, height: height / UIScreen.main.scale)
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        UIBezierPath.init(roundedRect: rect, cornerRadius: 6.0/UIScreen.main.scale).addClip()
        color.setFill()
        UIRectFill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let cgImage = image?.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }

    // Used within the settings pages
    func imageWithInsets(insets: UIEdgeInsets) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: self.size.width + insets.left + insets.right,
                   height: self.size.height + insets.top + insets.bottom), false, self.scale)
        _ = UIGraphicsGetCurrentContext()
        let origin = CGPoint(x: insets.left, y: insets.top)
        self.draw(at: origin)
        let imageWithInsets = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return imageWithInsets
    }

    var aspectRatio: CGFloat { size.width / size.height }

    func resize(with size: CGFloat) -> UIImage? {
        var width: CGFloat
        var height: CGFloat
        if aspectRatio > 1 {
            // Landscape image
            width = size
            height = size / aspectRatio
        } else {
            // Portrait image
            height = size
            width = size * aspectRatio
        }
        let newSize = CGSize(width: width, height: height)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        draw(in: CGRect(origin: CGPoint.zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage
    }
    
    
    func downsizeIfRequired(maxWidth: CGFloat, maxHeight: CGFloat) -> UIImage? {
        
        let ratio = min(maxWidth / self.size.width, maxHeight / self.size.height)

        // If the current image is small enough, return it
        
        guard ratio < 1 else {
            return self
        }
        
        // If we reach this point, at least one side of the image is too big.
        // We need to resize down the image
        
        let newSize = CGSize(
            width: self.size.width * ratio,
            height: self.size.height * ratio)
        
        // Create the downsized image
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        draw(in: CGRect(origin: CGPoint.zero, size: newSize))
        let downsizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        // Return it
        
        return downsizedImage
                        
    }
    
}
