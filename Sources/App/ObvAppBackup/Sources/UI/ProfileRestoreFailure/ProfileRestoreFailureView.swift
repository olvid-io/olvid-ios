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
import MessageUI
import ObvTypes
import ObvAppCoreConstants
import ObvDesignSystem



@MainActor
protocol ProfileRestoreFailureViewActionsProtocol: AnyObject {
    func userWantsToSendErrorByEmail(errorMessage: String) async
}


struct ProfileRestoreFailureView: View {

    let actions: ProfileRestoreFailureViewActionsProtocol
    let model: Model
    let canSendMail: Bool
    
    struct Model {
        let error: Error
    }
    

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
    
    
    private func userWantsToSendErrorByEmail() {
        Task { await actions.userWantsToSendErrorByEmail(errorMessage: Self.stringForError(model.error) ) }
    }
    
    
    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    
                    ObvHeaderView(
                        title: String(localizedInThisBundle: "PROFILE_RESTORATION_FAILED_TITLE"),
                        subtitle: String(localizedInThisBundle: "PROFILE_RESTORATION_FAILED_SUBTITLE"))
                    
                    Image(systemIcon: .xmarkCircleFill)
                        .font(.title)
                        .foregroundStyle(Color(UIColor.systemRed))
                        .padding(.vertical)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("PROFILE_RESTORATION_FAILED_BODY_\(ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage)")
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(.bottom, 4)
                            Text(verbatim: Self.stringForError(model.error))
                                .lineLimit(nil)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 4)
                            HStack {
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = Self.stringForError(model.error)
                                } label: {
                                    Text("COPY_ERROR_TO_PASTEBOARD")
                                }
                            }
                        }
                        Spacer()
                    }
                    
                    
                }.padding(.horizontal)
            }
            if canSendMail {
                InternalButton(String(localizedInThisBundle: "SEND_ERROR_BY_EMAIL"), action: userWantsToSendErrorByEmail)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
    }
    
}


// MARK: - Button used in this view only

private struct InternalButton: View {
    
    private let key: String
    private let action: () -> Void
    
    init(_ key: String, action: @escaping () -> Void) {
        self.key = key
        self.action = action
    }
        
    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                Label(
                    title: {
                        HStack {
                            Text(key)
                                .foregroundStyle(.white)
                                .padding(.vertical, 8)
                        }
                    },
                    icon: {
                        Image(systemIcon: .envelope)
                            .foregroundStyle(.white)
                    }
                )
                Spacer()
            }
        }
        .buttonStyle(.borderedProminent)
    }
    
}




// MARK: - Previews


private final class ActionsForPreviews: ProfileRestoreFailureViewActionsProtocol {
    
    func userWantsToSendErrorByEmail(errorMessage: String) async {
        // Nothing to test
    }

}


private enum ObvErrorForPreviews: Error {
    case someError
}


#Preview("Can send email") {
    ProfileRestoreFailureView(actions: ActionsForPreviews(), model: .init(error: ObvErrorForPreviews.someError), canSendMail: true)
}

#Preview("Cannot send email") {
    ProfileRestoreFailureView(actions: ActionsForPreviews(), model: .init(error: ObvErrorForPreviews.someError), canSendMail: false)
}
