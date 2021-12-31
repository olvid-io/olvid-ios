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
import UniformTypeIdentifiers
import QuickLookThumbnailing
import MobileCoreServices


@available(iOS 14.0, *)
final class UIImageViewForHardLink: UIImageView {
    
    private(set) var hardlink: HardLinkToFyle?
    
    override var image: UIImage? {
        get {
            return super.image
        }
        set {
            assertionFailure("Use setHardlink instead")
        }
    }
    
    
    func reset() {
        super.image = nil
        self.hardlink = nil
    }
    
    
    func setHardlink(newHardlink: HardLinkToFyle, withImage image: UIImage?) {
        if let image = image {
            setImageAndHardlink(newImage: image, newHardlink: newHardlink, contentMode: .scaleAspectFill)
        } else {
            setDefaultImageForUTIWithinHardlink(newHardlink)
        }
    }
    
    
    func setDownsizedThumbnail(withImage newImage: UIImage) {
        reset()
        super.image = newImage
        self.contentMode = .scaleAspectFill
        self.alpha = 1.0
        self.isHidden = false
    }
    
    private var imageForUTI = [String: UIImage]()

    private func setDefaultImageForUTIWithinHardlink(_ newHardlink: HardLinkToFyle) {
        assert(Thread.isMainThread)
        let uti = newHardlink.uti
        if let image = imageForUTI[uti] {
            setImageAndHardlink(newImage: image, newHardlink: newHardlink, contentMode: .center)
        } else {
            let configuration = UIImage.SymbolConfiguration(pointSize: 20)
            let image: UIImage
            if let utType = UTType(uti) {
                if utType.conforms(to: .image) {
                    image = UIImage(systemIcon: .photoOnRectangleAngled, withConfiguration: configuration)!
                } else if utType.conforms(to: .pdf) {
                    image = UIImage(systemIcon: .docRichtext, withConfiguration: configuration)!
                } else if ObvUTIUtils.uti(uti, conformsTo: kUTTypeAudio) {
                    image = UIImage(systemIcon: .musicNote, withConfiguration: configuration)!
                } else {
                    image = UIImage(systemIcon: .paperclip, withConfiguration: configuration)!
                }
            } else {
                image = UIImage(systemIcon: .paperclip, withConfiguration: configuration)!
            }
            imageForUTI[uti] = image
            setImageAndHardlink(newImage: image, newHardlink: newHardlink, contentMode: .center)
        }
        self.alpha = 1.0
        self.isHidden = false
    }

    
    private func setImageAndHardlink(newImage: UIImage, newHardlink: HardLinkToFyle, contentMode: UIView.ContentMode) {
        assert(Thread.isMainThread)
        self.hardlink = newHardlink
        super.image = newImage
        self.contentMode = contentMode
    }
}



@available(iOS 14.0, *)
final class UIImageViewForHardLinkForOlvidStack: ViewForOlvidStack {
 
    var hardlink: HardLinkToFyle? {
        imageViewForHardLink.hardlink
    }
    
    var image: UIImage? {
        imageViewForHardLink.image
    }

    let imageViewForHardLink = UIImageViewForHardLink()
 
    func setHardlink(newHardlink: HardLinkToFyle, withImage image: UIImage?) {
        imageViewForHardLink.setHardlink(newHardlink: newHardlink, withImage: image)
    }

    func reset() {
        imageViewForHardLink.reset()
    }

    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupInternalViews() {
        
        addSubview(imageViewForHardLink)
        imageViewForHardLink.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            imageViewForHardLink.topAnchor.constraint(equalTo: topAnchor),
            imageViewForHardLink.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageViewForHardLink.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageViewForHardLink.leadingAnchor.constraint(equalTo: leadingAnchor),
        ])
        
    }
}
