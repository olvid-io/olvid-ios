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
import ObvTypes
import ObvAppTypes
import ObvDesignSystem


// MARK: - Subview: Invite group members to one2one

public struct OneToOneInvitableViewModel: Sendable, Equatable {
    let numberOfGroupMembersThatAreContactsButNotOneToOne: Int
    let numberOfOneToOneInvitationsSent: Int
    let numberOfPendingMembersWithNoAssociatedContact: Int // Those cannot be invited yet
    let groupHasNoOtherMember: Bool
    public init(numberOfGroupMembersThatAreContactsButNotOneToOne: Int, numberOfOneToOneInvitationsSent: Int, numberOfPendingMembersWithNoAssociatedContact: Int, groupHasNoOtherMember: Bool) {
        self.numberOfGroupMembersThatAreContactsButNotOneToOne = numberOfGroupMembersThatAreContactsButNotOneToOne
        self.numberOfOneToOneInvitationsSent = numberOfOneToOneInvitationsSent
        self.numberOfPendingMembersWithNoAssociatedContact = numberOfPendingMembersWithNoAssociatedContact
        self.groupHasNoOtherMember = groupHasNoOtherMember
    }
}


@MainActor
public protocol OneToOneInvitableViewDataSource {
    func getAsyncSequenceOfOneToOneInvitableViewModel(_ view: OneToOneInvitableView, groupIdentifier: ObvGroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<OneToOneInvitableViewModel>)
    func finishAsyncSequenceOfOneToOneInvitableViewModel(_ view: OneToOneInvitableView, streamUUID: UUID)
}


@MainActor
public protocol OneToOneInvitableViewNavigation {
    func userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(_ view: OneToOneInvitableView.InternalView, groupIdentifier: ObvGroupIdentifier)
}


/// This view, at the bottom of the main view, shows how many group members are not yet part of the one2one contact of the owned identity, how many can be invited in one click, etc.
public struct OneToOneInvitableView: View {
    
    let groupIdentifier: ObvGroupIdentifier
    let dataSource: OneToOneInvitableViewDataSource
    let navigation: OneToOneInvitableViewNavigation
    
    public init(groupIdentifier: ObvGroupIdentifier, dataSource: OneToOneInvitableViewDataSource, navigation: OneToOneInvitableViewNavigation) {
        self.groupIdentifier = groupIdentifier
        self.dataSource = dataSource
        self.navigation = navigation
    }
    
    @State private var model: OneToOneInvitableViewModel?
    @State private var streamUUID: UUID?
    
    private func onAppear() {
        Task {
            do {
                let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfOneToOneInvitableViewModel(self, groupIdentifier: groupIdentifier)
                if let previousStreamUUID = self.streamUUID {
                    dataSource.finishAsyncSequenceOfOneToOneInvitableViewModel(self, streamUUID: previousStreamUUID)
                }
                self.streamUUID = streamUUID
                for await model in stream {
                    if self.model == nil {
                        self.model = model
                    } else {
                        withAnimation {
                            self.model = model
                        }
                    }
                }
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func onDisappear() {
        if let previousStreamUUID = self.streamUUID {
            dataSource.finishAsyncSequenceOfOneToOneInvitableViewModel(self, streamUUID: previousStreamUUID)
            self.streamUUID = nil
        }
    }
    
    public var body: some View {
        InternalView(groupIdentifier: groupIdentifier,
                     navigation: navigation,
                     model: model)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
    }
    
    public struct InternalView: View {
        
        let groupIdentifier: ObvGroupIdentifier
        let navigation: OneToOneInvitableViewNavigation
        let model: OneToOneInvitableViewModel?

        private func userTappedButtonToShowAllInvitableContacts() {
            navigation.userWantsToNavigateToViewAllowingToSelectGroupMembersToInviteToOneToOne(self, groupIdentifier: groupIdentifier)
        }
        
        private func explanationText(model: OneToOneInvitableViewModel) -> String {
            switch (model.numberOfGroupMembersThatAreContactsButNotOneToOne > 0, model.numberOfPendingMembersWithNoAssociatedContact > 0) {
            case (false, false):
                // Note that in that case, we do not show the button.
                return String(localizedInThisBundle: "ALL_THE_GROUP_MEMBERS_ARE_PART_OF_YOUR_CONTACTS")
            case (false, true):
                return String(localizedInThisBundle: "\(model.numberOfPendingMembersWithNoAssociatedContact)_OF_THE_GROUP_MEMBERS_ARE_NOT_PART_OF_YOUR_CONTACTS_BUT_YOU_CANNOT_INVITE_THEM_UNTIL_THEY_ACCEPT_THE_GROUP_INVITATION")
            case (true, false):
                return String(localizedInThisBundle: "\(model.numberOfGroupMembersThatAreContactsButNotOneToOne)_OF_THE_GROUP_MEMBERS_ARE_NOT_PART_OF_YOUR_CONTACTS_BUT_YOU_CAN_INVITE_THEM")
            case (true, true):
                let total = model.numberOfGroupMembersThatAreContactsButNotOneToOne + model.numberOfPendingMembersWithNoAssociatedContact
                let s1 = String(localizedInThisBundle: "\(total)_OF_THE_GROUP_MEMBERS_ARE_NOT_PART_OF_YOUR_CONTACTS")
                let s2 = String(localizedInThisBundle: "YOU_CAN_INVITE_\(model.numberOfGroupMembersThatAreContactsButNotOneToOne)_OF_THEM_NOW")
                let s3 = String(localizedInThisBundle: "THE_REMAINING_\(model.numberOfPendingMembersWithNoAssociatedContact)_MUST_ACCEPT_THE_GROUP_INVITATION_BEFORE_YOU_CAN_ADD_THEM")
                let s = [s1, s2, s3].joined(separator: " ")
                return s
            }
        }
        
        private func subExplanationText(model: OneToOneInvitableViewModel) -> String? {
            guard model.numberOfOneToOneInvitationsSent > 0 else { return nil }
            if model.numberOfOneToOneInvitationsSent < model.numberOfGroupMembersThatAreContactsButNotOneToOne {
                return String(localizedInThisBundle: "YOU_ALREADY_INVITED_\(model.numberOfOneToOneInvitationsSent)_OF_THESE_MEMBERS")
            } else {
                if model.numberOfOneToOneInvitationsSent == 1 {
                    return String(localizedInThisBundle: "YOU_ALREADY_INVITED_THIS_MEMBER")
                } else {
                    return String(localizedInThisBundle: "YOU_ALREADY_INVITED_ALL_THESE_MEMBERS")
                }
            }
        }
        
        private func showButton(model: OneToOneInvitableViewModel) -> Bool {
            // We always show the button, except when all the group members are already part of the one2one contacts.
            return model.numberOfGroupMembersThatAreContactsButNotOneToOne > 0 || model.numberOfPendingMembersWithNoAssociatedContact > 0
        }
        
        public var body: some View {
            if let model {
                
                if model.groupHasNoOtherMember {
                    
                    EmptyView()
                    
                } else {
                    
                    VStack {
                        
                        HStack {
                            Text("ADD_GROUP_MEMBERS_TO_YOUR_CONTACTS")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.bold)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                        }
                        
                        ObvCardView(padding: 0) {
                            
                            HStack {
                                VStack {
                                    VStack(alignment: .leading) {
                                        HStack {
                                            Text(explanationText(model: model))
                                            Spacer(minLength: 0)
                                        }
                                        if let subExplanationText = subExplanationText(model: model) {
                                            HStack {
                                                Text(subExplanationText)
                                                Spacer(minLength: 0)
                                            }
                                            .padding(.top, 4)
                                        }
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.top)
                                    .padding(.horizontal)
                                    .padding(.bottom, showButton(model: model) ? 0 : 16)
                                    if showButton(model: model) {
                                        Divider()
                                            .padding(.vertical, 4)
                                            .padding(.leading)
                                        Button(action: userTappedButtonToShowAllInvitableContacts) {
                                            HStack {
                                                Text("SHOW_ME")
                                                    .tint(.primary)
                                                Spacer()
                                                ObvChevronRight()
                                            }
                                            .padding(.bottom)
                                            .padding(.horizontal)
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel(Text("SHOW_ME"))
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            
                        }
                    }
                    
                }
                
            } else {
                
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }.padding()
                
            }
        }
        
    }

}
