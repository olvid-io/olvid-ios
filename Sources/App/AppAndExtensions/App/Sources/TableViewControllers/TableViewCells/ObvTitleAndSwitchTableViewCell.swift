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

final class ObvTitleAndSwitchTableViewCell: UITableViewCell {

    private let uiSwitch = UISwitch()
    
    var blockOnSwitchValueChanged: ((Bool) -> Void)?
    
    
    var title: String? {
        get { self.textLabel?.text }
        set {
            var config = self.defaultContentConfiguration()
            config.text = newValue
            self.contentConfiguration = config
        }
    }
    
    var switchIsOn: Bool {
        get { self.uiSwitch.isOn }
        set { self.uiSwitch.isOn = newValue }
    }
    
    func setSwitchOn(_ on: Bool, animated: Bool) {
        self.uiSwitch.setOn(on, animated: animated)
    }

    var isEnabled: Bool {
        get { self.uiSwitch.isEnabled }
        set { self.uiSwitch.isEnabled = newValue }
    }
    
    init(reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        setup()
    }
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        assertionFailure()
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    
    private func setup() {
        self.accessoryView = self.uiSwitch
        self.uiSwitch.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
        self.prepareForReuse()
    }
    
    
    override func prepareForReuse() {
        super.prepareForReuse()
        self.blockOnSwitchValueChanged = nil
        self.uiSwitch.isOn = false
        self.title = nil
    }
    
    @objc func switchValueChanged() {
        self.blockOnSwitchValueChanged?(self.uiSwitch.isOn)
    }
    
}
