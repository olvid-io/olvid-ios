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

class TwoColumnsView: UIView {

    static let nibName = "TwoColumnsView"

    // Views
    
    @IBOutlet weak var titleLeft: UILabel!
    @IBOutlet weak var titleRight: UILabel!
    @IBOutlet weak var listLeft: UILabel!
    @IBOutlet weak var listRight: UILabel!
    
}


// MARK: - awakeFromNib

extension TwoColumnsView {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        translatesAutoresizingMaskIntoConstraints = false
        configureAttributes()
    }

    
    private func configureAttributes() {
        titleLeft.textColor = AppTheme.shared.colorScheme.label
        titleRight.textColor = AppTheme.shared.colorScheme.label
        listLeft.textColor = AppTheme.shared.colorScheme.secondaryLabel
        listRight.textColor = AppTheme.shared.colorScheme.secondaryLabel
    }
    
}


// MARK: - API

extension TwoColumnsView {
    
    func setLeftTile(with title: String) {
        titleLeft.text = title
    }

    func setRightTile(with title: String) {
        titleRight.text = title
    }

    func setLeftList(with list: [String]) {
        var s = ""
        for (index, item) in list.enumerated() {
            s += "✓ \(item)"
            if index != list.count-1 {
                s += "\n"
            }
        }
        if s == "" {
            s = CommonString.Word.None
        }
        listLeft.text = s
    }

    func setRightList(with list: [String]) {
        var s = ""
        for (index, item) in list.enumerated() {
            s += "∙ \(item)"
            if index != list.count-1 {
                s += "\n"
            }
        }
        if s == "" {
            s = "None"
        }
        listRight.text = s
    }
}
