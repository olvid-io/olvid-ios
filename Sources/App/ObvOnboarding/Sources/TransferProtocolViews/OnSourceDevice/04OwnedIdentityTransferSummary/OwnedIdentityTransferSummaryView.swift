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
import Contacts
import ObvTypes
import ObvCrypto
import ObvAppCoreConstants


protocol OwnedIdentityTransferSummaryViewActionsProtocol: AnyObject {
    func userDidCancelOwnedIdentityTransferProtocol() async
    func userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(enteredSAS: ObvOwnedIdentityTransferSas, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID) async throws
}



struct OwnedIdentityTransferSummaryView: View {
    
    let actions: OwnedIdentityTransferSummaryViewActionsProtocol
    let model: Model
    
    @State private var isInterfaceDisabled = false
    
    @State private var errorForAlert: Error?
    @State private var isAlertShown = false

    struct Model {
        let ownedCryptoId: ObvCryptoId
        let ownedDetails: CNContact
        let enteredSAS: ObvOwnedIdentityTransferSas
        let ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult
        let targetDeviceName: String
        let deviceToKeepActive: ObvOwnedDeviceDiscoveryResult.Device?
        let protocolInstanceUID: UID
        let isTransferRestricted: Bool
    }
    
    
    private var ownedIdentityName: String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        return formatter.string(from: model.ownedDetails.personNameComponents)
    }
    
    
    private var jobTitleAndOrganizationName: String? {
        let jobTitle = model.ownedDetails.jobTitle.mapToNilIfZeroLength()
        let organizationName = model.ownedDetails.organizationName.mapToNilIfZeroLength()
        switch (jobTitle, organizationName) {
        case (.none, .none):
            return nil
        case (.some(let jobTitle), .none):
            return jobTitle
        case (.none, .some(let organizationName)):
            return organizationName
        case (.some(let jobTitle), .some(let organizationName)):
            return [jobTitle, organizationName].joined(separator: "@")
        }
    }
    
    
    private var nameOfDeviceToKeepActive: String {
        if let device = model.deviceToKeepActive {
            return device.name ?? String(device.identifier.hexString().prefix(4))
        } else {
            return model.targetDeviceName
        }
    }
    
    
    private func cancelButtonTapped() {
        isInterfaceDisabled = true
        Task {
            await actions.userDidCancelOwnedIdentityTransferProtocol()
        }
    }
    
    static let fakeDeviceIdForNewDevice: Data = Data(repeating: 0, count: 1)
    
    private func proceedButtonTapped() {
        let deviceToKeepActive: UID?
        // The ChooseDeviceToKeepActiveView.fakeDeviceIdForNewDevice was used to give a fake identifier to the target device.
        // Setting the deviceToKeepActive to nil means "keep target device active".
        if let identifier = model.deviceToKeepActive?.identifier, identifier != Self.fakeDeviceIdForNewDevice {
            guard let uid = UID(uid: identifier) else { assertionFailure(); return }
            deviceToKeepActive = uid
        } else {
            deviceToKeepActive = nil
        }
        isInterfaceDisabled = true
        Task {
            do {
                try await actions.userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(
                    enteredSAS: model.enteredSAS,
                    deviceToKeepActive: deviceToKeepActive,
                    ownedCryptoId: model.ownedCryptoId,
                    protocolInstanceUID: model.protocolInstanceUID)
            } catch {
                // This is unlikely to happen (as this only occurs if we cannot post the protocol message).
                // If the protocol fails, this is not called, but a failure notification will be catched by the flow manager.
                // It will show the screen describing the error.
                errorForAlert = error
                isAlertShown = true
            }
        }
    }
    

    private var alertTitle: LocalizedStringKey {
        if let errorForAlert {
            return "COULD_NOT_PERFORM_OWNED_IDENTITY_TRANSFER_ALERT_\(ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage)_\((errorForAlert as NSError).description)"
        } else {
            return "COULD_NOT_PERFORM_OWNED_IDENTITY_TRANSFER_ALERT_\(ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage)"
        }
    }
    
    
    var body: some View {
        
        VStack {
            
            ScrollView {
                VStack {
                    
                    NewOnboardingHeaderView(
                        title: "OWNED_IDENTITY_SUMMARY_VIEW_TITLE",
                        subtitle: "OWNED_IDENTITY_SUMMARY_VIEW_SUBTITLE")
                    
                    Divider()
                        .padding(.top)
                    
                    HStack(alignment: .top) {
                        
                        HStack {
                            
                            Label(
                                title: {
                                    VStack(alignment: .leading) {
                                        Text("PROFILE_YOU_ARE_ABOUT_TO_ADD_TO_NEW_DEVICE")
                                            .font(.headline)
                                        Text(verbatim: ownedIdentityName)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        if let jobTitleAndOrganizationName {
                                            Text(verbatim: jobTitleAndOrganizationName)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                },
                                icon: {
                                    Image(systemIcon: .person)
                                }
                            )
                            
                            Spacer()
                        }.padding(.top)
                        
                        
                        HStack {
                            
                            Label(
                                title: {
                                    VStack(alignment: .leading) {
                                        Text("WILL_BE_ADDED_TO_THIS_DEVICE")
                                            .font(.headline)
                                        Text(verbatim: model.targetDeviceName)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                },
                                icon: {
                                    Image(systemIcon: .laptopcomputerAndIphone)
                                }
                            )
                            
                            Spacer()
                        }.padding(.top)
                        
                    }
                    
                    Divider()
                        .padding(.top)
                    
                    if !model.ownedDeviceDiscoveryResult.isMultidevice {
                        
                        HStack {
                            
                            Label(
                                title: {
                                    VStack(alignment: .leading) {
                                        Text("THE_FOLLOWING_DEVICE_WILL_REMAIN_ACTIVE")
                                            .font(.headline)
                                        Text(verbatim: nameOfDeviceToKeepActive)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text("YOUR_OTHER_DEVICES_WILL_BE_DEACTIVATED_EXPLANATION")
                                            .foregroundStyle(.secondary)
                                            .padding(.top)
                                    }
                                },
                                icon: {
                                    Image(systemIcon: .poweroff)
                                }
                            )
                            
                            Spacer()
                        }.padding(.top)

                        Divider()
                            .padding(.top)
                        
                    }
                    
                    if model.isTransferRestricted {
                        HStack {
                            Label("TRANSFER_RESTRICTED_REMINDER", systemIcon: .exclamationmarkCircle)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }.padding(.top)
                    }
                    
                    if isInterfaceDisabled {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }.padding(.top)
                    }
                    
                    
                }.padding(.horizontal)
            }
            
            HStack {
                InternalButton("Cancel", style: .red, action: cancelButtonTapped)
                InternalButton("VALIDATE", style: .blue, action: proceedButtonTapped)
            }.padding()
            
        }
        .disabled(isInterfaceDisabled)
        .alert(alertTitle, isPresented: $isAlertShown) {
            Button("OK".localizedInThisBundle, role: .cancel) { }
            if let errorForAlert {
                Button("COPY_ERROR".localizedInThisBundle, role: .none) { UIPasteboard.general.string = (errorForAlert as NSError).description }
            }
        }

    }
}


// MARK: - Button used in this view only

private struct InternalButton: View {
    
    enum Style {
        case red
        case blue
    }
    
    private var backgroundColor: Color {
        switch style {
        case .red:
            return Color(UIColor.systemRed)
        case .blue:
            return Color.blue01
        }
    }
    
    private let key: LocalizedStringKey
    private let action: () -> Void
    private let style: Style
    @Environment(\.isEnabled) var isEnabled
    
    init(_ key: LocalizedStringKey, style: Style, action: @escaping () -> Void) {
        self.key = key
        self.action = action
        self.style = style
    }
        
    var body: some View {
        Button(action: action) {
            Text(key)
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
    
}


extension CNContact {
    
    var personNameComponents: PersonNameComponents {
        .init(namePrefix: self.namePrefix,
              givenName: self.givenName,
              middleName: self.middleName,
              familyName: self.familyName,
              nameSuffix: self.nameSuffix,
              nickname: self.nickname,
              phoneticRepresentation: nil)
    }
    
}




// MARK: - Previews

struct OwnedIdentityTransferSummaryView_Previews: PreviewProvider {
    
    private static let ownedDetails: CNContact = {
        let contact = CNMutableContact()
        contact.givenName = "Steve"
        contact.familyName = "Jobs"
        contact.jobTitle = "CEO"
        contact.organizationName = "Apple"
        contact.nickname = "The boss"
        return contact
    }()
    
    private static let devices: Set<ObvOwnedDeviceDiscoveryResult.Device> = Set([
        .init(identifier: UID(uid: Data(repeating: 0x01, count: UID.length))!.raw,
              expirationDate: Date(timeIntervalSinceNow: 400),
              latestRegistrationDate: Date(timeIntervalSinceNow: -200),
              name: "iPad Pro"),
        .init(identifier: UID.zero.raw,
              expirationDate: Date(timeIntervalSinceNow: 500),
              latestRegistrationDate: Date(timeIntervalSinceNow: -100),
              name: "iPhone 15"),
    ])

    private static let ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult = .init(
        devices: devices,
        isMultidevice: false)

    private static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

    private static let enteredSAS = try! ObvOwnedIdentityTransferSas(fullSas: "12345678".data(using: .utf8)!)

    private final class ActionsForPreviews: OwnedIdentityTransferSummaryViewActionsProtocol {
        func userDidCancelOwnedIdentityTransferProtocol() async {}
        func userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(enteredSAS: ObvOwnedIdentityTransferSas, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID) async throws {}
    }
    
    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        OwnedIdentityTransferSummaryView(actions: actions,
                                         model: .init(ownedCryptoId: ownedCryptoId,
                                                      ownedDetails: ownedDetails,
                                                      enteredSAS: enteredSAS,
                                                      ownedDeviceDiscoveryResult: ownedDeviceDiscoveryResult,
                                                      targetDeviceName: "iPhone 13",
                                                      deviceToKeepActive: devices.first,
                                                      protocolInstanceUID: UID.zero,
                                                      isTransferRestricted: true))
        
    }
    
}
