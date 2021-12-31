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

import SwiftUI
import ObvTypes
import ObvEngine
import CoreData


@available(iOS 13, *)
struct SingleContactIdentityView: View {
    
    @ObservedObject var contact: SingleContactIdentity

    var body: some View {
        SingleContactIdentityInnerView(contact: contact,
                                       changed: $contact.changed,
                                       contactStatus: $contact.contactStatus,
                                       tappedGroup: $contact.tappedGroup)
            .environment(\.managedObjectContext, ObvStack.shared.viewContext)
    }
    
}


@available(iOS 13, *)
struct SingleContactIdentityInnerView: View {
    
    @ObservedObject var contact: SingleContactIdentity
    @Binding var changed: Bool
    @Binding var contactStatus: PersistedObvContactIdentity.Status
    @Binding var tappedGroup: PersistedContactGroup?

    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack {
                    ContactIdentityHeaderView(singleIdentity: contact,
                                              forceEditionMode: .nicknameAndPicture(action: { contact.userWantsToEditContactNickname() }))
                        .padding(.top, 16)
                    
                    
                    if contact.isActive {
                        if contact.contactHasNoDevice {
                            CreatingChannelExplanationView(restartChannelCreationButtonTapped: contact.userWantsToRestartChannelCreation)
                                .padding(.top, 16)
                        } else {
                            HStack {
                                OlvidButton(style: .standardWithBlueText,
                                            title: Text(CommonString.Word.Chat),
                                            systemIcon: .textBubbleFill,
                                            action: contact.userWantsToDiscuss)
                                OlvidButton(style: .standardWithBlueText,
                                            title: Text(CommonString.Word.Call),
                                            systemIcon: .phoneFill,
                                            action: contact.userWantsToCallContact)
                                    .disabled(contact.contactHasNoDevice)
                            }
                            .padding(.top, 16)
                        }
                        if contact.showReblockView, let contactCryptoId = contact.persistedContact?.cryptoId, let ownedCryptoId = contact.persistedContact?.ownedIdentity?.cryptoId {
                            ContactCanBeReblockedExplanationView(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
                                .padding(.top, 16)
                        }
                    } else if let contactCryptoId = contact.persistedContact?.cryptoId, let ownedCryptoId = contact.persistedContact?.ownedIdentity?.cryptoId {
                        ContactIsNotActiveExplanationView(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
                    }
                    
                    ContactIdentityCardViews(contact: contact,
                                             changed: $contact.changed,
                                             contactStatus: $contact.contactStatus)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    if let groupFetchRequest = contact.groupFetchRequest {
                        GroupsCardView(groupFetchRequest: groupFetchRequest,
                                       changed: $changed,
                                       userWantsToNavigateToSingleGroupView: contact.userWantsToNavigateToSingleGroupView,
                                       tappedGroup: $tappedGroup)
                            .padding(.top, 16)
                    }

                    TrustOriginsCardView(trustOrigins: contact.trustOrigins)
                        .padding(.top, 16)
                    
                    BottomButtonsView(contact: contact,
                                      userWantsToDeleteContact: {contact.userWantsToDeleteContact { success in
                                        guard success else { return }
                                        presentationMode.wrappedValue.dismiss()
                                      }})
                        .padding(.top, 16)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
    }
}


@available(iOS 13, *)
fileprivate struct GroupsCardView: View {
    
    private var fetchRequest: FetchRequest<PersistedContactGroup>
    let groupFetchRequest: NSFetchRequest<PersistedContactGroup>
    @Binding var changed: Bool
    let userWantsToNavigateToSingleGroupView: (PersistedContactGroup) -> Void
    @Binding var tappedGroup: PersistedContactGroup?

    init(groupFetchRequest: NSFetchRequest<PersistedContactGroup>, changed: Binding<Bool>, userWantsToNavigateToSingleGroupView: @escaping (PersistedContactGroup) -> Void, tappedGroup: Binding<PersistedContactGroup?>) {
        self.fetchRequest = FetchRequest(fetchRequest: groupFetchRequest)
        self.groupFetchRequest = groupFetchRequest
        self._changed = changed
        self.userWantsToNavigateToSingleGroupView = userWantsToNavigateToSingleGroupView
        self._tappedGroup = tappedGroup
    }
    
    var body: some View {
        if fetchRequest.wrappedValue.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading) {
                HStack {
                    Text(CommonString.Word.Groups)
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                }
                ObvCardView {
                    GroupCellsStackView(groupFetchRequest: groupFetchRequest,
                                        changed: $changed,
                                        userWantsToNavigateToSingleGroupView: userWantsToNavigateToSingleGroupView,
                                        tappedGroup: $tappedGroup)
                }
            }
        }
    }
    
}


@available(iOS 13, *)
fileprivate struct GroupCellsStackView: View {
    
    private var fetchRequest: FetchRequest<PersistedContactGroup>
    @Binding var changed: Bool
    let userWantsToNavigateToSingleGroupView: (PersistedContactGroup) -> Void
    @Binding var tappedGroup: PersistedContactGroup?
    @State private var forceUpdate: Bool = false // Dirty bugfix

    init(groupFetchRequest: NSFetchRequest<PersistedContactGroup>, changed: Binding<Bool>, userWantsToNavigateToSingleGroupView: @escaping (PersistedContactGroup) -> Void, tappedGroup: Binding<PersistedContactGroup?>) {
        self.fetchRequest = FetchRequest(fetchRequest: groupFetchRequest)
        self._changed = changed
        self.userWantsToNavigateToSingleGroupView = userWantsToNavigateToSingleGroupView
        self._tappedGroup = tappedGroup
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(fetchRequest.wrappedValue, id: \.self) { group in
                GroupCellView(group: group, showChevron: true, selected: tappedGroup == group)
                    .onTapGesture {
                        withAnimation {
                            tappedGroup = group
                            forceUpdate.toggle()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                            userWantsToNavigateToSingleGroupView(group)
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                            withAnimation {
                                tappedGroup = nil
                                forceUpdate.toggle()
                            }
                        }
                    }
                if group != fetchRequest.wrappedValue.last {
                    SeparatorView()
                }
            }
        }
    }
    
}



@available(iOS 13, *)
fileprivate struct TrustOriginsCardView: View {
    
    let trustOrigins: [ObvTrustOrigin]
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        df.dateStyle = .short
        df.doesRelativeDateFormatting = true
        return df
    }()

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("TRUST_ORIGINS")
                    .font(.system(.headline, design: .rounded))
                Spacer()
            }
            ObvCardView {
                TrustOriginsView(trustOrigins: trustOrigins, dateFormatter: dateFormatter)
            }
        }
    }
    
}


@available(iOS 13, *)
fileprivate struct ContactIdentityCardViews: View {
    
    @ObservedObject var contact: SingleContactIdentity
    @Binding var changed: Bool
    @Binding var contactStatus: PersistedObvContactIdentity.Status

    private var deviceName: String {
        UIDevice.current.name
    }

    private let introduceAction: OlvidButtonAction
    private let updateDetailsAction: OlvidButtonAction

    init(contact: SingleContactIdentity, changed: Binding<Bool>, contactStatus: Binding<PersistedObvContactIdentity.Status>) {
        self.contact = contact
        self._changed = changed
        self._contactStatus = contactStatus
        self.introduceAction = OlvidButtonAction(action: contact.introduceToAnotherContact,
                                                 title: Text("INTRODUCE_\(contact.publishedContactDetails?.coreDetails.getDisplayNameWithStyle(.short) ?? contact.shortDisplayableName)_TO"),
                                                 systemIcon: .arrowshapeTurnUpForwardFill)
        self.updateDetailsAction = OlvidButtonAction(action: contact.updateDetails,
                                                     title: Text("UPDATE_DETAILS"),
                                                     systemIcon: .personCropCircleBadgeCheckmark)
    }
    
    
    
    var body: some View {
        switch contactStatus {
        case .noNewPublishedDetails:
            ContactIdentityCardView(contact: contact,
                                    actions: [introduceAction],
                                    preferredDetails: .trusted,
                                    topLeftText: nil,
                                    explanationText: nil)
        case .unseenPublishedDetails, .seenPublishedDetails:
            VStack(spacing: 12) {
                ContactIdentityCardView(contact: contact,
                                        actions: [introduceAction],
                                        preferredDetails: .publishedOrTrusted,
                                        topLeftText: Text("New"),
                                        explanationText: nil)
                ContactIdentityCardView(contact: contact,
                                        actions: [],
                                        preferredDetails: .trusted,
                                        topLeftText: Text("ON_MY_DEVICE_\(deviceName)"),
                                        explanationText: Text("NEW_DETAILS_EXPLANATION_\(contact.shortDisplayableName)_\(deviceName)"))
                OlvidButton(olvidButtonAction: updateDetailsAction)
            }
        }
    }
    
}

@available(iOS 13, *)
fileprivate struct BottomButtonsView: View {

    let contact: SingleContactIdentity
    let userWantsToDeleteContact: () -> Void
    
    @State private var confirmRecreateTheSecureChannelSheetPresented = false
    @State private var showingContactDetails = false
    
    var body: some View {
        VStack(spacing: 8) {
            
            if !contact.contactHasNoDevice {
                OlvidButton(style: .standard,
                            title: Text("RECREATE_CHANNEL"),
                            systemIcon: .restartCircle,
                            action: { confirmRecreateTheSecureChannelSheetPresented.toggle() })
                    .actionSheet(isPresented: $confirmRecreateTheSecureChannelSheetPresented) {
                        ActionSheet(title: Text("RECREATE_CHANNEL"), message: Text("Do you really wish to recreate the secure channel?"), buttons: [
                            .default(Text("Yes"), action: contact.userWantsToRecreateTheSecureChannel),
                            .cancel(),
                        ])
                    }
            }

            if let persistedContact = contact.persistedContact {
                OlvidButton(style: .standard,
                            title: Text("SHOW_CONTACT_DETAILS"),
                            systemIcon: .personCropCircleBadgeQuestionmark,
                            action: { showingContactDetails.toggle() })
                    .sheet(isPresented: $showingContactDetails,
                           onDismiss: nil) {
                        ContactDetailedInfosView(contact: persistedContact)
                    }
            }
            
            // No confirmation required, this confirmation is requested in the containing View Controller
            OlvidButton(style: .standard,
                        title: Text("DELETE_CONTACT"),
                        systemIcon: .minusCircle,
                        action: userWantsToDeleteContact)
        }
    }
    
}


@available(iOS 13, *)
fileprivate struct CreatingChannelExplanationView: View {
    
    let restartChannelCreationButtonTapped: () -> Void
    @State private var showAlertConfirmRestart = false
    
    var body: some View {
        ObvCardView {
            VStack(spacing: 8) {
                HStack(alignment: .top) {
                    Text("ESTABLISHING_SECURE_CHANNEL")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    ObvActivityIndicator(isAnimating: .constant(true), style: .medium)
                }
                HStack {
                    Text("ESTABLISHING_SECURE_CHANNEL_EXPLANATION")
                        .lineLimit(nil)
                        .font(.body)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: /*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
                    Spacer()
                }
                OlvidButton(style: .standard, title: Text("Restart"), systemIcon: .restartCircle, action: { showAlertConfirmRestart.toggle() })
            }
        }
        .actionSheet(isPresented: $showAlertConfirmRestart) {
            ActionSheet(title: Text("RESTART_CHANNEL_CREATION"), message: Text("Do you really wish to restart the channel establishment?"), buttons: [
                .default(Text("Yes"), action: restartChannelCreationButtonTapped),
                .cancel(),
            ])
        }
    }
    
}


@available(iOS 13, *)
fileprivate struct ContactIsNotActiveExplanationView: View {
    
    let ownedCryptoId: ObvCryptoId
    let contactCryptoId: ObvCryptoId
    @State private var showAlertConfirm = false

    var body: some View {
        ObvCardView {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("CONTACT_IS_NOT_ACTIVE_EXPLANATION_TITLE")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemIcon: .exclamationmarkShieldFill)
                        .foregroundColor(.red)
                }
                .font(.headline)
                HStack {
                    Text("CONTACT_IS_NOT_ACTIVE_EXPLANATION_BODY")
                        .lineLimit(nil)
                        .font(.body)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: /*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
                    Spacer()
                }
                OlvidButton(style: .standard, title: Text("UNBLOCK_CONTACT"), systemIcon: .shieldFill, action: { showAlertConfirm.toggle() })
            }
        }
        .actionSheet(isPresented: $showAlertConfirm) {
            ActionSheet(title: Text("UNBLOCK_CONTACT"), message: Text("UNBLOCK_CONTACT_CONFIRMATION"), buttons: [
                .default(Text("Yes"), action: {
                    ObvMessengerInternalNotification.userWantsToUnblockContact(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
                        .postOnDispatchQueue()
                }),
                .cancel(),
            ])
        }
    }

}


@available(iOS 13, *)
fileprivate struct ContactCanBeReblockedExplanationView: View {
    
    let ownedCryptoId: ObvCryptoId
    let contactCryptoId: ObvCryptoId
    @State private var showAlertConfirm = false

    var body: some View {
        ObvCardView {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("CONTACT_IS_NOT_ACTIVE_EXPLANATION_TITLE")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemIcon: .shieldFill)
                }
                .font(.headline)
                HStack {
                    Text("EXPLANATION_CONTACT_REVOKED_AND_UNBLOCKED")
                        .lineLimit(nil)
                        .font(.body)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: /*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
                    Spacer()
                }
                OlvidButton(style: .standard, title: Text("REBLOCK_CONTACT"), systemIcon: .exclamationmarkShieldFill, action: { showAlertConfirm.toggle() })
            }
        }
        .actionSheet(isPresented: $showAlertConfirm) {
            ActionSheet(title: Text("REBLOCK_CONTACT"), message: Text("REBLOCK_CONTACT_CONFIRMATION"), buttons: [
                .default(Text("Yes"), action: {
                    ObvMessengerInternalNotification.userWantsToReblockContact(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
                        .postOnDispatchQueue()
                }),
                .cancel(),
            ])
        }
    }

}


@available(iOS 13, *)
struct ContactIdentityCardView: View {

    @ObservedObject var contact: SingleContactIdentity
    let actions: [OlvidButtonAction]
    let preferredDetails: PreferredDetails
    let topLeftText: Text?
    let explanationText: Text?

    var body: some View {
        ObvCardView(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let text = self.topLeftText {
                    TopLeftText(text: text)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ContactIdentityCardContentView(model: contact,
                                                   preferredDetails: preferredDetails)
                    HStack { Spacer() }
                    if let text = self.explanationText {
                        text
                            .font(.caption)
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                            .padding(.top, 16)
                    }
                    if !actions.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(actions) { action in
                                OlvidButton(olvidButtonAction: action)
                            }
                        }
                        .padding(.top, 16)
                    }
                }
                .padding()
            }
        }
    }
}


@available(iOS 13, *)
fileprivate struct TopLeftText: View {
    
    let text: Text
    let backgroundColor = Color.green
    let textColor = Color.white
    
    var body: some View {
        text
            .font(.footnote)
            .fontWeight(.medium)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .foregroundColor(.white)
            .background(
                ObvRoundedRectangle(tl: 16, tr: 0, bl: 0, br: 16)
                    .foregroundColor(.green)
            )
    }
    
}


@available(iOS 13, *)
struct SingleContactIdentityView_Previews: PreviewProvider {
    
    static let otherCoreDetails = try! ObvIdentityCoreDetails(firstName: "Steve",
                                                              lastName: "Jobs",
                                                              company: "Apple",
                                                              position: "CEO",
                                                              signedUserDetails: nil)
    static let otherIdentityDetails = ObvIdentityDetails(coreDetails: otherCoreDetails,
                                                         photoURL: nil)
    
    static let contact = SingleContactIdentity(firstName: "Tim",
                                               lastName: "Cooks",
                                               position: "CEO",
                                               company: "Apple",
                                               editionMode: .none,
                                               publishedContactDetails: nil,
                                               contactStatus: .noNewPublishedDetails,
                                               contactHasNoDevice: false,
                                               isActive: true,
                                               trustOrigins: trustOrigins)
    
    static let contactWithOtherDetails = SingleContactIdentity(firstName: "Steve",
                                                               lastName: "Jobs",
                                                               position: "CEO",
                                                               company: "NeXT",
                                                               editionMode: .none,
                                                               publishedContactDetails: otherIdentityDetails,
                                                               contactStatus: .seenPublishedDetails,
                                                               contactHasNoDevice: false,
                                                               isActive: true,
                                                               trustOrigins: trustOrigins)
    
    static let contactWithoutDevice = SingleContactIdentity(firstName: "Some",
                                                            lastName: "User",
                                                            position: "Without Device",
                                                            company: "Olvid",
                                                            editionMode: .none,
                                                            publishedContactDetails: nil,
                                                            contactStatus: .noNewPublishedDetails,
                                                            contactHasNoDevice: true,
                                                            isActive: true,
                                                            trustOrigins: trustOrigins)

    
    static let someDate = Date(timeIntervalSince1970: 1_600_000_000)

    static let trustOrigins: [ObvTrustOrigin] = [
        .direct(timestamp: someDate),
        .introduction(timestamp: someDate, mediator: nil),
            .group(timestamp: someDate, groupOwner: nil),
    ]
    
    static var previews: some View {
        Group {
            SingleContactIdentityInnerView(contact: contact, changed: .constant(false), contactStatus: .constant(contact.contactStatus), tappedGroup: .constant(nil))
            SingleContactIdentityInnerView(contact: contactWithOtherDetails, changed: .constant(false), contactStatus: .constant(contact.contactStatus), tappedGroup: .constant(nil))
            SingleContactIdentityInnerView(contact: contactWithOtherDetails, changed: .constant(false), contactStatus: .constant(contact.contactStatus), tappedGroup: .constant(nil))
                .environment(\.colorScheme, .dark)
                .environment(\.locale, .init(identifier: "fr"))
            SingleContactIdentityInnerView(contact: contactWithoutDevice, changed: .constant(false), contactStatus: .constant(contact.contactStatus), tappedGroup: .constant(nil))
        }
    }
}
