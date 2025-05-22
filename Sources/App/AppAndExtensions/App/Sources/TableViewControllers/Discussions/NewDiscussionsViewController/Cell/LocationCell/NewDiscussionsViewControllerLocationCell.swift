/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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

import SwiftUI
import ObvAppCoreConstants
import ObvTypes


protocol NewDiscussionsViewControllerLocationCellDelegate: AnyObject {
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice()
    func userWantsToShowMapToConsultLocationSharedContinously(ownedCryptoId: ObvTypes.ObvCryptoId) async throws
}

@available(iOS 16.0, *)
extension NewDiscussionsViewController {
    
    final class LocationCell: UICollectionViewListCell {
        
        private weak var delegate: NewDiscussionsViewControllerLocationCellDelegate?
        private var viewModel: LocationsCellViewModel?
        
        func configure(viewModel: LocationsCellViewModel, delegate: NewDiscussionsViewControllerLocationCellDelegate) {
            self.viewModel = viewModel
            self.delegate = delegate
            setNeedsUpdateConfiguration()
        }
        
        override func updateConfiguration(using state: UICellConfigurationState) {
            backgroundConfiguration = CustomBackgroundConfiguration.configuration()
            contentConfiguration = UIHostingConfiguration {
                LocationsCellView(viewModel: viewModel, actions: self)
            }
        }
        
        
        private struct CustomBackgroundConfiguration {
            static func configuration() -> UIBackgroundConfiguration {

                var background = UIBackgroundConfiguration.clear()
                
                background.backgroundColor = .secondarySystemBackground
                if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
                    background.cornerRadius = 8
                } else {
                    background.cornerRadius = 12
                }
                background.backgroundInsets = .init(top: 8, leading: 16, bottom: 8, trailing: 16)

                return background

            }
        }

    }
    
    
}

@available(iOS 16.0, *)
extension NewDiscussionsViewController.LocationCell: LocationsCellViewActions {
    
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice() {
        delegate?.userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice()
    }
    
    
    func userWantsToShowMapToConsultLocationSharedContinously(ownedCryptoId: ObvTypes.ObvCryptoId) async throws {
        try await delegate?.userWantsToShowMapToConsultLocationSharedContinously(ownedCryptoId: ownedCryptoId)
    }
    
}
