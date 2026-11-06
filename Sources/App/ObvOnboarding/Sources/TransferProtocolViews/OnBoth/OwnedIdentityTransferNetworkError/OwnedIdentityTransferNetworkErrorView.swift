/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import MessageUI
import ObvAppCoreConstants
import ObvDesignSystem
import ObvSystemIcon


/// Shown (on the source or the target device) when the owned identity transfer protocol fails with a ``OwnedIdentityTransferError.serverRequestFailed`` error,
/// i.e., when the device could not reach the transfer server. This is almost always a local network issue, so this screen gives actionable advice
/// instead of the generic transfer failure screen. The user can still send the technical error by email, as the generic screen allows.
struct OwnedIdentityTransferNetworkErrorView: View {

    let model: Model

    struct Model {
        let error: Error
    }

    @State private var isEmailComposerViewPresented = false
    @State private var hudCategory: HUDView.Category? = nil


    private static func stringForError(_ error: Error) -> String {
        let fullOlvidVersion = ObvAppCoreConstants.fullVersion
        let preciseModel = UIDevice.current.preciseModel
        let systemName = UIDevice.current.name
        let systemVersion = UIDevice.current.systemVersion
        let msg = [
            "Olvid version: \(fullOlvidVersion)",
            "Device model: \(preciseModel)",
            "System: \(systemName) \(systemVersion)",
            "Error messages:\n\(error.localizedDescription)",
        ]
        return msg.joined(separator: "\n")
    }


    private var emailModel: ObvEmailComposerView.Model {
        .init(subject: String(localizedInThisBundle: "MAIL_SUBJECT_COULD_NOT_TRANSFER_PROFILE_ERROR"),
              toRecipients: [ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage],
              messageBody: String.localizedStringWithFormat(String(localizedInThisBundle: "MAIL_BODY_COULD_NOT_TRANSFER_PROFILE_ERROR$@"), Self.stringForError(model.error)))
    }


    private func sendErrorByEmailButtonTapped() {
        isEmailComposerViewPresented = true
    }


    var body: some View {
        ZStack {
            VStack {
                ScrollView {
                    VStack {

                        ObvHeaderView(
                            title: "OWNED_IDENTITY_TRANSFER_NETWORK_ERROR_TITLE".localizedInThisBundle,
                            subtitle: "OWNED_IDENTITY_TRANSFER_NETWORK_ERROR_SUBTITLE".localizedInThisBundle)

                        Image(systemIcon: .networkSlash)
                            .font(.system(size: 56, weight: .regular))
                            .foregroundStyle(Color(UIColor.systemOrange))
                            .padding(.vertical)

                        HStack {
                            Text("OWNED_IDENTITY_TRANSFER_NETWORK_ERROR_BODY")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            AdviceRow(icon: .arrowClockwise, titleKey: "OWNED_IDENTITY_TRANSFER_NETWORK_ERROR_ADVICE_TRY_AGAIN")
                            AdviceRow(icon: .wifi, titleKey: "OWNED_IDENTITY_TRANSFER_NETWORK_ERROR_ADVICE_OTHER_NETWORK")
                            AdviceRow(icon: .shieldSlash, titleKey: "OWNED_IDENTITY_TRANSFER_NETWORK_ERROR_ADVICE_VPN")
                        }
                        .padding(.top)

                        HStack {
                            Text("OWNED_IDENTITY_TRANSFER_NETWORK_ERROR_ADMIN_FOOTNOTE")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top)

                        HStack {
                            Text("OWNED_IDENTITY_TRANSFER_NETWORK_ERROR_IF_PROBLEM_PERSISTS_\(ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 4)

                        if !ObvEmailComposerView.canSendEmail() {
                            HStack {
                                Spacer()
                                Button("COPY_ERROR_TO_PASTEBOARD".localizedInThisBundle) {
                                    UIPasteboard.general.string = Self.stringForError(model.error)
                                }
                            }
                            .padding(.top, 4)
                        }

                    }
                    .padding(.horizontal)
                }
                if ObvEmailComposerView.canSendEmail() {
                    OlvidButtonNew(action: sendErrorByEmailButtonTapped) {
                        Label("SEND_ERROR_BY_EMAIL", systemIcon: .envelope)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            if let hudCategory {
                HUDView(category: hudCategory)
                    .zIndex(1)
            }
        }
        .obvEmailComposerView(isPresented: $isEmailComposerViewPresented, model: emailModel, delegate: self)
    }

}


// MARK: - Implementing ObvEmailComposerViewDelegate

extension OwnedIdentityTransferNetworkErrorView: ObvEmailComposerViewDelegate {

    func emailComposerViewDidFinish(_ view: ObvEmailComposerView, result: Result<MFMailComposeResult, any Error>) {
        isEmailComposerViewPresented = false
        let hudCategoryToShow: HUDView.Category
        switch result {
        case .success(.cancelled):
            return
        case .success:
            hudCategoryToShow = .checkmark
        case .failure:
            hudCategoryToShow = .xmark
        }
        Task {
            // Let the mail composer sheet finish its dismissal animation before showing the HUD
            try? await Task.sleep(seconds: 0.5)
            hudCategory = hudCategoryToShow
            try? await Task.sleep(seconds: 1)
            hudCategory = nil
        }
    }

}


// MARK: - Advice row

private struct AdviceRow: View {

    let icon: SystemIcon
    let titleKey: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemIcon: icon)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            Text(titleKey)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

}



// MARK: - Previews

#if DEBUG

private enum ObvErrorForPreviews: Error {
    case someError
}

@MainActor
private let modelForPreviews: OwnedIdentityTransferNetworkErrorView.Model = .init(error: ObvErrorForPreviews.someError)

#Preview {
    OwnedIdentityTransferNetworkErrorView(model: modelForPreviews)
}

#endif
