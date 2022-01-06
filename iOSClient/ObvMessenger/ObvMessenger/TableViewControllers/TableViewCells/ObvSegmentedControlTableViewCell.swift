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

final class ObvSegmentedControlTableViewCell: UITableViewCell {

    static let nibName = "ObvSegmentedControlTableViewCell"
    static let identifier = "ObvSegmentedControlTableViewCell"

    weak var delegate: ObvSegmentedControlTableViewCellDelegate?
    
    @IBOutlet weak var segmentedControl: UISegmentedControl! {
        didSet {
            self.segmentedControl?.addTarget(self, action: #selector(segmentedControlValueChanged), for: .valueChanged)
        }
    }
 
    @objc private func segmentedControlValueChanged() {
        delegate?.segmentedControlValueChanged(toIndex: segmentedControl.selectedSegmentIndex)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.prepareForReuse()
    }
        
    override func prepareForReuse() {
        super.prepareForReuse()
        self.segmentedControl.removeAllSegments()
    }
}


protocol ObvSegmentedControlTableViewCellDelegate: AnyObject {
    
    func segmentedControlValueChanged(toIndex: Int)
    
}
