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
import MessageUI
import ObvTypes



protocol OwnedIdentityTransferFailureViewActionsProtocol: AnyObject {
    func userWantsToSendErrorByEmail(errorMessage: String) async
}


struct OwnedIdentityTransferFailureView: View {

    let actions: OwnedIdentityTransferFailureViewActionsProtocol
    let model: Model
    let canSendMail: Bool
    
    struct Model {
        let error: Error
    }
    

    private static func stringForError(_ error: Error) -> String {
        let fullOlvidVersion = ObvMessengerConstants.fullVersion
        let preciseModel = UIDevice.current.preciseModel
        let systemName = UIDevice.current.systemName
        let systemVersion = UIDevice.current.systemVersion
        let msg = [
            "Olvid version: \(fullOlvidVersion)",
            "Device model: \(preciseModel)",
            "System: \(systemName) \(systemVersion)",
            "Error messages:\n\(error.localizedDescription)",
        ]
        return msg.joined(separator: "\n")
    }
    
    
    private static func localizedStringKeyForErrorThrownByTransferProtocol(_ error: OwnedIdentityTransferError) -> LocalizedStringKey? {
        switch error {
        case .serverRequestFailed:
            return "OWNED_IDENTITY_TRANSFER_ERROR_SERVER_REQUEST_FAILED"
        case .tryingToTransferAnOwnedIdentityThatAlreadyExistsOnTargetDevice:
            return "OWNED_IDENTITY_TRANSFER_ERROR_TRYING_TO_TRANSFER_IDENTITY_THAT_ALREADY_EXISTS_ON_TARGET"
        case .couldNotGenerateObvChannelServerQueryMessageToSend,
                .couldNotDecodeSyncSnapshot,
                .decryptionFailed,
                .decodingFailed,
                .incorrectSAS,
                .connectionIdsDoNotMatch,
                .couldNotOpenCommitment,
                .couldNotComputeSeed:
            return nil
        }
    }

    
    private func userWantsToSendErrorByEmail() {
        Task { await actions.userWantsToSendErrorByEmail(errorMessage: Self.stringForError(model.error) ) }
    }
    
    
    private var localizedStringKeyForProtocolError: LocalizedStringKey? {
        guard let error = model.error as? OwnedIdentityTransferError else { return nil }
        return Self.localizedStringKeyForErrorThrownByTransferProtocol(error)
    }
    

    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    
                    NewOnboardingHeaderView(
                        title: "OWNED_IDENTITY_TRANSFER_FAILED_TITLE",
                        subtitle: "OWNED_IDENTITY_TRANSFER_FAILED_SUBTITLE")
                    
                    Image(systemIcon: .xmarkCircleFill)
                        .font(.title)
                        .foregroundStyle(Color(UIColor.systemRed))
                        .padding(.vertical)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            if let localizedStringKeyForProtocolError {
                                Text(localizedStringKeyForProtocolError)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .padding(.bottom, 4)
                            }
                            Text("OWNED_IDENTITY_TRANSFER_FAILED_BODY_\(ObvMessengerConstants.toEmailForSendingInitializationFailureErrorMessage)")
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(.bottom, 4)
                            if localizedStringKeyForProtocolError == nil {
                                Text(verbatim: Self.stringForError(model.error))
                                    .lineLimit(nil)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.bottom, 4)
                            }
                            HStack {
                                Spacer()
                                Button("COPY_ERROR_TO_PASTEBOARD") {
                                    UIPasteboard.general.string = Self.stringForError(model.error)
                                }
                            }
                        }
                        Spacer()
                    }
                    
                    
                }.padding(.horizontal)
            }
            if canSendMail {
                InternalButton("SEND_ERROR_BY_EMAIL", action: userWantsToSendErrorByEmail)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
    }
    
}


// MARK: - Button used in this view only

private struct InternalButton: View {
    
    private let key: LocalizedStringKey
    private let action: () -> Void
    @Environment(\.isEnabled) var isEnabled
    
    init(_ key: LocalizedStringKey, action: @escaping () -> Void) {
        self.key = key
        self.action = action
    }
        
    var body: some View {
        Button(action: action) {
            Label(
                title: {
                    Text(key)
                        .foregroundStyle(.white)
                        .padding(.vertical, 16)
                },
                icon: {
                    Image(systemIcon: .envelope)
                        .foregroundStyle(.white)
                }
            )
        }
        .frame(maxWidth: .infinity)
        .background(Color("Blue01"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
    
}



struct OwnedIdentityTransferFailureView_Previews: PreviewProvider {
    
    private final class ActionsForPreviews: OwnedIdentityTransferFailureViewActionsProtocol {
        func userWantsToSendErrorByEmail(errorMessage: String) async {}
    }

    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        
        OwnedIdentityTransferFailureView(actions: actions, model: .init(error: ObvError.errorForPreviews), canSendMail: true)
    }
    
    private enum ObvError: Error {
        case errorForPreviews
    }
    
}
