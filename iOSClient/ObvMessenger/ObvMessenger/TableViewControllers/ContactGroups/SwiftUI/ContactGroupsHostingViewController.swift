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
import ObvEngine
import CoreData
import os.log
import ObvTypes

@available(iOS 13.0, *)
final class ContactGroupsHostingViewController: UIHostingController<GroupsView>, GroupsViewStoreDelegate {
        
    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: "ContactGroupsHostingViewController"))

    let searchController: UISearchController
    private let store: GroupsViewStore

    weak var delegate: ContactGroupsHostingViewControllerDelegate?

    init(ownedCryptoId: ObvCryptoId, delegate: ContactGroupsHostingViewControllerDelegate) {
        self.searchController = UISearchController(searchResultsController: nil)
        self.searchController.obscuresBackgroundDuringPresentation = false
        self.searchController.hidesNavigationBarDuringPresentation = true
        let store = GroupsViewStore(ownedCryptoId: ownedCryptoId)
        self.store = store
        self.searchController.searchResultsUpdater = store
        store.contactGroupsHostingViewControllerDelegate = delegate
        let view = GroupsView(store: store)
        super.init(rootView: view)
        store.delegate = self
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func selectRowOfContactGroup(_ group: PersistedContactGroup) {
        store.selectRowOfContactGroup(group)
    }

    func userWantsToSeeContactGroupDetails(of group: PersistedContactGroup) {
        delegate?.userWantsToSeeContactGroupDetails(of: group)
    }

    func scrollToTop() {
        store.scrollToTopNow()
    }
    
}


@available(iOS 13.0, *)
protocol GroupsViewStoreDelegate: AnyObject {
    func userWantsToSeeContactGroupDetails(of group: PersistedContactGroup)
}


@available(iOS 13.0, *)
fileprivate class GroupsViewStore: NSObject, ObservableObject, UISearchResultsUpdating {
    
    @Published var fetchRequest: NSFetchRequest<PersistedContactGroup>
    @Published var changed: Bool // This allows to "force" the refresh of the view
    @Published var tappedGroup: PersistedContactGroup? = nil
    @Published var scrollToTop: Bool = false
    private let ownedCryptoId: ObvCryptoId

    weak var delegate: GroupsViewStoreDelegate?
    weak var contactGroupsHostingViewControllerDelegate: ContactGroupsHostingViewControllerDelegate?

    
    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        self.fetchRequest = PersistedContactGroup.getFetchRequestForAllContactGroups(ownedIdentity: ownedCryptoId, andPredicate: nil)
        self.changed = false
        super.init()
    }
    
    fileprivate func userWantsToNavigateToSingleGroupView(_ group: PersistedContactGroup) {
        delegate?.userWantsToSeeContactGroupDetails(of: group)
    }
    
    private func refreshFetchRequest(searchText: String?) {
        let searchPredicate: NSPredicate?
        if searchText != nil {
            searchPredicate = NSPredicate(format: "%K contains[cd] %@",
                                              PersistedContactGroup.groupNameKey, searchText!)
        } else {
            searchPredicate = nil
        }
        self.fetchRequest = PersistedContactGroup.getFetchRequestForAllContactGroups(ownedIdentity: ownedCryptoId, andPredicate: searchPredicate)
    }

    func selectRowOfContactGroup(_ group: PersistedContactGroup) {
        self.tappedGroup = group
    }

    func scrollToTopNow() {
        self.scrollToTop.toggle()
        self.changed.toggle()
    }

    // UISearchResultsUpdating
    
    func updateSearchResults(for searchController: UISearchController) {
        if let searchedText = searchController.searchBar.text, !searchedText.isEmpty {
            refreshFetchRequest(searchText: searchedText)
        } else {
            refreshFetchRequest(searchText: nil)
        }
    }

}


@available(iOS 13.0, *)
struct GroupsView: View {
    
    @ObservedObject fileprivate var store: GroupsViewStore
    
    var body: some View {
        GroupsScrollingView(nsFetchRequest: store.fetchRequest,
                            changed: $store.changed,
                            userWantsToNavigateToSingleGroupView: store.userWantsToNavigateToSingleGroupView,
                            tappedGroup: $store.tappedGroup,
                            scrollToTop: $store.scrollToTop)
            .environment(\.managedObjectContext, ObvStack.shared.viewContext)
    }
    
}


@available(iOS 13.0, *)
fileprivate struct GroupsScrollingView: View {
    
    let nsFetchRequest: NSFetchRequest<PersistedContactGroup>
    @Binding var changed: Bool
    let userWantsToNavigateToSingleGroupView: (PersistedContactGroup) -> Void
    @Binding var tappedGroup: PersistedContactGroup?
    @Binding var scrollToTop: Bool

    var body: some View {
        if #available(iOS 14.0, *) {
            ScrollViewReader { scrollViewProxy in
                GroupsInnerViewList(nsFetchRequest: nsFetchRequest,
                                    changed: $changed,
                                    userWantsToNavigateToSingleGroupView: userWantsToNavigateToSingleGroupView,
                                    tappedGroup: $tappedGroup)
                    .onChange(of: scrollToTop) { (_) in
                        if let firstItem = try? ObvStack.shared.viewContext.fetch(nsFetchRequest).first {
                            withAnimation {
                                scrollViewProxy.scrollTo(firstItem)
                                scrollToTop = false
                            }
                        }
                    }
            }
        } else {
            GroupsInnerViewList(nsFetchRequest: nsFetchRequest,
                                changed: $changed,
                                userWantsToNavigateToSingleGroupView: userWantsToNavigateToSingleGroupView,
                                tappedGroup: $tappedGroup)
        }
    }
    
}


@available(iOS 13.0, *)
fileprivate struct GroupsInnerViewList: View {
    
    var fetchRequest: FetchRequest<PersistedContactGroup>
    @Binding var changed: Bool
    let userWantsToNavigateToSingleGroupView: (PersistedContactGroup) -> Void
    @Binding var tappedGroup: PersistedContactGroup?

    init(nsFetchRequest: NSFetchRequest<PersistedContactGroup>, changed: Binding<Bool>, userWantsToNavigateToSingleGroupView: @escaping (PersistedContactGroup) -> Void, tappedGroup: Binding<PersistedContactGroup?>) {
        self.fetchRequest = FetchRequest(fetchRequest: nsFetchRequest)
        self._changed = changed
        self.userWantsToNavigateToSingleGroupView = userWantsToNavigateToSingleGroupView
        self._tappedGroup = tappedGroup
    }
    
    private func sectionize(_ results: FetchedResults<PersistedContactGroup>) -> [PersistedContactGroup.Category: [FetchedResults<PersistedContactGroup>.Element]] {
        Dictionary(grouping: results) { $0.category }
    }
    
    private func textForCategory(_ category: PersistedContactGroup.Category) -> Text {
        switch category {
        case .owned: return Text("Groups created")
        case .joined: return Text("Groups joined")
        }
    }
    
    var body: some View {
        let sectionizedResults = sectionize(fetchRequest.wrappedValue)
        List {
            ForEach([PersistedContactGroup.Category.owned, PersistedContactGroup.Category.joined], id: \.self) { category in
                if let resultsInCategory = sectionizedResults[category] {
                    Section(header: textForCategory(category)) {
                        ForEach(resultsInCategory, id: \.self) { group in
                            GroupCellView(group: group, showChevron: true, selected: tappedGroup == group)
                                .padding(.vertical, 4)
                                .onTapGesture {
                                    withAnimation {
                                        tappedGroup = group
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                                        userWantsToNavigateToSingleGroupView(group)
                                    }
                                }
                                .onAppear {
                                    withAnimation {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                                            tappedGroup = nil
                                        }
                                    }
                                }
                        }
                    }
                }
            }
        }
        .obvListStyle()
    }
    
}


@available(iOS 13.0, *)
struct GroupCellView: View {

    @ObservedObject var group: PersistedContactGroup
    let showChevron: Bool
    let selected: Bool

    private var data: ContactGroup { ContactGroup(persistedContactGroup: group) }
    
    var body: some View {
        HStack {
            GroupCardContentView(model: data)
            Spacer()
            if showChevron {
                if let joinedGroup = group as? PersistedContactGroupJoined {
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
                ObvChevron(selected: selected)
            }
        }
        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
    }

}
