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

class QRCodeScannerView: UIView {

    private let insetForInsideRect: CGFloat = 10
    private let insideRectLineWidth: CGFloat = 2
    private let insideRectColor: UIColor = .white
    private let ratioSmallLinesLength: CGFloat = 0.2
    private let smallLinesWidth: CGFloat = 2
    lazy private var smallLinesColor: UIColor! = { return AppTheme.shared.colorScheme.secondary }()
    
    override func draw(_ rect: CGRect) {
        
        // Draw the transparent background (made of 4 line of width equal to the insetForInsideRect
        
        do {
            let path = UIBezierPath()
            path.lineWidth = insetForInsideRect * 2
            
            path.move(to: self.bounds.origin)
            path.addLine(to: CGPoint(x: self.bounds.origin.x + self.bounds.width, y: self.bounds.origin.y))
            path.addLine(to: CGPoint(x: self.bounds.origin.x + self.bounds.width, y: self.bounds.origin.y + self.bounds.height))
            path.addLine(to: CGPoint(x: self.bounds.origin.x, y: self.bounds.origin.y + self.bounds.height))
            path.addLine(to: CGPoint(x: self.bounds.origin.x, y: self.bounds.origin.y))

            UIColor(named: "QRCodeScannerTransparentBackground")?.setStroke()
            path.stroke()
        }
        
        // Draw the square
        
        do {
            let insideRect = UIBezierPath(rect: self.bounds.insetBy(dx: insetForInsideRect, dy: insetForInsideRect))
            insideRect.lineWidth = insideRectLineWidth
            insideRectColor.setStroke()
            insideRect.stroke()
        }
        
        // Draw the 2 x 4 = 8 lines on the 4 edges
        
        do {
            
            let path = UIBezierPath()
            path.lineWidth = smallLinesWidth
            
            // Top left corner
            do {
                let refPoint = self.bounds.origin
                path.move(to: refPoint)
                path.addLine(to: CGPoint(x: refPoint.x + self.bounds.width * ratioSmallLinesLength,
                                         y: refPoint.y))
                path.move(to: refPoint)
                path.addLine(to: CGPoint(x: refPoint.x,
                                         y: refPoint.y + self.bounds.height * ratioSmallLinesLength))

            }

            // Top right corner
            do {
                let refPoint = CGPoint(x: self.bounds.origin.x + self.bounds.width, y: self.bounds.origin.y)
                path.move(to: refPoint)
                path.addLine(to: CGPoint(x: refPoint.x - self.bounds.width * ratioSmallLinesLength,
                                         y: refPoint.y))
                path.move(to: refPoint)
                path.addLine(to: CGPoint(x: refPoint.x,
                                         y: refPoint.y + self.bounds.height * ratioSmallLinesLength))
            }

            // Bottom right corner
            do {
                let refPoint = CGPoint(x: self.bounds.origin.x + self.bounds.width, y: self.bounds.origin.y + self.bounds.height)
                path.move(to: refPoint)
                path.addLine(to: CGPoint(x: refPoint.x - self.bounds.width * ratioSmallLinesLength,
                                         y: refPoint.y))
                path.move(to: refPoint)
                path.addLine(to: CGPoint(x: refPoint.x,
                                         y: refPoint.y - self.bounds.height * ratioSmallLinesLength))
            }

            // Bottom left corner
            do {
                let refPoint = CGPoint(x: self.bounds.origin.x, y: self.bounds.origin.y + self.bounds.height)
                path.move(to: refPoint)
                path.addLine(to: CGPoint(x: refPoint.x + self.bounds.width * ratioSmallLinesLength,
                                         y: refPoint.y))
                path.move(to: refPoint)
                path.addLine(to: CGPoint(x: refPoint.x,
                                         y: refPoint.y - self.bounds.height * ratioSmallLinesLength))
            }

            smallLinesColor.setStroke()
            path.stroke()
            
        }
        
        
    }

}
