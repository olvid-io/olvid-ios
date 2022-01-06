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

class MultipleButtonsCollectionViewCell: ObvCardCollectionViewCell, InvitationCollectionCell, CellContainingHeaderView {

    static let nibName = "MultipleButtonsCollectionViewCell"
    static let identifier = "MultipleButtonsCollectionViewCell"

    // Views
    
    @IBOutlet weak var placeholderView: UIView!
    @IBOutlet weak var topPlaceholderView: UIView!
    @IBOutlet weak var bottomPlaceholderView: UIView!

    // Constraints
    
    private var widthConstraint: NSLayoutConstraint!
    
    // Subviews set in awakeFromNib
    
    var cellHeaderView: CellHeaderView!
    var buttonsStackView: UIStackView!
    private var buttonAction = [UIButton: () -> Void]()
    
}


// MARK: - awakeFromNib

extension MultipleButtonsCollectionViewCell {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.accessibilityIdentifier = "MultipleButtonsCollectionViewCell"
        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        self.widthConstraint = self.contentView.widthAnchor.constraint(equalToConstant: 50.0)
        self.widthConstraint.isActive = true
        instantiateAndPlaceTheCellHeaderView()
        instantiateAndPlaceTheButtonsStackView()
    }
    
    private func instantiateAndPlaceTheCellHeaderView() {
        topPlaceholderView.backgroundColor = .clear
        cellHeaderView = (Bundle.main.loadNibNamed(CellHeaderView.nibName, owner: nil, options: nil)!.first as! CellHeaderView)
        topPlaceholderView.addSubview(cellHeaderView)
        topPlaceholderView.pinAllSidesToSides(of: cellHeaderView)
    }
    
    private func instantiateAndPlaceTheButtonsStackView() {
        bottomPlaceholderView?.backgroundColor = .clear
        self.buttonsStackView = UIStackView()
        self.buttonsStackView.translatesAutoresizingMaskIntoConstraints = false
        self.buttonsStackView.axis = .vertical
        self.buttonsStackView.spacing = 16.0
        bottomPlaceholderView.addSubview(buttonsStackView)
        let constraints = [bottomPlaceholderView.topAnchor.constraint(equalTo: buttonsStackView.topAnchor, constant: 0.0),
                           bottomPlaceholderView.trailingAnchor.constraint(equalTo: buttonsStackView.trailingAnchor, constant: 16.0),
                           bottomPlaceholderView.bottomAnchor.constraint(equalTo: buttonsStackView.bottomAnchor, constant: 16.0),
                           bottomPlaceholderView.leadingAnchor.constraint(equalTo: buttonsStackView.leadingAnchor, constant: -16.0)]
        NSLayoutConstraint.activate(constraints)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        cellHeaderView.prepareForReuse()
        buttonAction.removeAll()
        for view in buttonsStackView.arrangedSubviews {
            buttonsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
    
}


// MARK: - Setting the width and accessing the size

extension MultipleButtonsCollectionViewCell {
    
    func setWidth(to newWidth: CGFloat) {
        widthConstraint.constant = newWidth
    }
    
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        setNeedsLayout()
        layoutIfNeeded()
        let size = contentView.systemLayoutSizeFitting(layoutAttributes.size)
        var newFrame = layoutAttributes.frame
        newFrame.size = size
        layoutAttributes.frame = newFrame
        return layoutAttributes
    }
}


// MARK: - Adding buttons

extension MultipleButtonsCollectionViewCell {
    
    enum ButtonStyle {
        case obvButton
        case obvButtonBorderless
    }
    
    func addButton(title: String, style: ButtonStyle, action: @escaping (() -> Void)) {
        let button: ObvButton
        switch style {
        case .obvButton:
            button = ObvButton()
        case .obvButtonBorderless:
            button = ObvButtonBorderless()
        }
        button.setTitle(title, for: .normal)
        buttonAction[button] = action
        button.addTarget(self, action: #selector(buttonTapped), for: UIControl.Event.touchUpInside)
        buttonsStackView.addArrangedSubview(button)
    }
    
    @objc func buttonTapped(button: UIButton) {
        guard let action = buttonAction[button] else { return }
        action()
    }
    
}
