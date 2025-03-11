/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

@available(iOS 16.0, *)
extension NewDiscussionsViewController {
    
    final class ProgressCell: UICollectionViewListCell {
        
        private var progress: AppCoordinatorsQueueMonitor.CoordinatorsOperationsProgress?

        func configure(progress: AppCoordinatorsQueueMonitor.CoordinatorsOperationsProgress) {
            self.progress = progress
            setNeedsUpdateConfiguration()
        }

        override func updateConfiguration(using state: UICellConfigurationState) {
            guard let progress else { assertionFailure(); contentConfiguration = defaultContentConfiguration(); return; }
            backgroundConfiguration = CustomBackgroundConfiguration.configuration()
            contentConfiguration = UIHostingConfiguration {
                DiscussionsListProgressCellContentView(progress: progress)
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


// MARK: - DiscussionsListProgressCellContentView

@available(iOS 16.0, *)
fileprivate struct DiscussionsListProgressCellContentView: View {
    
    @ObservedObject var progress: AppCoordinatorsQueueMonitor.CoordinatorsOperationsProgress

    var body: some View {
        VStack(alignment: .leading) {
            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(LinearProgressViewStyle())
                //.labelsHidden()
            Text("Please hold on, we're working hard in the background to get everything ready for you!")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }.padding()
    }
    
}
