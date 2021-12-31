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

protocol CellContainingHeaderView {
    
    var cellHeaderView: CellHeaderView! { get }
    
}

extension CellContainingHeaderView where Self: InvitationCollectionCell {
    
    var title: String {
        get { return cellHeaderView.title }
        set { cellHeaderView.title = newValue }
    }
    
    var subtitle: String {
        get { return cellHeaderView.subtitle }
        set { cellHeaderView.subtitle = newValue }
    }
    
    var details: String {
        get { return cellHeaderView.details }
        set { cellHeaderView.details = newValue }
    }
    
    var date: Date? {
        get { return cellHeaderView.date }
        set { cellHeaderView.date = newValue }
    }
    
    var identityColors: (background: UIColor, text: UIColor)? {
        get { return cellHeaderView.identityColors }
        set { cellHeaderView.identityColors = newValue }
    }
    
    func addChip(withText text: String) {
        cellHeaderView.addChip(withText: text)
    }
    
}
