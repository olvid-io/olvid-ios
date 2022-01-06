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

// Warning: This class should not be used anymore. We should use NewCircledInitialsView instead.
final class CircledInitials: UIView {

    static let nibName = "CircledInitials"

    // Views
    
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var imageView: RoundedImageView!
    @IBOutlet weak var photoView: RoundedImageView!
    
    // Properties
    
    var identityColors: (background: UIColor, text: UIColor)? = nil { didSet { resetColorsFromData() } }
    private var discColor: UIColor? = nil { didSet { setNeedsDisplay() } }
    private var circleColor: UIColor? = nil { didSet { setNeedsDisplay() } }
    var withShadow = false { didSet { setNeedsDisplay() } }

    // Constants
    
    private let lineWidth: CGFloat = 0.0
    private let numberOfCharactersWithinCircle = 1
    private let boldThresholdPointSize: CGFloat = 28.0
    
}


// MARK: - awakeFromNib

extension CircledInitials {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        resetEverything()
    }

}


// MARK: - Draw and helpers

extension CircledInitials {
    
    override func draw(_ rect: CGRect) {
        
        if withShadow {
            let shadowPath = UIBezierPath(ovalIn: self.bounds)
            layer.masksToBounds = false
            layer.shadowOpacity = 0.3
            layer.shadowRadius = 1.0
            layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowPath = shadowPath.cgPath
        }

        // Draw the disc first
        
        let discBounds = self.bounds.insetBy(dx: lineWidth, dy: lineWidth)
        let disc = UIBezierPath(ovalIn: discBounds)
        discColor?.setFill()
        disc.fill()
        
        // Draw the circle
        
        let circleBounds = self.bounds.insetBy(dx: lineWidth, dy: lineWidth)
        let circle = UIBezierPath(ovalIn: circleBounds)
        circle.lineWidth = lineWidth
        circleColor?.setStroke()
        circle.stroke()
        
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // We adjust the font size and choose a bold font in case the font size is too small
        let size = self.bounds.width / (1.415 * CGFloat(numberOfCharactersWithinCircle))
        if size > self.boldThresholdPointSize {
            self.label.font = UIFont.systemFont(ofSize: size, weight: UIFont.Weight.regular)
        } else {
            self.label.font = UIFont.systemFont(ofSize: size, weight: UIFont.Weight.bold)
        }
    }
}


// MARK: - Deriving colors for the data

extension CircledInitials {
    
    private func resetColorsFromData() {
        
        guard let identityColors = self.identityColors else {
            discColor = .clear
            circleColor = .lightGray
            label.textColor = .lightGray
            return
        }
        
        discColor = identityColors.background
        circleColor = identityColors.text
        label.textColor = identityColors.text
        self.imageView.tintColor = identityColors.text

        self.setNeedsDisplay()
        
    }
    
    
    func showCircledText(from _title: String?) {
        guard let title = _title else { return }
        var tokens = title.components(separatedBy: " ")
        tokens = tokens.map { return $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        tokens = tokens.filter { return !$0.isEmpty }
        tokens = tokens.map { "\($0.first ?? Character(""))" }
        var text = ""
        while text.count < numberOfCharactersWithinCircle && !tokens.isEmpty {
            let token = tokens.removeFirst()
            text += token.prefix(1)
        }
        label.text = text
        hideEverythinExcept(elementShown: .label)
    }
    
    func showImage(fromImage _image: UIImage?) {
        guard let image = _image else { return }
        if #available(iOS 13, *) {
            imageView.contentMode = .scaleAspectFit
        }
        imageView.image = image
        hideEverythinExcept(elementShown: .image)
    }

    func showPhoto(fromUrl url: URL?) {
        guard let url = url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        guard let image = UIImage(data: data) else { return }
        photoView.image = image
        hideEverythinExcept(elementShown: .photo)
    }
    
    private enum ElementShown {
        case label
        case image
        case photo
    }
    
    private func hideEverythinExcept(elementShown: ElementShown) {
        photoView.isHidden = (elementShown != .photo)
        label.isHidden = (elementShown != .label)
        imageView.isHidden = (elementShown != .image)
    }
    
    func resetEverything() {
        photoView.isHidden = true
        label.isHidden = true
        imageView.isHidden = true
        photoView.image = nil
        label.text = nil
        imageView.image = nil
    }
    
}

@IBDesignable public class RoundedImageView: UIImageView {

    override public func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = 0.5 * bounds.size.width
    }
}
