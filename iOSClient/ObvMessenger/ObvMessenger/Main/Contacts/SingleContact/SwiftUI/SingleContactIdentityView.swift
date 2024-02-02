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

import CoreData
import ObvTypes
import ObvEngine
import ObvUI
import ObvUICoreData
import SwiftUI
import ObvDesignSystem


struct SingleContactIdentityView: View {
    
    @ObservedObject var contact: SingleContactIdentity

    var body: some View {
        SingleContactIdentityInnerView(contact: contact)
            .environment(\.managedObjectContext, ObvStack.shared.viewContext)
    }
    
}



struct SingleContactIdentityInnerView: View {
    
    @ObservedObject var contact: SingleContactIdentity

    private var displayedContactGroupFetchRequest: FetchRequest<DisplayedContactGroup>
    @State private var showAlertCannotDiscussWithNonOneToOne = false

    init(contact: SingleContactIdentity) {
        self.contact = contact
        self.displayedContactGroupFetchRequest = FetchRequest(fetchRequest: contact.displayedContactGroupFetchRequest)
    }
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ScrollView {
            VStack {
                ContactIdentityHeaderView(singleIdentity: contact,
                                          editionMode: .custom(icon: .pencil(), action: { contact.userWantsToEditContactNickname() }))
                .padding(.top, 16)
                
                
                if contact.isActive {
                    if !contact.contactHasNoDevice && !contact.atLeastOneDeviceAllowsThisContactToReceiveMessages {
                        CreatingChannelExplanationView(restartChannelCreationButtonTapped: contact.userWantsToRestartChannelCreation)
                            .padding(.top, 16)
                    } else {
                        HStack {
                            OlvidButton(style: contact.contactIsOneToOne ? .standardWithBlueText : .standard,
                                        title: Text(CommonString.Word.Chat),
                                        systemIcon: .textBubbleFill,
                                        action: {
                                if contact.contactIsOneToOne {
                                    contact.userWantsToDiscuss()
                                } else {
                                    showAlertCannotDiscussWithNonOneToOne.toggle()
                                }
                            })
                            OlvidButton(style: .standardWithBlueText,
                                        title: Text(CommonString.Word.Call),
                                        systemIcon: .phoneFill,
                                        action: contact.userWantsToCallContact)
                            .disabled(!contact.atLeastOneDeviceAllowsThisContactToReceiveMessages)
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
                
                if let persistedContact = contact.persistedContact, let textOfNote = persistedContact.note, !textOfNote.isEmpty {
                    PersonalNoteView(model: persistedContact)
                        .padding(.top, 16)
                }
                
                ContactIdentityCardViews(contact: contact,
                                         contactStatus: $contact.contactStatus)
                .padding(.top, 16)
                .padding(.bottom, 16)
                
                if !displayedContactGroupFetchRequest.wrappedValue.isEmpty {
                    GroupsCardView(displayedContactGroups: displayedContactGroupFetchRequest.wrappedValue,
                                   userWantsToNavigateToSingleGroupView: contact.userWantsToNavigateToSingleGroupView,
                                   tappedGroup: $contact.tappedGroup)
                    .padding(.top, 16)
                }
                
                if let persistedContact = contact.persistedContact {
                    ContactDevicesCardView(
                        contact: persistedContact,
                        userWantsToNavigateToListOfContactDevicesView: contact.userWantsToNavigateToListOfContactDevicesView)
                    .padding(.top, 16)
                }
                
                TrustOriginsCardView(
                    trustOrigins: contact.trustOrigins,
                    userWantsToNavigateToListOfTrustOriginsView: contact.userWantsToNavigateToListOfTrustOriginsView)
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
            .alert(isPresented: $showAlertCannotDiscussWithNonOneToOne) {
                Alert(title: Text("INVITE_REQUIRED_ALERT_TITLE"),
                      message: Text("YOU_NEED_TO_INVITE_\(contact.getFirstName(for: .trusted))_BEFORE_HAVING_DISCUSSION_ALERT_MESSAGE"),
                      primaryButton: .cancel(Text("Cancel")),
                      secondaryButton: .default(Text("Invite")) {
                    contact.userWantsToInviteContactToOneToOne()
                })
            }
        }.background {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
        }
    }
}



fileprivate struct GroupsCardView: View {
    
    let displayedContactGroups: FetchedResults<DisplayedContactGroup>
    let userWantsToNavigateToSingleGroupView: (DisplayedContactGroup) -> Void
    @Binding var tappedGroup: DisplayedContactGroup?

    init(displayedContactGroups: FetchedResults<DisplayedContactGroup>,
         userWantsToNavigateToSingleGroupView: @escaping (DisplayedContactGroup) -> Void,
         tappedGroup: Binding<DisplayedContactGroup?>) {
        self.displayedContactGroups = displayedContactGroups
        self.userWantsToNavigateToSingleGroupView = userWantsToNavigateToSingleGroupView
        self._tappedGroup = tappedGroup
    }
    
    var body: some View {
        if displayedContactGroups.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading) {
                HStack {
                    Text(CommonString.Word.Groups)
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                }
                ObvCardView {
                    GroupCellsStackView(displayedContactGroups: displayedContactGroups,
                                        userWantsToNavigateToSingleGroupView: userWantsToNavigateToSingleGroupView,
                                        tappedGroup: $tappedGroup)
                }
            }
        }
    }
    
}



fileprivate struct GroupCellsStackView: View {
    
    let displayedContactGroups: FetchedResults<DisplayedContactGroup>
    let userWantsToNavigateToSingleGroupView: (DisplayedContactGroup) -> Void
    @Binding var tappedGroup: DisplayedContactGroup?
    @State private var forceUpdate: Bool = false // Dirty bugfix

    init(displayedContactGroups: FetchedResults<DisplayedContactGroup>,
         userWantsToNavigateToSingleGroupView: @escaping (DisplayedContactGroup) -> Void,
         tappedGroup: Binding<DisplayedContactGroup?>) {
        self.displayedContactGroups = displayedContactGroups
        self.userWantsToNavigateToSingleGroupView = userWantsToNavigateToSingleGroupView
        self._tappedGroup = tappedGroup
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(displayedContactGroups) { group in
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
                if group != displayedContactGroups.last {
                    SeparatorView()
                }
            }
        }
    }
    
}



private struct GroupCellView: View {

    @ObservedObject var group: DisplayedContactGroup
    let showChevron: Bool
    let selected: Bool
    
    private var textViewModel: TextView.Model {
        .init(titlePart1: group.displayedTitle,
              titlePart2: nil,
              subtitle: group.subtitle,
              subsubtitle: nil)
    }
    
    private var profilePictureViewModelContent: ProfilePictureView.Model.Content {
        .init(text: nil,
              icon: .person3Fill,
              profilePicture: group.displayedImage,
              showGreenShield: group.isKeycloakManaged,
              showRedShield: false)
    }
    
    private var circleAndTitlesViewModelContent: CircleAndTitlesView.Model.Content {
        .init(textViewModel: textViewModel,
              profilePictureViewModelContent: profilePictureViewModelContent)
    }
    
    private var initialCircleViewModelColors: InitialCircleView.Model.Colors {
        .init(background: group.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
              foreground: group.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared))
    }
    
    private var circleAndTitlesViewModel: CircleAndTitlesView.Model {
        .init(content: circleAndTitlesViewModelContent,
              colors: initialCircleViewModelColors,
              displayMode: .normal,
              editionMode: .none)
    }
    
    var body: some View {
        HStack {

            CircleAndTitlesView(model: circleAndTitlesViewModel)

            Spacer()

            if showChevron {
                
                if let groupV1 = group.groupV1 {
                    if let joinedGroup = groupV1 as? PersistedContactGroupJoined {
                        switch joinedGroup.status {
                        case .noNewPublishedDetails:
                            EmptyView()
                        case .unseenPublishedDetails:
                            Image(systemName: "person.crop.rectangle")
                                .foregroundColor(.red)
                        case .seenPublishedDetails:
                            Image(systemName: "person.crop.rectangle")
                                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        }
                    }
                }
                
                ObvChevron(selected: selected)
            }
        }
        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
    }

}




fileprivate struct TrustOriginsCardView: View {
    
    let trustOrigins: [ObvTrustOrigin]
    let userWantsToNavigateToListOfTrustOriginsView: () -> Void
    @State private var selected = false

    var body: some View {
        VStack(alignment: .leading) {
            ObvCardView {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemIcon: .checkmarkShield)
                        .foregroundColor(Color(.systemGreen))
                        .font(.system(size: 22))
                        .frame(width: 40)

                    Text("TRUST_ORIGINS")
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                    
                    Spacer()
                 
                    ObvChevron(selected: selected)
                    
                }
                .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
                .onTapGesture {
                    withAnimation {
                        selected = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                            userWantsToNavigateToListOfTrustOriginsView()
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                        withAnimation {
                            selected = false
                        }
                    }
                }
            }
        }
    }
    
}


fileprivate struct ContactDevicesCardView: View {
    
    let contact: PersistedObvContactIdentity
    let userWantsToNavigateToListOfContactDevicesView: () -> Void
    @State private var selected = false
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Devices")
                    .font(.system(.headline, design: .rounded))
                Spacer()
            }
            ObvCardView {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemIcon: .laptopcomputerAndIphone)
                        .foregroundColor(Color(.systemBlue))
                        .font(.system(size: 22))
                        .frame(width: 40)

                    Text(String.localizedStringWithFormat(NSLocalizedString("CONTACT_HAS_N_DEVICES", comment: ""), contact.customOrShortDisplayName, contact.devices.count))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                    
                    Spacer()
                 
                    ObvChevron(selected: selected)
                    
                }
                .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
                .onTapGesture {
                    withAnimation {
                        selected = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                            userWantsToNavigateToListOfContactDevicesView()
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                        withAnimation {
                            selected = false
                        }
                    }
                }
            }
        }
    }

    
}



fileprivate struct ContactIdentityCardViews: View {
    
    @ObservedObject var contact: SingleContactIdentity
    @Binding var contactStatus: PersistedObvContactIdentity.Status
    
    private var OneToOneInvitationSentFetchRequest: FetchRequest<PersistedInvitationOneToOneInvitationSent>

    private var deviceName: String {
        UIDevice.current.name
    }

    private let introduceAction: OlvidButtonAction
    private let inviteToOneToOneAction: OlvidButtonAction
    private let abortInviteToOneToOneAction: OlvidButtonAction
    private let updateDetailsAction: OlvidButtonAction

    init(contact: SingleContactIdentity,
         contactStatus: Binding<PersistedObvContactIdentity.Status>) {
        self.contact = contact
        self._contactStatus = contactStatus
        self.OneToOneInvitationSentFetchRequest = FetchRequest(fetchRequest: contact.oneToOneInvitationSentFetchRequest)
        self.introduceAction = OlvidButtonAction(action: contact.introduceToAnotherContact,
                                                 title: Text("INTRODUCE_\(contact.publishedContactDetails?.coreDetails.getDisplayNameWithStyle(.short) ?? contact.shortDisplayableName)_TO"),
                                                 systemIcon: .arrowshapeTurnUpForwardFill)
        self.inviteToOneToOneAction = OlvidButtonAction(action: contact.userWantsToInviteContactToOneToOne,
                                                        title: Text(CommonString.Word.Invite),
                                                        systemIcon: .personCropCircleBadgePlus)
        self.updateDetailsAction = OlvidButtonAction(action: contact.updateDetails,
                                                     title: Text("UPDATE_DETAILS"),
                                                     systemIcon: .personCropCircleBadgeCheckmark)
        self.abortInviteToOneToOneAction = OlvidButtonAction(action: contact.userWantsToCancelSentInviteContactToOneToOne,
                                                             title: Text(CommonString.Word.Abort),
                                                             systemIcon: .xmarkCircleFill,
                                                             style: .standardWithBlueText)
    }
    
    private func actionsForMainCard(hasOneToOneInvitationSent: Bool) -> [OlvidButtonAction] {
        guard contact.atLeastOneDeviceAllowsThisContactToReceiveMessages && contact.isActive else { return [] }
        if contact.contactIsOneToOne {
            return [introduceAction]
        } else if hasOneToOneInvitationSent {
            return [abortInviteToOneToOneAction]
        } else {
            return [inviteToOneToOneAction]
        }
    }
    
    private func explanationForMainCard(hasOneToOneInvitationSent: Bool) -> Text? {
        // This test in correct only because we do not use this SingleIdentityView to show keycloak-only users.
        // Instead of this simple test, we should query the MainFlowViewController to see if there is a one2one invitation
        // that can be sent to the user (keycloak and/or protocol).
        guard contact.atLeastOneDeviceAllowsThisContactToReceiveMessages && contact.isActive else { return nil }
        if contact.contactIsOneToOne {
            return nil
        } else if hasOneToOneInvitationSent {
            return Text("ONE_TO_ONE_DISCUSSION_INVITATION_SENT_TO_\(contact.getFirstName(for: .trusted))")
        } else {
            return Text("INVITE_\(contact.getFirstName(for: .trusted))_IF_YOU_WANT_ONE_TO_ONE_DISCUSSION")
        }
    }
        
    var body: some View {
        switch contactStatus {
        case .noNewPublishedDetails:
            ContactIdentityCardView(contact: contact,
                                    actions: actionsForMainCard(hasOneToOneInvitationSent: OneToOneInvitationSentFetchRequest.wrappedValue.isEmpty ? false : true),
                                    preferredDetails: .trusted,
                                    topLeftText: nil,
                                    explanationText: explanationForMainCard(hasOneToOneInvitationSent: OneToOneInvitationSentFetchRequest.wrappedValue.isEmpty ? false : true))
        case .unseenPublishedDetails, .seenPublishedDetails:
            VStack(spacing: 12) {
                ContactIdentityCardView(contact: contact,
                                        actions: actionsForMainCard(hasOneToOneInvitationSent: OneToOneInvitationSentFetchRequest.wrappedValue.isEmpty ? false : true),
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


fileprivate struct BottomButtonsView: View {

    let contact: SingleContactIdentity
    let userWantsToDeleteContact: () -> Void
    
    @State private var confirmRecreateTheSecureChannelSheetPresented = false
    @State private var showingContactDetails = false
    
    private var deleteContactButtonTitle: Text {
        switch contact.preferredDeletionType {
        case .legacyFullDeletion: return Text("DELETE_CONTACT")
        case .downgradeToNonOneToOne: return Text("DOWNGRADE_CONTACT_TO_NON_ONE_TO_ONE_BUTTON_TITLE")
        case .fullDeletion: return Text("DELETE_OLVID_USER")
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            
            if let persistedContact = contact.persistedContact {
                OlvidButton(style: .standard,
                            title: Text("SHOW_CONTACT_DETAILS"),
                            systemIcon: .personCropCircleBadgeQuestionmark,
                            action: { showingContactDetails.toggle() })
                    .sheet(isPresented: $showingContactDetails,
                           onDismiss: nil) {
                        ContactDetailedInfosView(contact: persistedContact,
                                                 userWantsToSyncOneToOneStatusOfContact: contact.userWantsToSyncOneToOneStatusOfContact)
                    }
            }
            
            // No confirmation required, this confirmation is requested in the containing View Controller
            OlvidButton(style: .standard,
                        title: deleteContactButtonTitle,
                        systemIcon: .minusCircle,
                        action: userWantsToDeleteContact)
        }
    }
    
}



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
                    ProgressView()
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
                    TopLeftTextForCardView(text: text)
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
                                               publishedContactDetails: nil,
                                               contactStatus: .noNewPublishedDetails,
                                               atLeastOneDeviceAllowsThisContactToReceiveMessages: true,
                                               contactHasNoDevice: false,
                                               contactIsOneToOne: true,
                                               isActive: true,
                                               trustOrigins: trustOrigins)

    static let contactWithOtherDetails = SingleContactIdentity(firstName: "Steve",
                                                               lastName: "Jobs",
                                                               position: "CEO",
                                                               company: "NeXT",
                                                               publishedContactDetails: otherIdentityDetails,
                                                               contactStatus: .seenPublishedDetails,
                                                               atLeastOneDeviceAllowsThisContactToReceiveMessages: true,
                                                               contactHasNoDevice: false,
                                                               contactIsOneToOne: true,
                                                               isActive: true,
                                                               trustOrigins: trustOrigins)

    static let contactWithoutDevice = SingleContactIdentity(firstName: "Some",
                                                            lastName: "User",
                                                            position: "Without Device",
                                                            company: "Olvid",
                                                            publishedContactDetails: nil,
                                                            contactStatus: .noNewPublishedDetails,
                                                            atLeastOneDeviceAllowsThisContactToReceiveMessages: false,
                                                            contactHasNoDevice: false,
                                                            contactIsOneToOne: true,
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
            SingleContactIdentityInnerView(contact: contact)
            SingleContactIdentityInnerView(contact: contactWithOtherDetails)
            SingleContactIdentityInnerView(contact: contactWithOtherDetails)
                .environment(\.colorScheme, .dark)
                .environment(\.locale, .init(identifier: "fr"))
            SingleContactIdentityInnerView(contact: contactWithoutDevice)
        }
    }
}
