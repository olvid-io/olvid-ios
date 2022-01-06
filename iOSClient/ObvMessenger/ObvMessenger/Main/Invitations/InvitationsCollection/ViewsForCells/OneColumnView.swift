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

class OneColumnView: UIView {

    static let nibName = "OneColumnView"
    
    // Views

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var listLabel: UILabel!

}

// MARK: - awakeFromNib

extension OneColumnView {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        translatesAutoresizingMaskIntoConstraints = false
        configureAttributes()
    }
    
    
    private func configureAttributes() {
        titleLabel.textColor = AppTheme.shared.colorScheme.label
        listLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
    }
    
}


// MARK: - API

extension OneColumnView {
    
    func setTitle(with title: String) {
        titleLabel.text = title
    }
    
    
    func setList(with list: [String]) {
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
        listLabel.text = s
    }
}
