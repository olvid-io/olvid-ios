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

class ObvSubtitleTableViewCell: UITableViewCell, ObvTableViewCellWithActivityIndicator {

    static let nibName = "ObvSubtitleTableViewCell"
    static let identifier = "ObvSubtitleTableViewCell"

    // Views

    @IBOutlet weak var circlePlaceholder: UIView! { didSet { circlePlaceholder.backgroundColor = .clear } }
    @IBOutlet weak var titleStackView: UIStackView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var mainStackView: UIStackView!
    @IBOutlet weak var activityIndicatorPlaceholder: UIView!
    var activityIndicator: UIView?
    private var titleChip: ObvChipLabel?
    
    // Constraints
    
    @IBOutlet weak var circlePlaceholderHeightConstraint: NSLayoutConstraint!
    private let defaultCirclePlaceholderHeight: CGFloat = 56.0
    
    // Vars
    
    var title: String = "" { didSet { setTitle(); refreshCircledInitials() } }
    var subtitle: String = "" { didSet { setSubtitle() } }
    var identityColors: (background: UIColor, text: UIColor)? { didSet { refreshCircledInitials() } }
    var circledImage: UIImage? = nil { didSet { refreshCircledInitials() } }
    var circledImageURL: URL? = nil { didSet { refreshCircledInitials() } }
    var showGreenShield: Bool = false { didSet { refreshCircledInitials() } }
    var showRedShield: Bool = false { didSet { refreshCircledInitials() } }
    private var chipImageView: UIImageView?
    private var badgeView: DiscView?

    // Subviews set in awakeFromNib
    
    private let circledInitials = NewCircledInitialsView()

}


// MARK: - awakeFromNib

extension ObvSubtitleTableViewCell {
    
    override func awakeFromNib() {
        super.awakeFromNib()
                
        titleLabel.textColor = appTheme.colorScheme.label
        subtitleLabel.textColor = appTheme.colorScheme.secondaryLabel

        circlePlaceholder.addSubview(circledInitials)
        circledInitials.translatesAutoresizingMaskIntoConstraints = false
        circledInitials.pinAllSidesToSides(of: circlePlaceholder)
        
        activityIndicatorPlaceholder.backgroundColor = .clear
        
        prepareForReuse()
        
        
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        isHidden = false
        circledImage = nil
        circlePlaceholderHeightConstraint.constant = defaultCirclePlaceholderHeight
        removeChipLabelAndChipImageView()
        removeTitleChip()
        titleLabel.text = nil
        subtitleLabel.text = nil
        setDefaultSubtitleFont()
    }
    
}


// MARK: - Setting labels and texts

extension ObvSubtitleTableViewCell {
    
    func setCircleDiameter(to diameter: CGFloat) {
        self.circlePlaceholderHeightConstraint.constant = diameter
    }
    
    private func setTitle() {
        titleLabel.text = title
    }
    
    private func refreshCircledInitials() {
        circledInitials.configureWith(
            foregroundColor: self.identityColors?.text ?? appTheme.colorScheme.secondaryLabel,
            backgroundColor: self.identityColors?.background ?? appTheme.colorScheme.secondarySystemFill,
            icon: .textBubbleFill, // Never shown
            stringForInitial: title,
            photoURL: circledImageURL,
            showGreenShield: showGreenShield,
            showRedShield: showRedShield)
    }

    private func setSubtitle() {
        subtitleLabel.text = subtitle
    }
    
    func setChipLabel(text: String) {
        removeChipLabelAndChipImageView()
        let chipLabel = ObvChipLabel()
        chipLabel.text = text
        chipLabel.textColor = .white
        chipLabel.chipColor = AppTheme.appleBadgeRedColor
        chipLabel.widthAnchor.constraint(equalToConstant: chipLabel.intrinsicContentSize.width).isActive = true
        self.mainStackView.addArrangedSubview(chipLabel)
    }
    
    func removeChipLabelAndChipImageView() {
        if let chipLabel = self.mainStackView.arrangedSubviews.last as? ObvChipLabel {
            self.mainStackView.removeArrangedSubview(chipLabel)
            chipLabel.removeFromSuperview()
        }
        if let chipImageView = chipImageView {
            self.mainStackView.removeArrangedSubview(chipImageView)
            chipImageView.removeFromSuperview()
            self.chipImageView = nil
        }
    }
    
    func setChipImage(to image: UIImage, withBadge: Bool) {
        removeChipLabelAndChipImageView()
        self.chipImageView = UIImageView(image: image)
        self.chipImageView!.widthAnchor.constraint(equalToConstant: 30.0).isActive = true
        self.chipImageView!.heightAnchor.constraint(equalToConstant: 30.0).isActive = true
        self.chipImageView!.contentMode = .scaleAspectFit
        self.chipImageView!.tintColor = AppTheme.shared.colorScheme.secondaryLabel
        self.mainStackView.addArrangedSubview(self.chipImageView!)
        if withBadge {
            self.chipImageView!.layoutIfNeeded()
            self.badgeView = DiscView(frame: CGRect(x: self.chipImageView!.bounds.width-5, y: 0, width: 10, height: 10))
            self.badgeView!.color = .red
            self.badgeView?.backgroundColor = .clear
            self.chipImageView!.addSubview(self.badgeView!)
            self.badgeView!.layoutIfNeeded()
        }
    }
    
    
    func setChipCheckmark() {
        if #available(iOS 13, *) {
            let checkmark = UIImage(systemName: "checkmark.circle.fill")!.withTintColor(.green, renderingMode: .alwaysOriginal)
            setChipImage(to: checkmark, withBadge: false)
        } else {
            let checkmark = UIImage(named: "checkmark")!
            setChipImage(to: checkmark, withBadge: false)
            self.chipImageView?.tintColor = .green
        }
    }

    func setChipMute() {
        if #available(iOS 13, *) {
            let checkmark = UIImage(systemName: ObvMessengerConstants.muteIcon.systemName)!.withTintColor(.gray, renderingMode: .alwaysOriginal)
            setChipImage(to: checkmark, withBadge: false)
        }
    }

    
    func setChipXmark() {
        if #available(iOS 13, *) {
            let checkmark = UIImage(systemName: "xmark.circle.fill")!.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
            setChipImage(to: checkmark, withBadge: false)
        } else {
            let checkmark = UIImage(named: "xmark")!
            setChipImage(to: checkmark, withBadge: false)
            self.chipImageView?.tintColor = .systemRed
        }
    }
    
    func removeTitleChip() {
        if self.titleChip != nil {
            titleStackView.removeArrangedSubview(self.titleChip!)
            self.titleChip!.removeFromSuperview()
            self.titleChip = nil
            self.setNeedsDisplay()
        }
    }


    func setTitleChip(text: String) {
        removeTitleChip()
        self.titleChip = ObvChipLabel()
        self.titleChip!.text = text
        self.titleChip!.textColor = ObvChipLabel.defaultTextColor
        titleStackView.addArrangedSubview(self.titleChip!)
    }


    func makeSubtitleItalic() {
        let fontDescriptor = subtitleLabel.font.fontDescriptor
        guard let newDescriptor = fontDescriptor.withSymbolicTraits(.traitItalic) else { assertionFailure(); return }
        subtitleLabel.font = UIFont(descriptor: newDescriptor, size: 0) // 0 means keep existing size
    }

    func setDefaultSubtitleFont() {
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
    }
}
