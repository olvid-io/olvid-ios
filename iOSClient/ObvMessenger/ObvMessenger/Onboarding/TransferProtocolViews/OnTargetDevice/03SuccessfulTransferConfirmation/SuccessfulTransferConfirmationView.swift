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
import ObvTypes


protocol SuccessfulTransferConfirmationViewActionsProtocol: AnyObject {
    func userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(transferredOwnedCryptoId: ObvCryptoId, userWantsToAddAnotherProfile: Bool) async
}



struct SuccessfulTransferConfirmationView: View {
    
    let actions: SuccessfulTransferConfirmationViewActionsProtocol
    let model: Model
    
    struct Model {
        let transferredOwnedCryptoId: ObvCryptoId
        let postTransferError: Error?
    }
    
    private func doneButtonTapped() {
        Task {
            await actions.userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(
                transferredOwnedCryptoId: model.transferredOwnedCryptoId,
                userWantsToAddAnotherProfile: false)
        }
    }
    
    private func addButtonTapped() {
        Task {
            await actions.userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(
                transferredOwnedCryptoId: model.transferredOwnedCryptoId,
                userWantsToAddAnotherProfile: true)
        }
    }
    
    
    private static func stringForError(_ error: Error) -> String {
        error.localizedDescription
    }

    
    var body: some View {
        ScrollView {
            VStack {
             
                NewOnboardingHeaderView(title: "PROFILE_ADDED_SUCCESSFULLY",
                                        subtitle: nil)
                
                
                LaptopcomputerAndIphoneView()
                    .padding(.top)

                // In case something went wrong after a successful snapshot restoratin at the engine level,
                // we show the error here.
                
                if let postTransferError = model.postTransferError {
                    HStack {
                        Label(
                            title: {
                                VStack(alignment: .leading) {
                                    Text("OWNED_IDENTITY_TRANSFER_KINDA_FAILED_TITLE")
                                        .font(.headline)
                                        .padding(.bottom, 4)
                                    Text("OWNED_IDENTITY_TRANSFER_KINDA_FAILED_BODY_\(ObvMessengerConstants.toEmailForSendingInitializationFailureErrorMessage)")
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .padding(.bottom, 4)
                                    Text(verbatim: Self.stringForError(postTransferError))
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 4)
                                    HStack {
                                        Spacer()
                                        Button("COPY_ERROR_TO_PASTEBOARD") {
                                            UIPasteboard.general.string = Self.stringForError(postTransferError)
                                        }
                                    }
                                }
                            },
                            icon: {
                                Image(systemIcon: .exclamationmarkCircle)
                                    .foregroundStyle(Color(UIColor.systemYellow))
                                    .padding(.trailing)
                            }
                        )
                        Spacer()
                    }
                    .padding(.top)
                }
                
                HStack {
                    Text("DO_YOU_HAVE_OTHER_PROFILES_TO_ADD")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                }.padding(.top)
                
                HStack {
                    InternalButton(style: .white, "ADD_ANOTHER_PROFILE", action: addButtonTapped)
                    InternalButton(style: .blue, "NO_OTHER_PROFILE_TO_ADD", action: doneButtonTapped)
                }.padding(.top)
                
                Spacer()
                
            }
            .padding(.horizontal)
        }
    }
}


// MARK: - Button used in this view only

private struct InternalButton: View {
    
    private let style: Style
    private let key: LocalizedStringKey
    private let action: () -> Void
    @Environment(\.isEnabled) var isEnabled
    
    enum Style {
        case blue
        case white
    }
    
    private var backgroundColor: Color {
        switch style {
        case .blue:
            return Color("Blue01")
        case .white:
            return Color(UIColor.systemBackground)
        }
    }
    
    
    private var textColor: Color {
        switch style {
        case .blue:
            return .white
        case .white:
            return Color(UIColor.label)
        }
    }
    
    private var borderOpacity: Double {
        switch style {
        case .blue:
            return 0.0
        case .white:
            return 1.0
        }
    }
    
    init(style: Style, _ key: LocalizedStringKey, action: @escaping () -> Void) {
        self.style = style
        self.key = key
        self.action = action
    }
        
    var body: some View {
        Button(action: action) {
            Text(key)
                .foregroundStyle(textColor)
                .padding(.horizontal, 26)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
        .overlay(content: {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.lightGray), lineWidth: 1)
                .opacity(borderOpacity)
        })
    }
    
}


private struct LaptopcomputerAndIphoneView: View {
    var body: some View {
        HStack {
            Spacer()
            Image(systemIcon: .laptopcomputerAndIphone)
                .font(.system(size: 80, weight: .regular))
                .foregroundStyle(.secondary)
                .overlay(alignment: .topTrailing) {
                    Image(systemIcon: .checkmarkCircleFill)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(Color(UIColor.systemGreen))
                        .background(.background, in: .circle.inset(by: -2))
                        .offset(y: -10)
                }
            Spacer()
        }
    }
}



// MARK: - Previews

struct SuccessfulTransferConfirmationView_Previews: PreviewProvider {
    
    private static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

    private final class ActionsForPreviews: SuccessfulTransferConfirmationViewActionsProtocol {
        func userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(transferredOwnedCryptoId: ObvCryptoId, userWantsToAddAnotherProfile: Bool) async {}
    }

    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        SuccessfulTransferConfirmationView(actions: actions, model: .init(transferredOwnedCryptoId: ownedCryptoId, postTransferError: ObvError.errorForPreviews))
    }
    
    
    fileprivate enum ObvError: Error {
        case errorForPreviews
    }
    
}

