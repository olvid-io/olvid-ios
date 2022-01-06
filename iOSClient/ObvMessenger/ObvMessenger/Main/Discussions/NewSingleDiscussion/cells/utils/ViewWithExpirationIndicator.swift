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


@available(iOS 13.0, *)
protocol ViewWithExpirationIndicator: UIView {
    
    var expirationIndicator: ExpirationIndicatorView { get }
    var expirationIndicatorSide: ExpirationIndicatorView.Side { get }

}


@available(iOS 13.0, *)
extension ViewWithExpirationIndicator {
    
    func refreshCellCountdown() {
        expirationIndicator.refreshCellCountdown()
    }
    
    
    func configure(readingRequiresUserAction: Bool, readOnce: Bool, scheduledVisibilityDestructionDate: Date?, scheduledExistenceDestructionDate: Date?) {
        expirationIndicator.configure(readingRequiresUserAction: readingRequiresUserAction,
                                      readOnce: readOnce,
                                      scheduledVisibilityDestructionDate: scheduledVisibilityDestructionDate,
                                      scheduledExistenceDestructionDate: scheduledExistenceDestructionDate)
    }

    func hideExpirationIndicator() {
        expirationIndicator.hide()
    }
    
    
    
    func setupConstraintsForExpirationIndicator(gap: CGFloat) {
        switch expirationIndicatorSide {
        case .leading:
            let constraints = [
                expirationIndicator.trailingAnchor.constraint(equalTo: self.leadingAnchor, constant: -gap),
                expirationIndicator.topAnchor.constraint(equalTo: self.topAnchor),
            ]
            constraints.forEach { $0.priority -= 1 }
            NSLayoutConstraint.activate(constraints)
        case .trailing:
            let constraints = [
                expirationIndicator.leadingAnchor.constraint(equalTo: self.trailingAnchor, constant: gap),
                expirationIndicator.topAnchor.constraint(equalTo: self.topAnchor),
            ]
            constraints.forEach { $0.priority -= 1 }
            NSLayoutConstraint.activate(constraints)
        }

    }
    
}
