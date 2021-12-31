/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


public extension UIImage {
    
    /// Typically used to compute a thumbnail used in user notifications
    @available(iOS 13.0, *)
    static func makeCircledCharacter(fromString: String, circleDiameter: CGFloat, fillColor: UIColor, characterColor: UIColor) -> UIImage? {
        guard let initialChar = fromString.first else { return nil }
        let initial = String(initialChar)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: circleDiameter, height: circleDiameter))
        return renderer.image { ctx in
            let rectangle = CGRect(x: 0, y: 0, width: circleDiameter, height: circleDiameter)

            ctx.cgContext.setFillColor(fillColor.cgColor)
            ctx.cgContext.setLineWidth(0.0)
            ctx.cgContext.addEllipse(in: rectangle)
            ctx.cgContext.drawPath(using: .fillStroke)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let attributes: [NSAttributedString.Key: Any] = [
                .paragraphStyle: paragraphStyle,
                .font: UIFont.rounded(ofSize: circleDiameter / 2, weight: .black),
                .foregroundColor: characterColor,
            ]
            let attributedString = NSAttributedString(string: initial, attributes: attributes)
            let height = attributedString.size().height

            attributedString.draw(with: CGRect(x: 0, y: (circleDiameter - height) / 2, width: circleDiameter, height: circleDiameter), options: [.usesLineFragmentOrigin], context: nil)
        }
    }

    /// Typically used to compute a thumbnail used in user notifications
    @available(iOS 13.0, *)
    static func makeCircledSymbol(from systemName: String, circleDiameter: CGFloat, fillColor: UIColor, symbolColor: UIColor) -> UIImage? {

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: circleDiameter, height: circleDiameter))
        return renderer.image { ctx in
            let rectangle = CGRect(x: 0, y: 0, width: circleDiameter, height: circleDiameter)

            ctx.cgContext.setFillColor(fillColor.cgColor)
            ctx.cgContext.setLineWidth(0.0)
            ctx.cgContext.addEllipse(in: rectangle)
            ctx.cgContext.drawPath(using: .fillStroke)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let textAttachment = NSTextAttachment()
            textAttachment.image = UIImage(systemName: systemName)?.withRenderingMode(.alwaysTemplate)
            textAttachment.setImageHeight(height: circleDiameter / 2.5)

            let attributedString = NSMutableAttributedString(attachment: textAttachment)

            let attributes: [NSAttributedString.Key: Any] = [
                .paragraphStyle: paragraphStyle,
                .foregroundColor: symbolColor,
            ]
            attributedString.addAttributes(attributes, range: NSRange(location: 0, length: attributedString.length))

            let height = attributedString.size().height

            attributedString.draw(with: CGRect(x: 0, y: (circleDiameter - height) / 2, width: circleDiameter, height: circleDiameter), options: [.usesLineFragmentOrigin], context: nil)
        }
    }

}

extension NSTextAttachment {
    func setImageHeight(height: CGFloat) {
        guard let image = image else { return }
        let ratio = image.size.width / image.size.height

        bounds = CGRect(x: bounds.origin.x, y: bounds.origin.y, width: ratio * height, height: height)
    }
}
