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
import OlvidUtils

class SasAcceptedView: UIView, ObvErrorMaker {

    static let nibName = "SasAcceptedView"

    private let expectedSasLength = 4
    private let sasFont = UIFont.preferredFont(forTextStyle: .title2)
    
    static let errorDomain = "SasAcceptedView"

    @IBOutlet weak var ownSasTitleLabel: UILabel! { didSet { ownSasTitleLabel.textColor = AppTheme.shared.colorScheme.label } }
    @IBOutlet weak var contactSasTitleLabel: UILabel! { didSet { contactSasTitleLabel.textColor = AppTheme.shared.colorScheme.label }}
    
    @IBOutlet weak var ownSasLabel: UILabel! {
        didSet {
            ownSasLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
            ownSasLabel.font = sasFont
        }
    }
    @IBOutlet weak var contactSasLabel: UILabel! {
        didSet {
            contactSasLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
            contactSasLabel.font = sasFont
            contactSasLabel.text = "✓"
        }
    }
    
}

// MARK: - awakeFromNib, configuration and responding to external events

extension SasAcceptedView {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        translatesAutoresizingMaskIntoConstraints = false
    }

}

// MARK: - SAS related stuff

fileprivate extension String {
    
    func isValidSas(ofLength length: Int) -> Bool {
        guard self.count == length else { return false }
        return self.allSatisfy { $0.isValidSasCharacter() }
    }
    
}

fileprivate extension Character {
    
    func isValidSasCharacter() -> Bool {
        return self >= "0" && self <= "9"
    }
    
}

extension SasAcceptedView {
    
    func setOwnSas(ownSas: Data) throws {
        guard let sas = String(data: ownSas, encoding: .utf8) else { throw Self.makeError(message: "Could not turn SAS into string") }
        guard sas.isValidSas(ofLength: expectedSasLength) else { throw Self.makeError(message: "SAS is not valid") }
        ownSasLabel.text = sas
        
    }
    
}
