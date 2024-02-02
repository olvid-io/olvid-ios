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
import CoreData
import PDFKit
import MobileCoreServices
import AVKit
import ObvUI
import ObvUICoreData
import ObvDesignSystem


class FyleCollectionViewCell: UICollectionViewCell {

    static let nibName = "FyleCollectionViewCell"
    static let identifier = "FyleCollectionViewCellIdentifier"
    
    // Views
    
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var imageViewPlaceholder: UIView!
    @IBOutlet weak var sizeTitle: UILabel!
    @IBOutlet weak var deleteImageView: UIImageView!
    
    
    // Constraints
    
    @IBOutlet weak var containerViewHeightConstraint: NSLayoutConstraint! {
        didSet {
            self.containerViewHeightConstraint.constant = FyleCollectionViewCell.intrinsicHeight
            self.setNeedsLayout()
        }
    }
    @IBOutlet weak var containerViewWidthConstraint: NSLayoutConstraint! {
        didSet {
            self.containerViewWidthConstraint.constant = FyleCollectionViewCell.intrinsicWidth
            self.setNeedsLayout()
        }
    }
    
    private var fyle: Fyle!
    
    // Other variables
        
    private let byteCountFormatter = ByteCountFormatter()
    
    static let intrinsicHeight: CGFloat = 130 + 8 // 8 for the image showing the "deletion" cross
    static let intrinsicWidth: CGFloat = 100 + 8 // 8 for the image showing the "deletion" cross
    static let intrinsicSize = CGSize(width: intrinsicWidth, height: intrinsicHeight)
    
    private var thumbnailObservationToken: NSKeyValueObservation?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        deleteImageView.image = UIImage.init(systemName: "xmark.circle.fill")!
        deleteImageView.tintColor = .red
        deleteImageView.tintColor = AppTheme.appleBadgeRedColor
    }
    
    
    override func prepareForReuse() {
        super.prepareForReuse()
        self.fyle = nil
        self.thumbnailObservationToken = nil
        _ = self.imageViewPlaceholder.subviews.map { $0.removeFromSuperview() }
    }

    
    func configure(with draftFyleJoin: PersistedDraftFyleJoin) {
        
        guard let draftFyleJoinFyle = draftFyleJoin.fyle else { return }
        guard let fyleElement = draftFyleJoin.fyleElement else { return }
        
        guard self.fyle?.objectID != draftFyleJoinFyle.objectID else {
            return
        }
        
        self.fyle = draftFyleJoinFyle
        
        self.setTitle(to: draftFyleJoin.fileName)
        self.setByteSize(to: Int(draftFyleJoinFyle.getFileSize() ?? -1))
        self.setPreview(with: fyleElement, thumbnailType: .normal)
        self.imageViewPlaceholder.tintColor = AppTheme.shared.colorScheme.tertiaryLabel
        
    }
    
    
    func configure(with fyleJoin: FyleJoin) {
        
        guard let draftFyleJoinFyle = fyleJoin.fyle else { return }
        guard let fyleElement = fyleJoin.genericFyleElement else { return }

        guard self.fyle?.objectID != draftFyleJoinFyle.objectID else {
            return
        }
        
        self.fyle = fyleJoin.fyle
        
        self.setTitle(to: fyleJoin.fileName)
        self.setByteSize(to: Int(draftFyleJoinFyle.getFileSize() ?? -1))
        self.setPreview(with: fyleElement, thumbnailType: .normal)
        self.imageViewPlaceholder.tintColor = AppTheme.shared.colorScheme.tertiaryLabel
        
    }
    
}


extension FyleCollectionViewCell {
    
    private func setTitle(to title: String) {
        self.label.text = title
        self.setNeedsLayout()
    }
    
    
    private func setPreview(with fyleElement: FyleElement, thumbnailType: ThumbnailType) {
        
        let completionHandler = { (thumbnail: Thumbnail) in
            DispatchQueue.main.async { [weak self] in
                guard let _self = self else { return }
                
                // Make sure we have the thumbnail corresponding to the current attachment (in case the cell was reused)
                guard thumbnail.fyleURL == _self.fyle?.url else {
                    return
                }
                
                let imageView = UIImageView(image: thumbnail.image)
                imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                imageView.contentMode = .scaleAspectFill
                if thumbnail.isSymbol {
                    // If the thumbnail was obtained using a symbol (typically, an SF symbol), we add some padding
                    let padding: CGFloat = max(_self.imageViewPlaceholder.bounds.width, _self.imageViewPlaceholder.bounds.height) / 4.0
                    let origin = CGPoint(x: padding, y: padding)
                    let insets = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
                    imageView.frame = CGRect(origin: origin, size: _self.imageViewPlaceholder.bounds.inset(by: insets).size)
                    imageView.tintColor = _self.appTheme.colorScheme.systemFill
                } else {
                    // If the thumbnail is not a symbol, but an actual thumbnail of the attachment, we do not add any padding
                    imageView.frame = CGRect(origin: CGPoint.zero, size: _self.imageViewPlaceholder.bounds.size)
                }
                _self.imageViewPlaceholder.backgroundColor = _self.appTheme.colorScheme.secondarySystemBackground
                self?.setCornersStyle(to: .rounded)
                imageView.isHidden = true
                self?.imageViewPlaceholder.addSubview(imageView)
                UIView.transition(with: _self.imageViewPlaceholder, duration: 0.3, options: .transitionCrossDissolve, animations: {
                    imageView.isHidden = false
                })
            }
        }
        ObvMessengerInternalNotification.requestThumbnail(fyleElement: fyleElement,
                                                          size: imageViewPlaceholder.bounds.size,
                                                          thumbnailType: thumbnailType,
                                                          completionHandler: completionHandler)
            .postOnDispatchQueue()
    }
    
    
    private func setByteSize(to byteSize: Int) {
        self.sizeTitle.text = byteCountFormatter.string(fromByteCount: Int64(byteSize))
    }
    
    enum ImageCornerStyle {
        case rounded
        case square
    }
    
    private func setCornersStyle(to style: ImageCornerStyle) {
        switch style {
        case .rounded:
            self.imageViewPlaceholder.layer.borderColor = UIColor.lightGray.cgColor
            self.imageViewPlaceholder.layer.borderWidth = 1.0
            self.imageViewPlaceholder.layer.cornerRadius = 5.0
        case .square:
            self.imageViewPlaceholder.layer.borderColor = UIColor.clear.cgColor
            self.imageViewPlaceholder.layer.borderWidth = 0.0
            self.imageViewPlaceholder.layer.cornerRadius = 0.0
        }
        self.imageViewPlaceholder.layer.masksToBounds = true
    }
}
