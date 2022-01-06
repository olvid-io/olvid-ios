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

class OwnedIdentityView: UIView {

    static let nibName = "OwnedIdentityView"
    
    // Views
    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var circlePlaceholder: UIView!
    @IBOutlet weak var touchOverlayView: UIView!
    
    // Vars
    
    var title: String = "" { didSet { setTitle(); setCircledText() } }
    var subtitle: String = "" { didSet { setSubtitle() } }
    var identityColors: (background: UIColor, text: UIColor)? { didSet { setIdentityColors() } }
    var circledImage: UIImage? = nil { didSet { setCircledImage() } }
    
    // Subviews set in awakeFromNib
    
    var circledInitials: CircledInitials!

    // Other vars
    
    weak var delegate: OwnedIdentityViewDelegate? = nil
    
}


extension OwnedIdentityView {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.translatesAutoresizingMaskIntoConstraints = false
        
        backgroundColor = .clear
        circlePlaceholder.backgroundColor = .clear
        titleLabel.textColor = appTheme.colorScheme.label
        subtitleLabel.textColor = appTheme.colorScheme.secondaryLabel
        
        circledInitials = (Bundle.main.loadNibNamed(CircledInitials.nibName, owner: nil, options: nil)!.first as! CircledInitials)
        circlePlaceholder.addSubview(circledInitials)
        circlePlaceholder.pinAllSidesToSides(of: circledInitials)
        
        let tapRecognizer = UITapGestureRecognizer.init(target: self, action: #selector(viewWasTapped))
        touchOverlayView.addGestureRecognizer(tapRecognizer)
    }
    
}

extension OwnedIdentityView {
    
    private func setTitle() {
        titleLabel.text = title
    }
    
    private func setCircledText() {
        guard circledImage == nil else { return }
        circledInitials.showCircledText(from: title)
    }
    
    private func setIdentityColors() {
        circledInitials.identityColors = identityColors
    }
    
    private func setSubtitle() {
        subtitleLabel.text = subtitle
    }
    
    private func setCircledImage() {
        guard let circledImage = circledImage else { return }
        circledInitials.showImage(fromImage: circledImage)
    }

}


extension OwnedIdentityView {
    
    @objc private func viewWasTapped() {
        UIView.animate(withDuration: 0.05, animations: { [weak self] in
            self?.backgroundColor = self?.appTheme.colorScheme.surfaceMedium
        }) { [weak self] (_) in
            self?.delegate?.ownedIdentityViewWasSelected()
        }
    }
    
    func clearBackgroundColor(animated: Bool) {
        guard animated else {
            backgroundColor = .clear
            return
        }
        UIView.animate(withDuration: 0.4) { [weak self] in
            self?.backgroundColor = .clear
        }
    }
    
}
