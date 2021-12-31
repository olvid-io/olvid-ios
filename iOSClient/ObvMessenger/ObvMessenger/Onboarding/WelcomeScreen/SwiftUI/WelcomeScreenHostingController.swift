/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

import UIKit
import SwiftUI


@available(iOS 13, *)
protocol WelcomeScreenHostingControllerDelegate: AnyObject {
    
    func userWantsToContinueAsNewUser()
    func userWantsToRestoreBackup()
    func userWantsWantsToScanQRCode()
    func userWantsToClearExternalOlvidURL()

}


protocol CanShowInformationAboutExternalOlvidURL {
    func showInformationAboutOlvidURL(_: OlvidURL?)
}

@available(iOS 13, *)
final class WelcomeScreenHostingController: UIHostingController<WelcomeScreenHostingView>, WelcomeScreenHostingViewStoreDelegate, CanShowInformationAboutExternalOlvidURL {
    
    fileprivate let store: WelcomeScreenHostingViewStore
    weak var delegate: WelcomeScreenHostingControllerDelegate?
    
    init(delegate: WelcomeScreenHostingControllerDelegate) {
        let store = WelcomeScreenHostingViewStore()
        self.store = store
        let view = WelcomeScreenHostingView(store: store)
        super.init(rootView: view)
        self.delegate = delegate
        store.delegate = self
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // WelcomeScreenHostingViewStoreDelegate
    
    func userWantsToContinueAsNewUser() {
        delegate?.userWantsToContinueAsNewUser()
    }
    
    func userWantsToRestoreBackup() {
        delegate?.userWantsToRestoreBackup()
    }

    func userWantsWantsToScanQRCode() {
        delegate?.userWantsWantsToScanQRCode()
    }
    
    func userWantsToClearExternalOlvidURL() {
        delegate?.userWantsToClearExternalOlvidURL()
    }
    
    // CanShowInformationAboutExternalOlvidURL
    
    func showInformationAboutOlvidURL(_ externalOlvidURL: OlvidURL?) {
        withAnimation {
            store.externalOlvidURL = externalOlvidURL
        }
    }
    
}


protocol WelcomeScreenHostingViewStoreDelegate: AnyObject {
    
    func userWantsToContinueAsNewUser()
    func userWantsToRestoreBackup()
    func userWantsWantsToScanQRCode()
    func userWantsToClearExternalOlvidURL()

}


@available(iOS 13, *)
final class WelcomeScreenHostingViewStore: ObservableObject {
    
    weak var delegate: WelcomeScreenHostingViewStoreDelegate?
    @Published var externalOlvidURL: OlvidURL?
    
    func userWantsToContinueAsNewUser() {
        delegate?.userWantsToContinueAsNewUser()
    }

    func userWantsToRestoreBackup() {
        delegate?.userWantsToRestoreBackup()
    }

    fileprivate func userWantsWantsToScanQRCode() {
        delegate?.userWantsWantsToScanQRCode()
    }
    
    fileprivate func userWantsToClearExternalOlvidURL() {
        delegate?.userWantsToClearExternalOlvidURL()
    }

}


@available(iOS 13, *)
struct WelcomeScreenHostingView: View {
    
    @ObservedObject var store: WelcomeScreenHostingViewStore
    @Environment(\.colorScheme) var colorScheme
    
    private var textForExternalOlvidURL: Text? {
        guard let olvidURL = store.externalOlvidURL else { return nil }
        switch olvidURL.category {
        case .invitation(urlIdentity: let urlIdentity):
            return Text("WILL_INVITE_\(urlIdentity.fullDisplayName)_AFTER_ONBOARDING")
        case .mutualScan(mutualScanURL: _):
            return nil
        case .configuration(serverAndAPIKey: let serverAndAPIKey, betaConfiguration: _, keycloakConfig: _):
            guard serverAndAPIKey != nil else { return nil }
            return Text("WILL_PROCESS_API_KEY_AFTER_ONBOARDING")
        case .openIdRedirect:
            return nil
        }
    }
    
    var body: some View {
        ZStack {
            Image("SplashScreenBackground")
                .resizable()
                .edgesIgnoringSafeArea(.all)
            VStack {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 300)
                ScrollView {
                    TextExplanationsView()
                    if let textForExternalOlvidURL = textForExternalOlvidURL {
                        ObvCardView {
                            HStack {
                                textForExternalOlvidURL
                                    .font(.body)
                                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                                Spacer()
                            }
                        }
                        .overlay(
                            Image(systemIcon: .xmarkCircleFill)
                                .font(Font.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(.red)
                                .background(Circle().fill(Color.white))
                                .offset(x: 10, y: -10)
                                .onTapGesture { store.userWantsToClearExternalOlvidURL() },
                            alignment: .topTrailing)
                        .padding(.top, 16)
                        .padding(.trailing, 10)
                        .transition(.asymmetric(insertion: .opacity, removal: .scale))
                    }
                }
                Spacer()
                HStack {
                    OlvidButton(style: colorScheme == .dark ? .standard : .standardAlt,
                                title: Text("Restore a backup"),
                                systemIcon: .folderCircle) {
                        store.userWantsToRestoreBackup()
                    }
                    OlvidButton(style: colorScheme == .dark ? .standard : .standardAlt,
                                title: Text("SCAN_QR_CODE"),
                                systemIcon: .qrcodeViewfinder) {
                        store.userWantsWantsToScanQRCode()
                    }
                }
                .padding(.bottom, 4)
                OlvidButton(style: colorScheme == .dark ? .blue : .white,
                            title: Text("Continue as a new user"),
                            systemIcon: .personCropCircle) {
                    store.userWantsToContinueAsNewUser()
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
    
}

@available(iOS 13, *)
fileprivate struct TextExplanationsView: View {
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Welcome to Olvid!")
                    .font(.headline)
                Text("If you are a new Olvid user, simply click Continue as a new user below.")
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                Text("If you already used Olvid and want to restore your identity and contacts from a backup, click Restore a backup")
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
            }
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
    
}




@available(iOS 13, *)
struct WelcomeScreenHostingView_Previews: PreviewProvider {
    
    static let mockupStore = WelcomeScreenHostingViewStore()
    
    static var previews: some View {
        Group {
            WelcomeScreenHostingView(store: mockupStore)
                .environment(\.colorScheme, .light)
            WelcomeScreenHostingView(store: mockupStore)
                .environment(\.colorScheme, .dark)
            WelcomeScreenHostingView(store: mockupStore)
                .environment(\.colorScheme, .dark)
                .previewDevice(PreviewDevice(rawValue: "com.apple.CoreSimulator.SimDeviceType.iPhone-SE"))
                .previewDisplayName("iPhone SE 1st generation")
        }
    }
    
}
