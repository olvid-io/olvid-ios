/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import CloudKit
import ObvSystemIcon
import ObvDesignSystem


protocol ChooseBackupFileViewActionsProtocol: AnyObject {
    func userWantsToRestoreBackupFromFile() async -> [NewBackupInfo]
    func userWantsToRestoreBackupFromICloud() async throws -> [NewBackupInfo]
    func userWantsToProceedWithBackup(encryptedBackup: Data) async
}



struct ChooseBackupFileView: View, NewBackupFileDropViewActionsDelegate {
    
    let actions: ChooseBackupFileViewActionsProtocol
    
    @State private var backupInfos = [NewBackupInfo]()
    @State private var alertType: AlertType? = nil
    @State private var isAlertPresented: Bool = false
    @State private var selectedBackup: NewBackupInfo? = nil
    @State private var isPerformingCloudFetch = false

    private enum AlertType {
        case icloudAccountStatusIsNotAvailable
        case cloudKitError(ckError: CKError)
        case otherCloudError(error: NSError)
    }
    
    enum ObvError: Error {
        case icloudAccountStatusIsNotAvailable
        case cloudKitError(ckError: CKError)
        case otherCloudError(error: NSError)
    }

    private func userWantsToRestoreBackupFromFile() {
        Task {
            let newBackupInfos = await actions.userWantsToRestoreBackupFromFile()
            await addNewBackupInfos(newBackupInfos)
        }
    }

    @MainActor
    private func userWantsToRestoreBackupFromICloud() async {
        isPerformingCloudFetch = true
        defer { isPerformingCloudFetch = false }
        do {
            let newBackupInfos = try await actions.userWantsToRestoreBackupFromICloud()
            await addNewBackupInfos(newBackupInfos)
        } catch {
            let obvError = (error as? ObvError) ?? ObvError.otherCloudError(error: error as NSError)
            switch obvError {
            case .icloudAccountStatusIsNotAvailable:
                alertType = .icloudAccountStatusIsNotAvailable
            case .cloudKitError(let ckError):
                alertType = .cloudKitError(ckError: ckError)
            case .otherCloudError(let error):
                alertType = .otherCloudError(error: error)
            }
            isAlertPresented = true
        }
    }

    
    private func userWantsToProceedWithBackup(url: URL) {
        guard let encryptedBackupData = try? Data(contentsOf: url) else { return }
        Task { await actions.userWantsToProceedWithBackup(encryptedBackup: encryptedBackupData) }
    }
    
    
    func userDroppedBackupInfos(_ backupInfos: [NewBackupInfo]) -> Bool {
        Task { await addNewBackupInfos(backupInfos) }
        return true
    }

    
    @MainActor
    private func addNewBackupInfos(_ newBackupInfos: [NewBackupInfo]) async {
        let mergedBackupInfos = Set(self.backupInfos).union(Set(newBackupInfos))
        withAnimation {
            self.backupInfos = Array(mergedBackupInfos)
            self.backupInfos.sort { b1, b2 in
                if let d1 = b1.creationDate, let d2 = b2.creationDate {
                    return d1 > d2
                }
                return b1.fileUrl.lastPathComponent > b2.fileUrl.lastPathComponent
            }
        }
    }

    
    private var alertTitle: LocalizedStringKey {
        switch alertType {
        case .icloudAccountStatusIsNotAvailable:
            return "Sign in to iCloud"
        case .cloudKitError:
            return "iCloud error"
        case .otherCloudError:
            return "ERROR"
        case .none:
            return ""
        }
    }
    
    private var alertMessage: LocalizedStringKey {
        switch alertType {
        case .icloudAccountStatusIsNotAvailable:
            return "Please sign in to your iCloud account. On the Home screen, launch Settings, tap iCloud, and enter your Apple ID. Turn iCloud Drive on."
        case .cloudKitError(ckError: let ckError):
            return LocalizedStringKey(stringLiteral: ckError.localizedDescription)
        case .otherCloudError(error: let error):
            return LocalizedStringKey(stringLiteral: error.localizedDescription)
        case .none:
            return ""
        }
    }
    
    
    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    
                    ObvHeaderView(
                        title: "CHOOSE_YOUR_BACKUP_FILE_ONBOARDING_TITLE".localizedInThisBundle,
                        subtitle: nil)
                    
                    HStack {
                        OnboardingSpecificBlueButton("ONBOARDING_BUTTON_CHOOSE_BACKUP_FILE_FROM_FILES",
                                                     systemIcon: .folderFill,
                                                     action: userWantsToRestoreBackupFromFile)
                        OnboardingSpecificBlueButton("ONBOARDING_BUTTON_CHOOSE_BACKUP_FILE_FROM_ICLOUD",
                                                     systemIcon: .icloud(.fill),
                                                     action: { Task { await userWantsToRestoreBackupFromICloud() } })
                        .disabled(isPerformingCloudFetch)
                        .overlay {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                                .opacity(isPerformingCloudFetch ? 1.0 : 0.0)
                        }
                    }.padding()
                    
                    if #available(iOS 16, *), UIDevice.current.userInterfaceIdiom != .phone {
                        NewBackupFileDropView(actions: self)
                            .padding(.horizontal)
                    }
                    
                    if !backupInfos.isEmpty {
                        VStack {
                            Divider()
                                .padding(.vertical)
                            VStack {
                                HStack {
                                    Text("ONBOARDING_WHICH_BACKUP_DO_YOU_WANT_TO_RESTORE")
                                        .font(.headline)
                                    Spacer()
                                }
                                NewBackupInfoListView(model: backupInfos,
                                                      selectedBackup: $selectedBackup)
                            }
                            .padding(.trailing)
                        }
                        .padding(.leading)
                    }
                    
                    
                }
            }
            
            Spacer()
            
            ValidateButton(action: {
                guard let selectedBackup else { return }
                userWantsToProceedWithBackup(url: selectedBackup.fileUrl)
            })
            .disabled(selectedBackup == nil)
            .padding()
            
        }.alert(alertTitle,
                isPresented: $isAlertPresented,
                presenting: alertType)
        { details in
        } message: { details in
            Text(alertMessage)
        }
    }
}


// MARK: - OnboardingSpecificBlueButton

struct OnboardingSpecificBlueButton: View {

    private let key: LocalizedStringKey
    private let systemIcon: SystemIcon
    private let action: () -> Void

    @Environment(\.isEnabled) var isEnabled

    init(_ key: LocalizedStringKey, systemIcon: SystemIcon, action: @escaping () -> Void) {
        self.key = key
        self.systemIcon = systemIcon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(key, systemIcon: systemIcon)
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.vertical)
        }
        .frame(maxWidth: .infinity) // So that two side-by-side buttons have the same size
        .background(Color.blue01)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }

}


// MARK: - Internal validate button

private struct ValidateButton: View {

    let action: () -> Void
    
    @Environment(\.isEnabled) var isEnabled
    
    var body: some View {
        Button(action: action) {
            Label("VALIDATE", systemIcon: .checkmarkCircleFill)
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.vertical)
                .frame(maxWidth: .infinity)
        }
        .background(Color.blue01)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.0)
    }
    
}

// MARK: - NewBackupInfoListView and Cell

private struct NewBackupInfoListView: View {
    
    let model: [NewBackupInfo]
    @Binding var selectedBackup: NewBackupInfo?
    
    var body: some View {
        ForEach(model) { backupInfo in
            NewBackupInfoListViewCell(
                model: backupInfo, 
                showAsSelectable: true,
                selectedBackup: $selectedBackup)
        }
        .onAppear(perform: {
            // If there is only one backup in the list, select it immediately
            if model.count == 1, let onlyBackup = model.first {
                selectedBackup = onlyBackup
            }
        })
    }
    
}


private struct NewBackupInfoListViewCell: View {
    
    let model: NewBackupInfo
    let showAsSelectable: Bool
    @Binding var selectedBackup: NewBackupInfo?
    
    private let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.timeStyle = .short
        df.dateStyle = .short
        return df
    }()
    
    var body: some View {
        HStack(alignment: .center) {
            
            if showAsSelectable {
                Image(systemIcon: model == selectedBackup ? .checkmarkCircleFill : .circle)
                    .font(Font.system(size: 24, weight: .regular, design: .default))
                    .foregroundColor(model == selectedBackup ? Color.green : Color.gray)
            }
            
            VStack(alignment: .leading) {
                if let deviceName = model.deviceName {
                    Text(deviceName)
                        .font(.system(.headline, design: .rounded))
                }
                if let formattedDate = model.creationDate?.relativeFormatted {
                    Text(formattedDate)
                        .font(.system(.callout))
                } else {
                    Text(model.fileUrl.lastPathComponent)
                        .font(.system(.footnote, design: .monospaced))
                }
            }
            
            Spacer()

        }
        .padding(.vertical, 6.0)
        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
        .onTapGesture {
            selectedBackup = model
        }
    }
    
}


// MARK: - BackupFileDropView


protocol NewBackupFileDropViewActionsDelegate {
    /// Returns `true` if the drop operation was successful; otherwise, return `false`.
    func userDroppedBackupInfos(_ backupInfos: [NewBackupInfo]) -> Bool
}


@available(iOS 16.0, *)
fileprivate struct NewBackupFileDropView: View {
    
    let actions: NewBackupFileDropViewActionsDelegate

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [8]))
                .frame(maxHeight: .infinity, alignment: .center)
            Label("ONBOARDING_DROP_A_BACKUP_FILE_HERE", systemIcon: .squareAndArrowDownOnSquare)
                .font(.body)
                .padding(.vertical, 64)
        }
        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
        .dropDestination(for: NewBackupInfo.self) { items, location in
            return actions.userDroppedBackupInfos(items)
        }
    }
    
}




struct ChooseBackupFileView_Previews: PreviewProvider {
    
    private final class ActionsForPreviews: ChooseBackupFileViewActionsProtocol {

        func userWantsToRestoreBackupFromFile() async -> [NewBackupInfo] {
            let backupInfosForPreviews: [NewBackupInfo] = [
                .init(fileUrl: URL(fileURLWithPath: "Olvid backup 2023-09-05 16-13-27.olvidbackup"),
                      deviceName: nil,
                      creationDate: nil),
                .init(fileUrl: URL(fileURLWithPath: "Olvid backup 2023-09-05 16-11-26.olvidbackup"),
                      deviceName: nil,
                      creationDate: nil),
            ]
            return backupInfosForPreviews
        }
        
        func userWantsToRestoreBackupFromICloud() async throws -> [NewBackupInfo] {
            try await Task.sleep(seconds: 2) // Simulate cloud fetch
            let backupInfosForPreviews: [NewBackupInfo] = [
                .init(fileUrl: URL(fileURLWithPath: "Olvid backup from iCloud"),
                      deviceName: "iPhone",
                      creationDate: .init(timeIntervalSince1970: 1_700_000_000)),
                .init(fileUrl: URL(fileURLWithPath: "Another Olvid backup from iCloud"),
                      deviceName: "iPhone",
                      creationDate: .init(timeIntervalSince1970: 1_600_000_000)),
            ]
            return backupInfosForPreviews
        }
        
        func userDroppedBackupInfos(_ backupInfos: [NewBackupInfo]) -> Bool { return false }
        func userWantsToProceedWithBackup(encryptedBackup: Data) async {}
    }
    
    
    private final class ThrowingActionsForPreviews: ChooseBackupFileViewActionsProtocol {

        func userWantsToRestoreBackupFromFile() async -> [NewBackupInfo] {
            return []
        }
        
        func userWantsToRestoreBackupFromICloud() async throws -> [NewBackupInfo] {
            throw ChooseBackupFileView.ObvError.icloudAccountStatusIsNotAvailable
        }
        
        func userDroppedBackupInfos(_ backupInfos: [NewBackupInfo]) -> Bool { return false }
        func userWantsToProceedWithBackup(encryptedBackup: Data) async {}

    }
    
    private static let actions = ActionsForPreviews()
    private static let throwingActions = ThrowingActionsForPreviews()

    private static let backupInfosForPreviews: [NewBackupInfo] = [
        .init(fileUrl: URL(fileURLWithPath: "Olvid backup 2023-09-05 16-13-27.olvidbackup"),
              deviceName: nil,
              creationDate: nil),
        .init(fileUrl: URL(fileURLWithPath: "Olvid backup 2023-09-05 16-11-26.olvidbackup"),
              deviceName: nil,
              creationDate: nil),
    ]
    
    static var previews: some View {
        ChooseBackupFileView(actions: actions)
        ChooseBackupFileView(actions: throwingActions)
    }
    
}



