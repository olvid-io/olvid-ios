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
import CoreData
import ObvDesignSystem
import ObvTypes


// MARK: - VerticalUsersView


/// In practice, `ManagedUserViewForVerticalUsersLayoutModelProtocol` is implemented by `PersistedUser`.
protocol VerticalUsersViewModelProtocol: ObservableObject, UsersScrollingViewModelProtocol {
    // associatedtype VerticalUserModel: ManagedUserViewForVerticalUsersLayoutModelProtocol
    @MainActor var searchInProgress: Bool { get }
    @MainActor var showSortingSpinner: Bool { get }
    //@MainActor var nsFetchRequest: NSFetchRequest<VerticalContactModel> { get }
}


protocol VerticalUsersViewActionsProtocol: UsersScrollingViewActionsProtocol {
    
}


protocol VerticalUsersViewConfigurationProtocol: UsersScrollingViewConfigurationProtocol {
    var showExplanation: Bool { get }
}


struct VerticalUsersView<Model: VerticalUsersViewModelProtocol>: View {
    
    @ObservedObject public var model: Model
    let actions: VerticalUsersViewActionsProtocol
    let configuration: VerticalUsersViewConfigurationProtocol
    
    var body: some View {
        if model.showSortingSpinner {
            ProgressView()
        } else if configuration.showExplanation && model.users.isEmpty {
            if model.searchInProgress {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView.search
                }
            } else {
                if #available(iOS 18.0, *) {
                    ObvContentUnavailableView(title: String(localized: "CONTENT_UNAVAILABLE_CONTACTS_TEXT") , systemIcon: .person, description: String(localized: "CONTENT_UNAVAILABLE_CONTACTS_DESCRIPTION_WHEN_USING_FLOATING_BUTTON"))
                } else {
                    ObvContentUnavailableView(title: String(localized: "CONTENT_UNAVAILABLE_CONTACTS_TEXT"), systemIcon: .person, description: String(localized: "CONTENT_UNAVAILABLE_CONTACTS_DESCRIPTION"))
                }
            }
        } else {
            UsersScrollingView(model: model, actions: actions, configuration: configuration)
        }
    }
    
}


// MARK: - UsersScrollingView

protocol UsersScrollingViewModelProtocol: ObservableObject, UsersInnerViewModelProtocol {
    // associatedtype VerticalUSerModel: ManagedUserViewForVerticalUsersLayoutModelProtocol
    @MainActor var userToScrollTo: VerticalUserModel? { get }
    @MainActor var scrollToTop: Bool { get set }
}


protocol UsersScrollingViewActionsProtocol: UsersInnerViewActionsProtocol {
    
}


protocol UsersScrollingViewConfigurationProtocol: UsersInnerViewConfigurationProtocol {}



fileprivate struct UsersScrollingView<Model: UsersScrollingViewModelProtocol>: View {
    
    @ObservedObject public var model: Model
    let actions: UsersScrollingViewActionsProtocol
    let configuration: UsersScrollingViewConfigurationProtocol
    //var fetchRequest: FetchRequest<Model.VerticalContactModel>
    
    var body: some View {
        if model.users.isEmpty {
            VStack {
                if let textAboveUserList = configuration.textAboveUserList {
                    List {
                        TextAboveUserListView(textAboveUserList: textAboveUserList)
                    }
                }
                Spacer()
            }
        } else {
            ScrollViewReader { scrollViewProxy in
                UsersInnerView(model: model,
                               actions: actions,
                               configuration: configuration)
                .onChange(of: model.userToScrollTo) { (_) in
                    guard let user = model.userToScrollTo else { return }
                    withAnimation {
                        scrollViewProxy.scrollTo(user)
                    }
                }
                .onChange(of: model.scrollToTop) { (_) in
                    if let firstItem = model.users.first {
                        withAnimation {
                            scrollViewProxy.scrollTo(firstItem)
                            model.scrollToTop = false
                        }
                    }
                }
            }
        }
    }
    
}


fileprivate struct TextAboveUserListView: View {
    
    let textAboveUserList: String
    
    var body: some View {
        Section {
            Text(textAboveUserList)
                .padding(4)
                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                .font(.callout)
        }
    }
    
}




// MARK: - UsersInnerView

protocol UsersInnerViewModelProtocol: ObservableObject {
    associatedtype VerticalUserModel: ManagedUserViewForVerticalUsersLayoutModelProtocol
    @MainActor var users: [VerticalUserModel] { get }
    @MainActor var tappedUser: VerticalUserModel? { get set }
    @MainActor var selectedUsers: Set<VerticalUserModel> { get }
}


protocol UsersInnerViewActionsProtocol: SelectableUserCellViewActionsProtocol {
    @MainActor func userWantsToNavigateToSingleContactIdentityView(user: any ManagedUserViewForVerticalUsersLayoutModelProtocol)
}


protocol UsersInnerViewConfigurationProtocol: SelectableUserCellViewConfiguration {
    var disableUsersWithoutDevice: Bool { get }
    var allowMultipleSelection: Bool { get }
    var textAboveUserList: String? { get }
    var selectionStyle: SelectionStyle { get }
}


fileprivate struct UsersInnerView<Model: UsersInnerViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: UsersInnerViewActionsProtocol
    let configuration: UsersInnerViewConfigurationProtocol
    //var fetchRequest: FetchRequest<Model.VerticalContactModel>

    private func userCellCanBeSelected(for user: Model.VerticalUserModel) -> Bool {
        guard configuration.allowMultipleSelection else { return false }
        if configuration.disableUsersWithoutDevice {
            return user.atLeastOneDeviceAllowsThisUserToReceiveMessages
        }
        return true
    }
    
    
    private func performOnTapGesture(user: Model.VerticalUserModel) async {
        withAnimation {
            model.tappedUser = user
        }
        try? await Task.sleep(milliseconds: 150)
        actions.userWantsToNavigateToSingleContactIdentityView(user: user)
    }
    
    private func isSelected(user: Model.VerticalUserModel) -> Bool {
        model.selectedUsers.contains(user)
    }
    
    var body: some View {
        List {
            if let textAboveUserList = configuration.textAboveUserList {
                TextAboveUserListView(textAboveUserList: textAboveUserList)
            }
            Section {
                ForEach(model.users, id: \.self) { user in
                    if configuration.allowMultipleSelection {
                        if userCellCanBeSelected(for: user) {
                            SelectableUserCellView(model: user,
                                                   actions: actions,
                                                   configuration: configuration,
                                                   isSelected: isSelected(user: user))
                        } else {
                            SingleUserViewForVerticalUsersLayout(model: user, state: .init(chevronStyle: .hidden, showDetailsStatus: false))
                        }
                    } else {
                        SingleUserViewForVerticalUsersLayout(model: user, state: .init(chevronStyle: .shown(selected: model.tappedUser == user), showDetailsStatus: true))
                            .onTapGesture {
                                Task { await performOnTapGesture(user: user) }
                            }
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                                    withAnimation {
                                        model.tappedUser = nil
                                    }
                                }
                            }
                    }
                }
            } header: {
                // Part of the trick that removes the top padding above the grouped list.
                Color.clear.frame(height: 0).listRowInsets(.init())
            } footer: {
                Rectangle()
                    .foregroundColor(.clear)
            }
        }
        .listStyle(InsetGroupedListStyle())
        // Part of the trick that removes the top padding above the grouped list.
        .environment(\.defaultMinListHeaderHeight, 0.0)
    }
    
}




// MARK: - SelectableUserCellView


enum SelectionStyle {
    case checkmark
    case multiply
}


protocol SelectableUserCellViewConfiguration {
    var selectionStyle: SelectionStyle { get }
}


protocol SelectableUserCellViewActionsProtocol {
    func userDidToggleSelectionOfUser(_ user: any ManagedUserViewForVerticalUsersLayoutModelProtocol, newIsSelected: Bool) async
}


fileprivate struct SelectableUserCellView<User: ManagedUserViewForVerticalUsersLayoutModelProtocol>: View {
        
    @ObservedObject var model: User
    let actions: SelectableUserCellViewActionsProtocol
    let configuration: SelectableUserCellViewConfiguration
    let isSelected: Bool
    
    private var imageSystemName: String {
        switch configuration.selectionStyle {
        case .checkmark: return "checkmark.circle.fill"
        case .multiply: return "multiply.circle.fill"
        }
    }
    
    private var imageColor: Color {
        switch configuration.selectionStyle {
        case .checkmark: return Color.green
        case .multiply: return Color.red
        }
    }
    
    var body: some View {
        HStack {
            SingleUserViewForVerticalUsersLayout(model: model, state: .init(chevronStyle: .hidden, showDetailsStatus: false))
            Image(systemName: isSelected ? imageSystemName : "circle")
                .font(Font.system(size: 24, weight: .regular, design: .default))
                .foregroundColor(isSelected ? imageColor : Color.gray)
                .padding(.leading)
        }
        .onTapGesture {
            Task { await actions.userDidToggleSelectionOfUser(model, newIsSelected: !isSelected) }
        }
    }
    
}
