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


protocol NewDiscussionsViewControllerLocationCellDelegate: AnyObject {
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice()
}

@available(iOS 16.0, *)
extension NewDiscussionsViewController {
    
    final class LocationCell: UICollectionViewListCell {
        
        private var numberOfSentMessagesWithLocationContinuousSentFromCurrentOwnedDevice: Int = 0
        private weak var delegate: NewDiscussionsViewControllerLocationCellDelegate?

        func configure(numberOfSentMessagesWithLocationContinuousSentFromCurrentOwnedDevice: Int, delegate: NewDiscussionsViewControllerLocationCellDelegate) {
            self.numberOfSentMessagesWithLocationContinuousSentFromCurrentOwnedDevice = max(0, numberOfSentMessagesWithLocationContinuousSentFromCurrentOwnedDevice)
            self.delegate = delegate
            setNeedsUpdateConfiguration()
        }

        override func updateConfiguration(using state: UICellConfigurationState) {
            backgroundConfiguration = CustomBackgroundConfiguration.configuration()
            contentConfiguration = UIHostingConfiguration {
                DiscussionsListLocationCellContentView(numberOfSentMessagesWithLocationContinuousSentFromCurrentOwnedDevice: numberOfSentMessagesWithLocationContinuousSentFromCurrentOwnedDevice, actions: self)
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
extension NewDiscussionsViewController.LocationCell: DiscussionsListLocationCellContentViewActions {
    
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice() {
        delegate?.userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice()
    }
    
}


// MARK: - DiscussionsListLocationCellContentView

@available(iOS 16.0, *)
fileprivate protocol DiscussionsListLocationCellContentViewActions {
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice()
}

@available(iOS 16.0, *)
fileprivate struct DiscussionsListLocationCellContentView: View {

    let numberOfSentMessagesWithLocationContinuousSentFromCurrentOwnedDevice: Int
    let actions: DiscussionsListLocationCellContentViewActions
    
    private func stopSharingButtonTapped() {
        actions.userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice()
    }

    var body: some View {
        HStack {
            Label {
                Text("YOU_ARE_SHARING_YOUR_LOCATION_IN_\(numberOfSentMessagesWithLocationContinuousSentFromCurrentOwnedDevice)_MESSAGES")
                    .font(.headline)
            } icon: {
                Image(systemIcon: .locationCircle)
                    .foregroundStyle(Color(UIColor.systemBlue))
            }
            Spacer()
            Button("STOP_SHARING", role: .destructive, action: stopSharingButtonTapped)
                .buttonStyle(.bordered)
        }
        .padding()
    }
    
}



// MARK: - Previews

private struct ActionsForPreviews: DiscussionsListLocationCellContentViewActions {
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice() {}
}

@available(iOS 16.0, *)
#Preview {
    DiscussionsListLocationCellContentView(numberOfSentMessagesWithLocationContinuousSentFromCurrentOwnedDevice: 5, actions: ActionsForPreviews())
}
