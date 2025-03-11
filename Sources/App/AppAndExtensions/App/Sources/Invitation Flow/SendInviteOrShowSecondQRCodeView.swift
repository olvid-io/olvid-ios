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

import ObvEngine
import ObvTypes
import ObvUI
import ObvUICoreData
import SwiftUI
import ObvSystemIcon
import ObvDesignSystem


/// View shown when scanning the "identity" QR code of an Olvid user, or when tapping an invitation link.
struct SendInviteOrShowSecondQRCodeView: View {
    
    let ownedCryptoId: ObvCryptoId
    let urlIdentity: ObvURLIdentity
    let contactIdentity: PersistedObvContactIdentity? /// Only set if the contact is already known
    let confirmInviteAction: (ObvURLIdentity) -> Void
    let cancelInviteAction: () -> Void
    
    @State private var mutualScanURL: ObvMutualScanUrl?
    @State private var showQRCodeFullScreen = false
    @State private var notificationTokens = [NSObjectProtocol]()
    
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
            return Color(AppTheme.shared.colorScheme.systemBackground)
        } else {
            return Color(AppTheme.shared.colorScheme.secondarySystemBackground)
        }
    }
    
    private func useLandscapeMode(for geometry: GeometryProxy) -> Bool {
        geometry.size.height < geometry.size.width
    }

    var body: some View {
        
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            GeometryReader { geometry in
                
                if useLandscapeMode(for: geometry) {
                    
                    /* --------------- */
                    // Landscape mode
                    /* --------------- */

                    HStack(spacing: 16.0) {
                        
                        VStack {
                            
                            IdentitySection(urlIdentity: urlIdentity,
                                            contactIdentity: contactIdentity,
                                            showQRCodeFullScreen: showQRCodeFullScreen)
                            
                            ObvCardView(shadow: true, backgroundColor: Color(AppTheme.shared.colorScheme.secondarySystemBackground)) {
                                
                                VStack {
                                    
                                    InviteFromADistanceCardView(urlIdentity: urlIdentity, confirmInviteAction: confirmInviteAction)
                                    
                                    Spacer(minLength: 0)
                                    
                                }

                            }
                                                        
                        }
                        
                        ObvCardView(shadow: !showQRCodeFullScreen, backgroundColor: cardViewBackgroundColor) {
                            
                            InviteLocallyView(showQRCodeFullScreen: $showQRCodeFullScreen,
                                              urlIdentity: urlIdentity,
                                              mutualScanURL: mutualScanURL)
                            
                        }

                    }
                    .padding()
                    
                } else {
                    
                    /* --------------- */
                    // Portrait mode
                    /* --------------- */

                    VStack {
                        
                        IdentitySection(urlIdentity: urlIdentity,
                                        contactIdentity: contactIdentity,
                                        showQRCodeFullScreen: showQRCodeFullScreen)
                        .padding(.horizontal, 16)
                        .padding(.top)
                        
                        ObvCardView(shadow: !showQRCodeFullScreen, backgroundColor: cardViewBackgroundColor) {
                            
                            VStack {
                                
                                InviteLocallyView(showQRCodeFullScreen: $showQRCodeFullScreen,
                                                  urlIdentity: urlIdentity,
                                                  mutualScanURL: mutualScanURL)
                                
                                if !showQRCodeFullScreen {
                                    
                                    InviteFromADistanceCardView(urlIdentity: urlIdentity, confirmInviteAction: confirmInviteAction)
                                        .padding(.top)
                                        .opacity(showQRCodeFullScreen ? 0.0 : 1.0)
                                    
                                }
                                
                            }
                            
                        }
                        .padding(.horizontal, showQRCodeFullScreen ? 0.0 : 16)
                        .padding(.vertical)
                        
                    }
                    
                }
            }
        }
        .navigationBarTitle(Text("GET_IN_CONTACT"), displayMode: .inline)
        .onAppear(perform: {
            // This prevents a crash of the SwiftUI preview
            #if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
            #endif
            ObvMessengerInternalNotification.aViewRequiresObvMutualScanUrl(
                remoteIdentity: urlIdentity.cryptoId.getIdentity(),
                ownedCryptoId: ownedCryptoId) { mutualScanUrl in
                    assert(Thread.isMainThread)
                    observeContactAddedViaMutualScan(expectedContactCryptoId: urlIdentity.cryptoId, expectedSignature: mutualScanUrl.signature)
                    self.mutualScanURL = mutualScanUrl
                }.postOnDispatchQueue()
        })

    }
    
    
    /// When receiving the `ObvMutualScanUrl` instance to display, we also listen to notifications
    /// telling us when a contact has been added. In that case, we want to dismiss the whole flow (this view in particular) and navigation to the appropriate discussion.
    /// In rare situations, we might not be notified that a discussion was inserted before it existed beforehand. This is the case when performing a mutual scan to add a "trust origin" to a contact
    /// previously known. To offer a consistent experience, we thus also observe the engine's MutualScanContactAdded notification. If, when receiving this notification, the discussion exists,
    /// we dismiss the flow and navigate to the one2one discussion, just as we would in the classical situation where we add a contact.
    private func observeContactAddedViaMutualScan(expectedContactCryptoId: ObvCryptoId, expectedSignature: Data) {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        notificationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observePersistedDiscussionWasInsertedOrReactivated { ownedCryptoId, discussionIdentifier in
                guard self.ownedCryptoId == ownedCryptoId else { return }
                ObvStack.shared.viewContext.perform {
                    guard let oneToOneDiscussion = try? PersistedDiscussion.getPersistedDiscussion(ownedCryptoId: ownedCryptoId, discussionId: discussionIdentifier, within: ObvStack.shared.viewContext) as? PersistedOneToOneDiscussion else { return }
                    guard oneToOneDiscussion.contactIdentity?.cryptoId == expectedContactCryptoId else { return }
                    navigateToSingleDiscussionAfterSuccessfulMutualScan(discussionPermanentID: oneToOneDiscussion.discussionPermanentID)
                }
            },
            ObvEngineNotificationNew.observeMutualScanContactAdded(within: NotificationCenter.default) { obvContactIdentity, signature in
                DispatchQueue.main.async {
                    guard signature == expectedSignature else { return }
                    guard self.ownedCryptoId == obvContactIdentity.ownedIdentity.cryptoId else { return }
                    // Check that the discussion exists and navigate to it if this is the case (see the comment above).
                    guard let oneToOneDiscussion = try? PersistedDiscussion.getPersistedDiscussion(ownedCryptoId: ownedCryptoId, discussionId: .oneToOne(id: .contactCryptoId(contactCryptoId: obvContactIdentity.cryptoId)), within: ObvStack.shared.viewContext) as? PersistedOneToOneDiscussion else { return }
                    guard oneToOneDiscussion.status == .active else { return }
                    navigateToSingleDiscussionAfterSuccessfulMutualScan(discussionPermanentID: oneToOneDiscussion.discussionPermanentID)
                }
            },
        ])
    }
    
    
    /// Exclusively called from ``observeContactAddedViaMutualScan(expectedContactCryptoId:expectedSignature:)``
    private func navigateToSingleDiscussionAfterSuccessfulMutualScan(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        let deepLink = ObvDeepLink.singleDiscussion(ownedCryptoId: ownedCryptoId, objectPermanentID: discussionPermanentID)
        UINotificationFeedbackGenerator()
            .notificationOccurred(.success)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }
        
}


fileprivate struct IdentitySection: View {
    
    let urlIdentity: ObvURLIdentity
    let contactIdentity: PersistedObvContactIdentity? /// Only set if the contact is already known
    let showQRCodeFullScreen: Bool
    
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
                                    .font(.body)
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


protocol InviteFromADistanceViewActions {
    func userConfirmedInvitation(urlIdentity: ObvURLIdentity) async
}


fileprivate struct InviteFromADistanceCardView: View {
    
    let urlIdentity: ObvURLIdentity
    let confirmInviteAction: (ObvURLIdentity) -> Void

    private func confirmInvite() {
        confirmInviteAction(urlIdentity)
    }

    var body: some View {
        VStack {
         
            SectionTitleNew(text: "OPTION_TWO_REMOTELY")
                .padding(.bottom)
            
            Button(action: confirmInvite) {
                Text("GET_IN_CONTACT_REMOTELY")
                    .frame(maxWidth:.infinity)
            }
            .buttonStyle(InviteButtonStyle())
            
        }
    }
    
}





fileprivate struct InviteButtonStyle: ButtonStyle {
    
    func makeBody(configuration: Configuration) -> some View {
        return configuration.label
            .padding()
            .foregroundStyle(configuration.isPressed ? .secondary : .primary)
            .clipShape(.capsule(style: .continuous))
            .overlay(
                RoundedRectangle(cornerSize: .init(width: 16, height: 16), style: .continuous)
                    .stroke(configuration.isPressed ? .secondary : .primary, lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
    
}


private struct InviteLocallyView: View {
    
    @Binding var showQRCodeFullScreen: Bool
    let urlIdentity: ObvURLIdentity
    let mutualScanURL: ObvMutualScanUrl?
    
    @Environment(\.colorScheme) var colorScheme

    private func copyMutualScanURLToPasteboard() {
        guard !ObvMessengerConstants.isRunningOnRealDevice else { return }
        guard let mutualScanURL = mutualScanURL else { return }
        UIPasteboard.general.string = mutualScanURL.urlRepresentation.absoluteString
    }

    var body: some View {
        VStack {
            if !showQRCodeFullScreen {
                
                SectionTitleNew(text: "OPTION_ONE_FACE_TO_FACE")
                    .padding(.bottom, 4)
                
                HStack {
                    Text("INVITE_\(urlIdentity.shortDisplayName)_LOCALLY")
                        .font(.body)
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
            QRCodeBlockView(urlIdentityRepresentation: mutualScanURL?.urlRepresentation, typicalPadding: 16)
                .padding(.horizontal, showQRCodeFullScreen ? 0.0 : 16.0)
                .padding(.top, showQRCodeFullScreen ? 0.0 : 4.0)
                .padding(.bottom, showQRCodeFullScreen ? 0.0 : 16.0)
                .onTapGesture(count: 1, perform: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showQRCodeFullScreen.toggle()
                    }
                })
                .onLongPressGesture(perform: copyMutualScanURLToPasteboard)

        }
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


fileprivate struct SectionTitleNew: View {
    
    let text: LocalizedStringKey
    
    var body: some View {
        HStack {
            Text(text)
            Spacer(minLength: 0)
        }
        .font(.system(.headline, design: .rounded))
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
                                                 confirmInviteAction: { _ in },
                                                 cancelInviteAction: {})
            }
            NavigationView {
                SendInviteOrShowSecondQRCodeView(ownedCryptoId: identity.cryptoId,
                                                 urlIdentity: ObvURLIdentity(urlRepresentation: identityAsURL)!,
                                                 contactIdentity: nil,
                                                 confirmInviteAction: { _ in },
                                                 cancelInviteAction: {})
                    .environment(\.colorScheme, .dark)
            }
            NavigationView {
                SendInviteOrShowSecondQRCodeView(ownedCryptoId: identity.cryptoId,
                                                 urlIdentity: ObvURLIdentity(urlRepresentation: identityAsURL)!,
                                                 contactIdentity: nil,
                                                 confirmInviteAction: { _ in },
                                                 cancelInviteAction: {})
                    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                    .previewLayout(.fixed(width: 320, height: 568))
            }
        }
    }
}
