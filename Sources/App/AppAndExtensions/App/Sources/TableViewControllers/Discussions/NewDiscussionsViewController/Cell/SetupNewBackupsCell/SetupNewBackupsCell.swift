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
import ObvDesignSystem


protocol SetupNewBackupsCellDelegate: AnyObject {
    func userWantsToSetupNewBackups()
    func userWantsToDisplayBackupKey()
}

@available(iOS 16.0, *)
extension NewDiscussionsViewController {
    
    final class SetupNewBackupsCell: UICollectionViewListCell {
        
        private var item: NewDiscussionsViewController.SetupNewBackupsItem?
        private weak var delegate: SetupNewBackupsCellDelegate?

        func configure(item: NewDiscussionsViewController.SetupNewBackupsItem, delegate: SetupNewBackupsCellDelegate) {
            self.item = item
            self.delegate = delegate
            setNeedsUpdateConfiguration()
        }

        override func updateConfiguration(using state: UICellConfigurationState) {
            backgroundConfiguration = CustomBackgroundConfiguration.configuration()
            contentConfiguration = UIHostingConfiguration {
                SetupNewBackupsCellContentView(item: self.item ?? .newBackupsShouldBeSetup, actions: self)
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
                background.backgroundInsets = .init(top: 8, leading: 20, bottom: 8, trailing: 20)

                return background

            }
        }

    }
    
    
}

@available(iOS 16.0, *)
extension NewDiscussionsViewController.SetupNewBackupsCell: SetupNewBackupsCellContentViewActions {
    
    func userWantsToDisplayBackupKey() {
        delegate?.userWantsToDisplayBackupKey()
    }
    

    func userWantsToSetupNewBackups() {
        delegate?.userWantsToSetupNewBackups()
    }
    
}


// MARK: - SetupNewBackupsCellContentView

@available(iOS 16.0, *)
fileprivate protocol SetupNewBackupsCellContentViewActions {
    func userWantsToSetupNewBackups()
    func userWantsToDisplayBackupKey()
}

@available(iOS 16.0, *)
fileprivate struct SetupNewBackupsCellContentView: View {

    let item: NewDiscussionsViewController.SetupNewBackupsItem
    let actions: SetupNewBackupsCellContentViewActions
    
    private let trailingPadding: CGFloat = 8
    
    private var title: LocalizedStringKey {
        switch item {
        case .newBackupsShouldBeSetup:
            return "TIP_SETUP_NEW_BACKUPS_TITLE"
        case .rememberToWriteDownBackupKey:
            return "TIP_REMEMBER_TO_WRITE_DOWN_BACKUP_KEY_TITLE"
        }
    }
    
    private var message: LocalizedStringKey {
        switch item {
        case .newBackupsShouldBeSetup:
            return "TIP_SETUP_NEW_BACKUPS_MESSAGE"
        case .rememberToWriteDownBackupKey:
            return "TIP_REMEMBER_TO_WRITE_DOWN_BACKUP_KEY_MESSAGE"
        }
    }
    
    var body: some View {
        
        HStack(alignment: .firstTextBaseline) {
            ObvCloudBackupIconView(size: .small)
                .padding(.trailing, 8)
                .offset(y: -2)
            VStack(alignment: .leading) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 4)
                .padding(.trailing, trailingPadding)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                    .padding(.trailing, trailingPadding)

                Divider()
                    .padding(.bottom, 4)

                switch item {
                case .newBackupsShouldBeSetup:
                    Button {
                        actions.userWantsToSetupNewBackups()
                    } label: {
                        HStack {
                            Text("CONFIGURE_NEW_BACKUPS_NOW")
                                .fontWeight(.semibold)
                            Spacer(minLength: 0)
                        }
                    }
                case .rememberToWriteDownBackupKey:
                    Button {
                        actions.userWantsToDisplayBackupKey()
                    } label: {
                        HStack {
                            Text("SHOW_BACKUP_KEY_NOW")
                                .fontWeight(.semibold)
                            Spacer(minLength: 0)
                        }
                    }
                }

            }
        }
        .padding(.leading)
        .padding(.vertical)
        
    }
    
}



// MARK: - Previews

private struct ActionsForPreviews: SetupNewBackupsCellContentViewActions {
    func userWantsToDisplayBackupKey() {}
    func userWantsToSetupNewBackups() {}
}

@available(iOS 16.0, *)
#Preview("Setup") {
    SetupNewBackupsCellContentView(item: .newBackupsShouldBeSetup, actions: ActionsForPreviews())
}

@available(iOS 16.0, *)
#Preview("Write key") {
    SetupNewBackupsCellContentView(item: .rememberToWriteDownBackupKey, actions: ActionsForPreviews())
}
