/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

import ObvEngine
import ObvTypes
import ObvUI
import ObvUICoreData
import SwiftUI
import UI_SystemIcon
import ObvDesignSystem


struct SendInviteOrShowSecondQRCodeView: View {
    
    let ownedCryptoId: ObvCryptoId
    let urlIdentity: ObvURLIdentity
    let contactIdentity: PersistedObvContactIdentity? /// Only set if the contact is already known
    let confirmInviteAction: (ObvURLIdentity) -> Void
    let cancelInviteAction: () -> Void
    
    @State private var mutualScanURL: ObvMutualScanUrl?
    @State private var showQRCodeFullScreen = false
    @State private var notificationToken: NSObjectProtocol?
    
    @Environment(\.sizeCategory) private var sizeCategory

    private var contactAlreadyKnown: Bool {
        contactIdentity != nil
    }

    init(ownedCryptoId: ObvCryptoId, urlIdentity: ObvURLIdentity, contactIdentity: PersistedObvContactIdentity?, confirmInviteAction: @escaping (ObvURLIdentity) -> Void, cancelInviteAction: @escaping () -> Void) {
        self.ownedCryptoId = ownedCryptoId
        self.urlIdentity = urlIdentity
        if urlIdentity.cryptoId == contactIdentity?.cryptoId {
            self.contactIdentity = contactIdentity
        } else {
            self.contactIdentity = nil
        }
        self.confirmInviteAction = confirmInviteAction
        self.cancelInviteAction = cancelInviteAction
    }
    
    private var cardViewBackgroundColor: Color {
        if showQRCodeFullScreen {
            return Color.clear
        } else {
            return Color(AppTheme.shared.colorScheme.secondarySystemBackground)
        }
    }
    
    private func useLandscapeMode(for geometry: GeometryProxy) -> Bool {
        geometry.size.height < geometry.size.width
    }

    private func useSmallScreenMode(for geometry: GeometryProxy) -> Bool {
        if sizeCategory.isAccessibilityCategory { return true }
        // Small screen mode for iPhone 6, iPhone 6S, iPhone 7, iPhone 8, iPhone SE (2016)
        return max(geometry.size.height, geometry.size.width) < 510
    }
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            GeometryReader { geometry in
                HStackOrVStack(useHStack: useLandscapeMode(for: geometry)) {
                    Group {
                        IdentitySection(urlIdentity: urlIdentity,
                                        contactIdentity: contactIdentity,
                                        showQRCodeFullScreen: showQRCodeFullScreen,
                                        smallScreenMode: useSmallScreenMode(for: geometry))
                            .padding(.horizontal)
                            .padding(.top)
                        InviteLocallySection(showQRCodeFullScreen: $showQRCodeFullScreen,
                                             urlIdentity: urlIdentity,
                                             mutualScanURL: mutualScanURL,
                                             optionNumber: 1,
                                             contactAlreadyKnown: contactAlreadyKnown,
                                             smallScreenMode: useSmallScreenMode(for: geometry))
                            .padding(.horizontal)
                            .padding(.top)
                        if !showQRCodeFullScreen {
                            InviteFromADistanceSection(urlIdentity: urlIdentity,
                                                       contactIdentity: contactIdentity,
                                                       confirmInviteAction: confirmInviteAction,
                                                       optionNumber: 2,
                                                       smallScreenMode: useSmallScreenMode(for: geometry))
                                .padding(.horizontal)
                                .padding(.top)
                                .padding(.bottom)
                        }
                    }
                }
            }
        }
        .navigationBarTitle(Text("Confirm invite"), displayMode: .inline)
        .onAppear(perform: {
            // This prevents a crash of the SwiftUI preview
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
            #endif
            ObvMessengerInternalNotification.aViewRequiresObvMutualScanUrl(
                remoteIdentity: urlIdentity.cryptoId.getIdentity(),
                ownedCryptoId: ownedCryptoId) { mutualScanUrl in
                assert(Thread.isMainThread)
                observeMutualScanContactAddedForSignature(expectedSignature: mutualScanUrl.signature)
                self.mutualScanURL = mutualScanUrl
            }.postOnDispatchQueue()
        })
    }
    
    /// When receiving the `ObvMutualScanUrl` instance to display, we also listen to notifications sent by the engine (more precisely, by the protocol manager)
    /// telling us when a contact has been added. In that case, we want to dismiss the whole flow (this view in particular) and navigation to the appropriate discussion.
    private func observeMutualScanContactAddedForSignature(expectedSignature: Data) {
        if let notificationToken = notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
        notificationToken = ObvEngineNotificationNew.observeMutualScanContactAdded(within: NotificationCenter.default) { obvContactIdentity, signature in
            DispatchQueue.main.async {
                guard signature == expectedSignature else { return }
                if let notificationToken = notificationToken {
                    NotificationCenter.default.removeObserver(notificationToken)
                }
                let deepLink = ObvDeepLink.latestDiscussions(ownedCryptoId: obvContactIdentity.ownedIdentity.cryptoId)
                ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                    .postOnDispatchQueue()
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.success)
            }
        }
    }

}


fileprivate struct IdentitySection: View {
    
    let urlIdentity: ObvURLIdentity
    let contactIdentity: PersistedObvContactIdentity? /// Only set if the contact is already known
    let showQRCodeFullScreen: Bool
    let smallScreenMode: Bool
    
    var body: some View {
        ObvCardView(padding: 8) {
            HStack {
                if let contact = self.contactIdentity {
                    VStack {
                        HStack {
                            IdentityCardContentView(model: SingleContactIdentity(persistedContact: contact, observeChangesMadeToContact: false))
                            Spacer()
                        }
                        if !showQRCodeFullScreen && contact.isOneToOne {
                            HStack {
                                Text("\(contact.identityCoreDetails?.getDisplayNameWithStyle(.firstNameThenLastName) ?? contact.fullDisplayName) is already part of your trusted contacts 🙌. Do you still wish to proceed?")
                                    .font(smallScreenMode ? .system(size: 19) : .body)
                                    .allowsTightening(true)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.leading)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 8)
                                Spacer()
                            }
                        }
                    }
                } else {
                    IdentityCardContentView(model: SingleIdentity(urlIdentity: urlIdentity))
                }
                Spacer()
            }
        }
    }
}


struct InviteFromADistanceSection: View {
    
    let urlIdentity: ObvURLIdentity
    let contactIdentity: PersistedObvContactIdentity? /// Only set if the contact is already known
    let confirmInviteAction: (ObvURLIdentity) -> Void
    let optionNumber: Int
    let smallScreenMode: Bool

    private var contactAlreadyKnown: Bool {
        contactIdentity != nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: Text("OPTION_\(String(optionNumber))_FROM_A_DISTANCE"), systemIcon: .paperplaneFill, iconColor: .green)
            InviteFromADistanceCard(urlIdentity: urlIdentity,
                                    contactAlreadyKnown: contactAlreadyKnown,
                                    confirmInviteAction: confirmInviteAction,
                                    smallScreenMode: smallScreenMode)
        }
    }
}



fileprivate struct InviteFromADistanceCard: View {
    
    let urlIdentity: ObvURLIdentity
    let contactAlreadyKnown: Bool
    let confirmInviteAction: (ObvURLIdentity) -> Void
    let smallScreenMode: Bool

    var body: some View {
        ObvCardView {
            VStack {
                if !contactAlreadyKnown {
                    HStack {
                        Text("SEND_INVITE_TO_\(urlIdentity.fullDisplayName)_TO_ADD_THEM_TO_YOUR_CONTACTS_FROM_A_DISTANCE")
                            .font(smallScreenMode ? .system(size: 19) : .body)
                            .foregroundColor(.secondary)
                            .allowsTightening(true)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .padding(.bottom, 8)
                        Spacer()
                    }
                }
                OlvidButton(style: .blue, title: Text("Send invite"), systemIcon: .paperplaneFill, action: { confirmInviteAction(urlIdentity) })
            }
        }
    }
    
}



struct InviteLocallySection: View {

    @Binding var showQRCodeFullScreen: Bool
    let urlIdentity: ObvURLIdentity
    let mutualScanURL: ObvMutualScanUrl?
    let optionNumber: Int
    let contactAlreadyKnown: Bool
    let smallScreenMode: Bool

    private func copyMutualScanURLToPasteboard() {
        guard !ObvMessengerConstants.isRunningOnRealDevice else { return }
        guard let mutualScanURL = mutualScanURL else { return }
        UIPasteboard.general.string = mutualScanURL.urlRepresentation.absoluteString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !showQRCodeFullScreen {
                SectionTitle(text: Text("OPTION_\(String(optionNumber))_LOCALLY"), systemIcon: .personFillViewfinder, iconColor: .orange)
            }
            InviteLocallyCard(showQRCodeFullScreen: $showQRCodeFullScreen,
                              urlIdentity: urlIdentity,
                              mutualScanURL: mutualScanURL,
                              contactAlreadyKnown: contactAlreadyKnown,
                              smallScreenMode: smallScreenMode)
            .onLongPressGesture(perform: copyMutualScanURLToPasteboard)
        }
    }
}



struct InviteLocallyCard: View {

    @Binding var showQRCodeFullScreen: Bool
    let urlIdentity: ObvURLIdentity
    let mutualScanURL: ObvMutualScanUrl?
    let contactAlreadyKnown: Bool
    let smallScreenMode: Bool

    private var cardViewBackgroundColor: Color {
        if showQRCodeFullScreen {
            return Color.clear
        } else {
            return Color(AppTheme.shared.colorScheme.secondarySystemBackground)
        }
    }

    var body: some View {
        
        ObvCardView(shadow: !showQRCodeFullScreen, backgroundColor: cardViewBackgroundColor) {
            VStack {
                if !showQRCodeFullScreen && !contactAlreadyKnown {
                    HStack {
                        Text("INVITE_\(urlIdentity.fullDisplayName)_LOCALLY")
                            .font(smallScreenMode ? .system(size: 19) : .body)
                            .foregroundColor(.secondary)
                            .allowsTightening(true)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .padding(.bottom, 8)
                        Spacer()
                    }
                }
                // The following technique makes it possible to "update" the QRCodeBlockView when an URL becomes available
                if let url = mutualScanURL?.urlRepresentation {
                    QRCodeBlockView(urlIdentityRepresentation: url, typicalPadding: 16)
                        .environment(\.colorScheme, .light)
                } else {
                    QRCodeBlockView(urlIdentityRepresentation: nil, typicalPadding: 0)
                        .environment(\.colorScheme, .light)
                }
            }
            .overlay(
                Image(systemIcon: .handTap)
                    .foregroundColor(showQRCodeFullScreen ? .clear : .secondary),
                alignment: .bottomTrailing
            )
        }
        .onTapGesture(count: 1, perform: {
            withAnimation(.easeInOut(duration: 0.25)) {
                showQRCodeFullScreen.toggle()
            }
        })

    }
    
}




fileprivate struct SectionTitle: View {
    
    let text: Text
    let systemIcon: SystemIcon
    let iconColor: Color
    
    var body: some View {
        HStack {
            text
            Image(systemIcon: systemIcon)
                .foregroundColor(iconColor)
        }
        .font(.system(.headline, design: .rounded))
        .offset(x: 6, y: 0)
    }
    
}



struct SendInviteOrShowSecondQRCodeView_Previews: PreviewProvider {
    
    static let identityAsURL = URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!
    
    private static let identity = ObvURLIdentity(urlRepresentation: identityAsURL)!
    
    static var previews: some View {
        Group {
            NavigationView {
                SendInviteOrShowSecondQRCodeView(ownedCryptoId: identity.cryptoId,
                                                 urlIdentity: ObvURLIdentity(urlRepresentation: identityAsURL)!,
                                                 contactIdentity: nil,
                                                 confirmInviteAction: {_ in },
                                                 cancelInviteAction: {})
            }
            NavigationView {
                SendInviteOrShowSecondQRCodeView(ownedCryptoId: identity.cryptoId,
                                                 urlIdentity: ObvURLIdentity(urlRepresentation: identityAsURL)!,
                                                 contactIdentity: nil,
                                                 confirmInviteAction: {_ in },
                                                 cancelInviteAction: {})
                    .environment(\.colorScheme, .dark)
            }
            NavigationView {
                SendInviteOrShowSecondQRCodeView(ownedCryptoId: identity.cryptoId,
                                                 urlIdentity: ObvURLIdentity(urlRepresentation: identityAsURL)!,
                                                 contactIdentity: nil,
                                                 confirmInviteAction: {_ in },
                                                 cancelInviteAction: {})
                    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                    .previewLayout(.fixed(width: 320, height: 568))
            }
        }
    }
}
