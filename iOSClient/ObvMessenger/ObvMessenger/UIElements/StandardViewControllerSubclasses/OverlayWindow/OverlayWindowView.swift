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

class OverlayWindowView: UIView {

    static let nibName = "OverlayWindowView"
    
    // Views
    
    @IBOutlet weak var viewPlaceholder: UIView!
    @IBOutlet weak var stackView: UIStackView!
    
    // Constraints
    
    @IBOutlet weak var viewPlaceholderWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var viewPlaceholderHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var viewPlaceholderTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var viewPlaceholderLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var stackViewLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var stackViewCenterConstraint: NSLayoutConstraint!
    
    // Variables
    
    private var actions = [(title: String, callback: () -> Void)]()
    var maskLayerTopMargin: CGFloat?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.translatesAutoresizingMaskIntoConstraints = false
        viewPlaceholder.backgroundColor = .clear
    }
    
    func setHorizontalCenter(to center: CGFloat) {
        stackViewLeadingConstraint.constant = center
    }
    
    func addView(_ view: UIView) {
        viewPlaceholderWidthConstraint.constant = view.frame.width
        viewPlaceholderHeightConstraint.constant = view.frame.height
        viewPlaceholderTopConstraint.constant = view.frame.origin.y
        viewPlaceholderLeadingConstraint.constant = view.frame.origin.x
        view.translatesAutoresizingMaskIntoConstraints = false
        viewPlaceholder.addSubview(view)
        viewPlaceholder.pinAllSidesToSides(of: view)
    }
    
    func addAction(title: String, image: UIImage, callback: @escaping () -> Void) {
        if !stackView.arrangedSubviews.isEmpty {
            let line = createLineView()
            stackView.addArrangedSubview(line)
        }
        let actionView = (Bundle.main.loadNibNamed(OverlayActionView.nibName, owner: nil, options: nil)!.first! as! OverlayActionView)
        actionView.addAction(title: title, image: image, callback: callback)
        stackView.addArrangedSubview(actionView)
        _ = stackView.arrangedSubviews.map {
            ($0 as? OverlayActionView)?.isTopActionView = false
            ($0 as? OverlayActionView)?.isBottomActionView = false
        }
        (stackView.arrangedSubviews.first as? OverlayActionView)?.isTopActionView = true
        (stackView.arrangedSubviews.last as? OverlayActionView)?.isBottomActionView = true
    }
    
    
    private var spaceAboveViewPlaceholder: CGFloat {
        return viewPlaceholder.frame.origin.y - (maskLayerTopMargin ?? 0)
    }
    
    
    private var spaceUnderViewPlaceholder: CGFloat {
        return self.bounds.height - viewPlaceholder.frame.origin.y - viewPlaceholder.frame.height
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if stackView.frame.height < max(spaceAboveViewPlaceholder, spaceUnderViewPlaceholder) {
            if spaceAboveViewPlaceholder > spaceUnderViewPlaceholder {
                stackViewCenterConstraint.constant = -(viewPlaceholder.frame.height + stackView.frame.height + CGFloat(32)) / CGFloat(2)
            } else {
                stackViewCenterConstraint.constant = (viewPlaceholder.frame.height + stackView.frame.height + CGFloat(8)) / CGFloat(2)
            }
        } else {
            // The height of the message is too large, we center the menu on the screen
            stackViewCenterConstraint?.isActive = false
            stackView.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true
            stackView.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
        }
        
        
    }
    
    func createLineView() -> UIView {
        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1.0).isActive = true
        line.backgroundColor = appTheme.colorScheme.whiteTextDisabled
        return line
    }
}
