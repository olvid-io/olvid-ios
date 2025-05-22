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
import ObvSystemIcon
import ObvCrypto


protocol BackupKeyDisplayerViewActionsDelegate: AnyObject {
    @MainActor func userConfirmedWritingDownTheBackupKey(remindToSaveBackupKey: Bool)
}


public struct BackupKeyDisplayerView: View {
    
    let model: Model
    let actions: BackupKeyDisplayerViewActionsDelegate
    
    @State private var isDisabled = false
    @State private var isBackupSeedHidden = true
    
    private func confirmationButtonTapped() {
        isDisabled = true
        actions.userConfirmedWritingDownTheBackupKey(remindToSaveBackupKey: false)
    }
    
    private func confirmButRemindLaterButtonTapped() {
        isDisabled = true
        actions.userConfirmedWritingDownTheBackupKey(remindToSaveBackupKey: true)
    }
    
    public struct Model {
        var backupSeed: BackupSeed
        public init(backupSeed: BackupSeed) {
            self.backupSeed = backupSeed
        }
    }
    
    private struct IntroductionParagraph: View {
        var body: some View {
            HStack {
                Label {
                    Text("THIS_BACKUP_KEY_WILL_BE_REQUIRED")
                } icon: {
                    Image(systemIcon: .infoCircle)
                }
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }
    
    
    private struct BackupKeyInternalView: View {
        let backupSeed: BackupSeed
        @Binding var isBackupSeedHidden: Bool
        var body: some View {
            HStack {
                Spacer(minLength: 0)
                VStack {
                    BackupKeyView(kind: .fixedValue(backupSeed.description, isBackupSeedHidden: $isBackupSeedHidden))
                        .padding(.bottom, 4)
                }
                Spacer(minLength: 0)
            }
        }
    }
    
    
    private struct WroteDownMyKeyConfirmationButtonView: View {
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    Text("ITS_NOTED")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    
    private struct RemindLaterButtonView: View {
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    Text("REMIND_ME_LATER")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
    }

    
    private func copyButtonTapped() {
        UIPasteboard.general.string = model.backupSeed.description
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
    }

    
    public var body: some View {
        
        VStack {
            
            Form {
                
                Section {
                    VStack(alignment: .center) {
                        HStack {
                            Spacer(minLength: 0)
                            Image(systemIcon: .keyFill)
                                .rotationEffect(.degrees(45))
                                .font(.system(size: 60, weight: .semibold))
                                .foregroundStyle(.pink)
                            Spacer(minLength: 0)
                        }
                        Text("YOUR_KEY")
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.bottom)
                        Text("THIS_BACKUP_KEY_WILL_BE_REQUIRED")
                            .multilineTextAlignment(.center)
                            .font(.body)
                            .padding(.bottom)
                        Text("THIS_BACKUP_KEY_CAN_BE_FOUND_IN_SETTINGS")
                            .multilineTextAlignment(.center)
                            .font(.body)
                            .padding(.bottom)
                    }
                }
                
                Section {
                    
                    BackupKeyInternalView(backupSeed: model.backupSeed, isBackupSeedHidden: $isBackupSeedHidden)
                        .listRowSeparator(.hidden)
                        .listRowSpacing(0)
                    
                } footer: {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                copyButtonTapped()
                            } label: {
                                Label {Text("COPY") } icon: { Image(systemIcon: .docOnDoc) }
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .disabled(isBackupSeedHidden)
                        }
                        .padding(.bottom)

                    }
                }
                
            }
            
            VStack {
                WroteDownMyKeyConfirmationButtonView(action: confirmationButtonTapped)
                RemindLaterButtonView(action: confirmButRemindLaterButtonTapped)
            }
            .padding(.horizontal)
            .padding(.bottom)
            .disabled(isDisabled)
            .background(Color(UIColor.systemGroupedBackground))

        }
        .background(Color(UIColor.systemGroupedBackground))
        
    }
    
}















// MARK: - Previews

private final class ActionsForPreviews: BackupKeyDisplayerViewActionsDelegate {
    func userConfirmedWritingDownTheBackupKey(remindToSaveBackupKey: Bool) {}
}

#Preview {
    BackupKeyDisplayerView(model: BackupKeyDisplayerView.Model(backupSeed: BackupSeed("V9DYA8HLVFED456G8YYT2TPBR8D4ED07")!),
                           actions: ActionsForPreviews())
}
