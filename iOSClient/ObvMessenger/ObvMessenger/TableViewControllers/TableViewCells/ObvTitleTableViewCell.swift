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

import ObvUI
import UIKit

class ObvTitleTableViewCell: UITableViewCell, ObvTableViewCellWithActivityIndicator {

    static let nibName = "ObvTitleTableViewCell"
    static let identifier = "ObvTitleTableViewCell"

    // Views
    
    @IBOutlet weak var circlePlaceholder: UIView! { didSet { circlePlaceholder.backgroundColor = .clear } }
    @IBOutlet weak var titleLabel: UILabel! { didSet { titleLabel.textColor = AppTheme.shared.colorScheme.label } }
    @IBOutlet weak var activityIndicatorPlaceholder: UIView! { didSet { activityIndicatorPlaceholder.backgroundColor = .clear } }
    var activityIndicator: UIView?
    @IBOutlet weak var sideLabel: UILabel!
    
    // Vars
    
    var title: String = "" { didSet { setTitle(); setCircledText() } }
    var identityColors: (background: UIColor, text: UIColor)? { didSet { setIdentityColors() } }
    var sideTitle: String? { didSet { setSideTitle() } }
    
    // Subviews set in awakeFromNib
    
    var circledInitials: CircledInitials!

    override func prepareForReuse() {
        super.prepareForReuse()
        sideLabel.text = nil
        stopSpinner()
    }
    
}

// MARK: - awakeFromNib

extension ObvTitleTableViewCell {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        titleLabel.textColor = appTheme.colorScheme.label
        sideLabel.textColor = appTheme.colorScheme.secondaryLabel
        
        prepareForReuse()
        
        circledInitials = (Bundle.main.loadNibNamed(CircledInitials.nibName, owner: nil, options: nil)!.first as! CircledInitials)
        circlePlaceholder.addSubview(circledInitials)
        circlePlaceholder.pinAllSidesToSides(of: circledInitials)

    }
    
}


// MARK: - Setting labels and texts

extension ObvTitleTableViewCell {
    
    private func setTitle() {
        titleLabel.text = title
    }
    
    private func setCircledText() {
        circledInitials.showCircledText(from: title)
    }

    private func setIdentityColors() {
        circledInitials.identityColors = self.identityColors
    }
    
    private func setSideTitle() {
        sideLabel.text = self.sideTitle
    }
}
