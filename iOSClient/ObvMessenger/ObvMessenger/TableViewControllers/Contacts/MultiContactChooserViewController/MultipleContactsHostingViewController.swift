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

import CoreData
import os.log
import ObvEngine
import ObvTypes
import ObvUI
import ObvUICoreData
import SwiftUI
import UI_SystemIcon
import UI_SystemIcon_SwiftUI
import ObvDesignSystem
import ObvSettings


final class MultipleContactsHostingViewController: UIHostingController<ContactsView>, ContactsViewStoreDelegate {

    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "MultipleContactsHostingViewController")

    let searchController: UISearchController
    private let store: ContactsViewStore
    
    weak var delegate: MultipleContactsHostingViewControllerDelegate?
    
    init(ownedCryptoId: ObvCryptoId, mode: MultipleContactsMode, disableContactsWithoutDevice: Bool, allowMultipleSelection: Bool, showExplanation: Bool, selectionStyle: SelectionStyle? = nil, textAboveContactList: String?, floatingButtonModel: FloatingButtonModel? = nil, delegate: MultiContactChooserViewControllerDelegate? = nil) {
        if allowMultipleSelection { assert(delegate != nil) }
        self.searchController = UISearchController(searchResultsController: nil)
        self.searchController.obscuresBackgroundDuringPresentation = false
        self.searchController.hidesNavigationBarDuringPresentation = true
        let store = ContactsViewStore(ownedCryptoId: ownedCryptoId,
                                      mode: mode,
                                      disableContactsWithoutDevice: disableContactsWithoutDevice,
                                      allowMultipleSelection: allowMultipleSelection,
                                      showExplanation: showExplanation,
                                      selectionStyle: selectionStyle,
                                      textAboveContactList: textAboveContactList,
                                      floatingButtonModel: floatingButtonModel)
        self.store = store
        self.searchController.searchResultsUpdater = store
        store.multiContactChooserDelegate = delegate
        let view = ContactsView(store: store)
        super.init(rootView: view)
        store.delegate = self
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    
    @objc
    func dismissPresentedViewController() {
        presentedViewController?.dismiss(animated: true)
    }

    func selectRowOfContactIdentity(_ contactIdentity: PersistedObvContactIdentity) {
        store.selectRowOfContactIdentity(contactIdentity)
    }

    func scrollToTop() {
        store.scrollToTopNow()
    }

    func setFloatingButtonEnable(to isEnabled: Bool) {
        store.setFloatingButtonEnable(to: isEnabled)

    }
    
    // MARK: - Implementing ContactsViewStoreDelegate

    func userWantsToSeeContactDetails(of contact: PersistedObvContactIdentity) {
        assert(Thread.isMainThread)
        delegate?.userWantsToSeeContactDetails(of: contact)
    }
    
}


enum MultipleContactsMode {
    case restricted(to: Set<ObvCryptoId>, oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus)
    case excluded(from: Set<ObvCryptoId>, oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus, requiredCapabilitites: [ObvCapability]?)
    case all(oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus, requiredCapabilitites: [ObvCapability]?)
    
    var oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus {
        switch self {
        case .restricted(to: _, oneToOneStatus: let oneToOneStatus),
                .excluded(from: _, oneToOneStatus: let oneToOneStatus, requiredCapabilitites: _),
                .all(oneToOneStatus: let oneToOneStatus, requiredCapabilitites: _):
            return oneToOneStatus
        }
    }
}

extension MultipleContactsMode {

    func predicate(with ownedCryptoId: ObvCryptoId) -> NSPredicate {
        switch self {
        case .restricted(to: let restrictedToContactCryptoIds, oneToOneStatus: let oneToOneStatus):
            return PersistedObvContactIdentity.getPredicateForAllContactsOfOwnedIdentity(with: ownedCryptoId, restrictedToContactCryptoIds: restrictedToContactCryptoIds, whereOneToOneStatusIs: oneToOneStatus)
        case .excluded(from: let excludedContactCryptoIds, oneToOneStatus: let oneToOneStatus, requiredCapabilitites: let requiredCapabilitites):
            if excludedContactCryptoIds.isEmpty { /// Should be .all
                return PersistedObvContactIdentity.getPredicateForAllContactsOfOwnedIdentity(
                    with: ownedCryptoId,
                    whereOneToOneStatusIs: oneToOneStatus,
                    requiredCapabilities: requiredCapabilitites)
            } else {
                return PersistedObvContactIdentity.getPredicateForAllContactsOfOwnedIdentity(
                    with: ownedCryptoId,
                    excludedContactCryptoIds: excludedContactCryptoIds,
                    whereOneToOneStatusIs: oneToOneStatus,
                    requiredCapabilities: requiredCapabilitites ?? [])
            }
        case .all(oneToOneStatus: let oneToOneStatus, requiredCapabilitites: let requiredCapabilitites):
            return PersistedObvContactIdentity.getPredicateForAllContactsOfOwnedIdentity(
                with: ownedCryptoId,
                whereOneToOneStatusIs: oneToOneStatus,
                requiredCapabilities: requiredCapabilitites)
        }
    }
}

enum MultipleContactsButton {
    case done(_: String? = nil)
    case system(_: SystemIcon)
    case floating(title: String, systemIcon: SystemIcon?) // Cannot be used with UIKit
}

final class MultipleContactsViewController: UIViewController, MultiContactChooserViewControllerDelegate {

    let ownedCryptoId: ObvCryptoId
    let mode: MultipleContactsMode
    let button: MultipleContactsButton
    let defaultSelectedContacts: Set<PersistedObvContactIdentity>
    let disableContactsWithoutDevice: Bool
    let allowMultipleSelection: Bool
    let showExplanation: Bool
    let allowEmptySetOfContacts: Bool
    let textAboveContactList: String?
    var selectionStyle: SelectionStyle? = nil

    var doneAction: (Set<PersistedObvContactIdentity>) -> Void
    var dismissAction: () -> Void

    var selectedContacts: Set<PersistedObvContactIdentity>

    private var doneButtonItem: BlockBarButtonItem?
    private var contactsViewController: MultipleContactsHostingViewController?

    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    init(ownedCryptoId: ObvCryptoId, mode: MultipleContactsMode, button: MultipleContactsButton, defaultSelectedContacts: Set<PersistedObvContactIdentity> = Set(), disableContactsWithoutDevice: Bool, allowMultipleSelection: Bool, showExplanation: Bool, allowEmptySetOfContacts: Bool, textAboveContactList: String?, selectionStyle: SelectionStyle? = nil, doneAction: @escaping (Set<PersistedObvContactIdentity>) -> Void, dismissAction: @escaping () -> Void) {

        self.ownedCryptoId = ownedCryptoId
        self.mode = mode
        self.button = button
        self.defaultSelectedContacts = defaultSelectedContacts
        self.disableContactsWithoutDevice = disableContactsWithoutDevice
        self.allowMultipleSelection = allowMultipleSelection
        self.showExplanation = showExplanation
        self.selectionStyle = selectionStyle
        self.doneAction = doneAction
        self.dismissAction = dismissAction
        self.selectedContacts = Set()
        self.allowEmptySetOfContacts = allowEmptySetOfContacts
        self.textAboveContactList = textAboveContactList
        super.init(nibName: nil, bundle: nil)
    }

    var floatingButtonModel: FloatingButtonModel? {
        guard case let .floating(title, icon) = button else { return nil }
        return FloatingButtonModel(title: title, systemIcon: icon, isEnabled: isDoneButtonEnabled) {
            self.doneAction(self.selectedContacts)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setUserContactSelection(to: defaultSelectedContacts)
        let vc = MultipleContactsHostingViewController(ownedCryptoId: ownedCryptoId,
                                                       mode: mode,
                                                       disableContactsWithoutDevice: disableContactsWithoutDevice,
                                                       allowMultipleSelection: true,
                                                       showExplanation: false,
                                                       selectionStyle: .checkmark,
                                                       textAboveContactList: textAboveContactList,
                                                       floatingButtonModel: floatingButtonModel,
                                                       delegate: self)
        contactsViewController = vc
        self.navigationItem.searchController = vc.searchController
        switch button {
        case .done(let text):
            if let text = text {
                doneButtonItem = BlockBarButtonItem(title: text, style: .done) { [weak self] in
                    guard let _self = self else { return }
                    _self.doneAction(_self.selectedContacts)
                }
            } else {
                doneButtonItem = BlockBarButtonItem(barButtonSystemItem: .done) { [weak self] in
                    guard let _self = self else { return }
                    _self.doneAction(_self.selectedContacts)
                }
            }
        case .system(let systemIcon):
            doneButtonItem = BlockBarButtonItem(systemIcon: systemIcon) { [weak self] in
                guard let _self = self else { return }
                _self.doneAction(_self.selectedContacts)
            }
        case .floating:
            break
        }
        doneButtonItem?.isEnabled = allowEmptySetOfContacts || !selectedContacts.isEmpty
        self.navigationItem.setRightBarButton(doneButtonItem, animated: false)
        let cancelButtonItem = BlockBarButtonItem.forClosing { [weak self] in
            self?.dismissAction()
        }
        self.navigationItem.setLeftBarButton(cancelButtonItem, animated: false)
        self.navigationItem.hidesSearchBarWhenScrolling = false

        if let contactsViewController = contactsViewController {
            displayContentController(content: contactsViewController)
        }
    }


    func userDidSelect(_ contact: PersistedObvContactIdentity) {
        selectedContacts.insert(contact)
        updateParentNavigationItem()
    }

    func userDidDeselect(_ contact: PersistedObvContactIdentity) {
        selectedContacts.remove(contact)
        updateParentNavigationItem()
    }

    func setUserContactSelection(to selection: Set<PersistedObvContactIdentity>) {
        selectedContacts = selection
        updateParentNavigationItem()
    }

    var isDoneButtonEnabled: Bool {
        allowEmptySetOfContacts || !selectedContacts.isEmpty
    }

    func updateParentNavigationItem() {
        if let doneButtonItem = doneButtonItem {
            doneButtonItem.isEnabled = isDoneButtonEnabled
        }
        contactsViewController?.setFloatingButtonEnable(to: isDoneButtonEnabled)
    }

}


struct MultipleContactsView: UIViewControllerRepresentable {

    let ownedCryptoId: ObvCryptoId?
    let mode: MultipleContactsMode
    let button: MultipleContactsButton
    let disableContactsWithoutDevice: Bool
    let allowMultipleSelection: Bool
    let showExplanation: Bool
    let allowEmptySetOfContacts: Bool
    let textAboveContactList: String?
    var selectionStyle: SelectionStyle? = nil
    var doneAction: (Set<PersistedObvContactIdentity>) -> Void
    var dismissAction: () -> Void

    private var doneButtonItem: BlockBarButtonItem?

    func makeCoordinator() -> Coordinator {
        Coordinator(allowEmptySetOfContacts: allowEmptySetOfContacts)
    }

    init(ownedCryptoId: ObvCryptoId?, mode: MultipleContactsMode, button: MultipleContactsButton, disableContactsWithoutDevice: Bool, allowMultipleSelection: Bool, showExplanation: Bool, allowEmptySetOfContacts: Bool, textAboveContactList: String?, selectionStyle: SelectionStyle? = nil, doneAction: @escaping (Set<PersistedObvContactIdentity>) -> Void, dismissAction: @escaping () -> Void) {
        self.ownedCryptoId = ownedCryptoId
        self.mode = mode
        self.button = button
        self.disableContactsWithoutDevice = disableContactsWithoutDevice
        self.allowMultipleSelection = allowMultipleSelection
        self.showExplanation = showExplanation
        self.allowEmptySetOfContacts = allowEmptySetOfContacts
        self.selectionStyle = selectionStyle
        self.doneAction = doneAction
        self.dismissAction = dismissAction
        self.textAboveContactList = textAboveContactList
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<MultipleContactsView>) -> UINavigationController {
        var doneButtonItem: BlockBarButtonItem?
        var floatingButtonModel: FloatingButtonModel?
        switch button {
        case .done(let text):
            if let text = text {
                doneButtonItem = BlockBarButtonItem(title: text, style: .done) {
                    doneAction(context.coordinator.selectedContacts)
                }
            } else {
                doneButtonItem = BlockBarButtonItem(barButtonSystemItem: .done) {
                    doneAction(context.coordinator.selectedContacts)
                }
            }
        case .system(let systemIcon):
            doneButtonItem = BlockBarButtonItem(systemIcon: systemIcon) {
                doneAction(context.coordinator.selectedContacts)
            }
        case .floating(let title, let icon):
            floatingButtonModel = FloatingButtonModel(title: title, systemIcon: icon, isEnabled: true) {
                self.doneAction(context.coordinator.selectedContacts)
            }
        }
        guard let ownedCryptoId = ownedCryptoId else { return UINavigationController() }
        let vc = MultipleContactsHostingViewController(ownedCryptoId: ownedCryptoId,
                                                       mode: mode,
                                                       disableContactsWithoutDevice: disableContactsWithoutDevice,
                                                       allowMultipleSelection: allowMultipleSelection,
                                                       showExplanation: showExplanation,
                                                       selectionStyle: selectionStyle,
                                                       textAboveContactList: textAboveContactList,
                                                       floatingButtonModel: floatingButtonModel,
                                                       delegate: context.coordinator)
        context.coordinator.doneButtonItem = doneButtonItem
        context.coordinator.contactsViewController = vc

        vc.navigationItem.searchController = vc.searchController
        let nav = UINavigationController(rootViewController: vc)

        vc.navigationItem.setRightBarButton(doneButtonItem, animated: false)
        let cancelButtonItem = BlockBarButtonItem.forClosing {
            dismissAction()
        }
        vc.navigationItem.setLeftBarButton(cancelButtonItem, animated: false)
        vc.navigationItem.hidesSearchBarWhenScrolling = false

        context.coordinator.updateParentNavigationItem()

        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: UIViewControllerRepresentableContext<MultipleContactsView>) {
    }

    class Coordinator: NSObject, MultiContactChooserViewControllerDelegate {
        var selectedContacts: Set<PersistedObvContactIdentity>
        var allowEmptySetOfContacts: Bool

        func userDidSelect(_ contact: PersistedObvContactIdentity) {
            selectedContacts.insert(contact)
            updateParentNavigationItem()
        }

        func userDidDeselect(_ contact: PersistedObvContactIdentity) {
            selectedContacts.remove(contact)
            updateParentNavigationItem()
        }

        func setUserContactSelection(to selection: Set<PersistedObvContactIdentity>) {
            selectedContacts = selection
            updateParentNavigationItem()
        }

        var isDoneButtonEnabled: Bool {
            allowEmptySetOfContacts || !selectedContacts.isEmpty
        }

        func updateParentNavigationItem() {
            if let buttonItem = doneButtonItem {
                buttonItem.isEnabled = isDoneButtonEnabled
            }
            if let vc = contactsViewController {
                vc.setFloatingButtonEnable(to: isDoneButtonEnabled)
            }
        }

        weak var doneButtonItem: UIBarButtonItem?
        weak var contactsViewController: MultipleContactsHostingViewController?

        init(allowEmptySetOfContacts: Bool) {
            self.selectedContacts = Set()
            self.allowEmptySetOfContacts = allowEmptySetOfContacts
            super.init()
        }
    }
}


protocol ContactsViewStoreDelegate: AnyObject {
    func userWantsToSeeContactDetails(of contact: PersistedObvContactIdentity)
}



public class ContactsViewStore: NSObject, ObservableObject, UISearchResultsUpdating {

    @Published var fetchRequest: NSFetchRequest<PersistedObvContactIdentity>
    @Published var changed: Bool // This allows to "force" the refresh of the view
    @Published var tappedContact: PersistedObvContactIdentity? = nil
    @Published var contactToScrollTo: PersistedObvContactIdentity? = nil
    @Published var scrollToTop: Bool = false
    @Published var showSortingSpinner: Bool
    @Published var floatingButtonModel: FloatingButtonModel?
    @Published var searchInProgress: Bool = false
    let textAboveContactList: String?
    let selectionStyle: SelectionStyle

    let allowMultipleSelection: Bool
    let disableContactsWithoutDevice: Bool
    let showExplanation: Bool
    private let ownedCryptoId: ObvCryptoId
    private let initialPredicate: NSPredicate
    private(set) var selectedContacts: Binding<Set<PersistedObvContactIdentity>>!

    let mode: MultipleContactsMode

    weak var delegate: ContactsViewStoreDelegate?
    weak var multiContactChooserDelegate: MultiContactChooserViewControllerDelegate?

    private var notificationTokens = [NSObjectProtocol]()

    init(ownedCryptoId: ObvCryptoId, mode: MultipleContactsMode, disableContactsWithoutDevice: Bool, allowMultipleSelection: Bool, showExplanation: Bool, selectionStyle: SelectionStyle? = nil, textAboveContactList: String?, floatingButtonModel: FloatingButtonModel? = nil) {
        assert(Thread.isMainThread)
        self.disableContactsWithoutDevice = disableContactsWithoutDevice
        self.mode = mode
        self.allowMultipleSelection = allowMultipleSelection
        self.showExplanation = showExplanation
        self.ownedCryptoId = ownedCryptoId
        self.initialPredicate = mode.predicate(with: ownedCryptoId)
        self.fetchRequest = PersistedObvContactIdentity.getFetchRequestForAllContactsOfOwnedIdentity(with: ownedCryptoId, predicate: self.initialPredicate, whereOneToOneStatusIs: mode.oneToOneStatus)
        self.changed = false
        self.selectedContacts = nil
        self.selectionStyle = selectionStyle ?? .checkmark
        self.showSortingSpinner = false
        self.floatingButtonModel = floatingButtonModel
        self.textAboveContactList = textAboveContactList
        super.init()
        self.selectedContacts = Binding(get: getSelectedContacts, set: setSelectedContacts)
        refreshFetchRequestWhenSortOrderChanges()
    }

    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// This method allows to make sure that the contacts are properly sorted. It is only required for long list of contacts.
    /// Indeed, when the list is short, the change on the sort key performed by the sorting operations forces the request to update
    /// the loaded contacts and thus to display these contacts in the appropriate order. But with a long list of contact this is not enough.
    /// Since there is no way to force the request to refresh itself, we "hack" it here: when a new sort order is observed, we hide the list of contacts,
    /// and perform a search that is likely to return no result. Soon after we cancel the search and display the list again. This seems to work, but
    /// this is clearely an ugly hack.
    private func refreshFetchRequestWhenSortOrderChanges() {
        notificationTokens.append(ObvMessengerSettingsNotifications.observeContactsSortOrderDidChange { [weak self] in
            DispatchQueue.main.async {
                withAnimation {
                    self?.showSortingSpinner = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
                    self?.refreshFetchRequest(searchText: String(repeating: " ", count: 100))
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
                        self?.refreshFetchRequest(searchText: nil)
                        withAnimation {
                            self?.showSortingSpinner = false
                        }
                    }
                }
            }
        })
    }
    
    
    private func refreshFetchRequest(searchText: String?) {
        let searchPredicate: NSPredicate?
        if searchText != nil {
            searchPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "%K contains[cd] %@", PersistedObvContactIdentity.Predicate.Key.fullDisplayName.rawValue, searchText!),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "%K != nil", PersistedObvContactIdentity.Predicate.Key.customDisplayName.rawValue),
                    NSPredicate(format: "%K contains[cd] %@", PersistedObvContactIdentity.Predicate.Key.customDisplayName.rawValue, searchText!),
                ])
            ])
        } else {
            searchPredicate = nil
        }
        let predicate = mode.predicate(with: ownedCryptoId)
        self.fetchRequest = PersistedObvContactIdentity.getFetchRequestForAllContactsOfOwnedIdentity(with: ownedCryptoId, predicate: predicate, and: searchPredicate, whereOneToOneStatusIs: mode.oneToOneStatus)
    }
    
    private func getSelectedContacts() -> Set<PersistedObvContactIdentity> {
        return multiContactChooserDelegate?.selectedContacts ?? Set()
    }
    
    private func setSelectedContacts(_ selection: Set<PersistedObvContactIdentity>) {
        assert(multiContactChooserDelegate != nil)
        multiContactChooserDelegate?.setUserContactSelection(to: selection)
        withAnimation {
            changed.toggle()
        }
    }
    
    func userWantsToNavigateToSingleContactIdentityView(_ contact: PersistedObvContactIdentity) {
        assert(delegate != nil)
        delegate?.userWantsToSeeContactDetails(of: contact)
    }

    func selectRowOfContactIdentity(_ contactIdentity: PersistedObvContactIdentity) {
        self.contactToScrollTo = contactIdentity
        self.tappedContact = contactIdentity
    }
    
    func scrollToTopNow() {
        self.scrollToTop.toggle()
        self.changed.toggle()
    }

    func setFloatingButtonEnable(to isEnabled: Bool) {
        assert(Thread.isMainThread)
        self.floatingButtonModel?.isEnabled = isEnabled
        self.changed.toggle()
    }


    // UISearchResultsUpdating
    
    public func updateSearchResults(for searchController: UISearchController) {
        if let searchedText = searchController.searchBar.text, !searchedText.isEmpty {
            refreshFetchRequest(searchText: searchedText)
        } else {
            refreshFetchRequest(searchText: nil)
        }
        self.searchInProgress = searchController.isActive
    }
}



public struct ContactsView: View {
    
    @ObservedObject public var store: ContactsViewStore
    
    public var body: some View {
        ContactsScrollingViewOrExplanationView(store: store)
            .environment(\.managedObjectContext, ObvStack.shared.viewContext)
    }
    
}



struct ContactsScrollingViewOrExplanationView: View {
    
    @ObservedObject fileprivate var store: ContactsViewStore
    private var fetchRequest: FetchRequest<PersistedObvContactIdentity>
    
    fileprivate init(store: ContactsViewStore) {
        self.store = store
        self.fetchRequest = FetchRequest(fetchRequest: store.fetchRequest)
    }


    var body: some View {
        if store.showSortingSpinner {
            ProgressView()
        } else if store.showExplanation && fetchRequest.wrappedValue.isEmpty {
            if store.searchInProgress {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView.search
                }
            } else {
                ObvContentUnavailableView("CONTENT_UNAVAILABLE_CONTACTS_TEXT", systemIcon: .person, description: Text("CONTENT_UNAVAILABLE_CONTACTS_DESCRIPTION"))
            }
        } else {
            ContactsScrollingView(nsFetchRequest: store.fetchRequest,
                                  multipleSelection: store.selectedContacts,
                                  changed: $store.changed,
                                  allowMultipleSelection: store.allowMultipleSelection,
                                  disableContactsWithoutDevice: store.disableContactsWithoutDevice,
                                  userWantsToNavigateToSingleContactIdentityView: store.userWantsToNavigateToSingleContactIdentityView,
                                  tappedContact: $store.tappedContact,
                                  contactToScrollTo: $store.contactToScrollTo,
                                  scrollToTop: $store.scrollToTop,
                                  selectionStyle: store.selectionStyle,
                                  floatingButtonModel: store.floatingButtonModel,
                                  textAboveContactList: store.textAboveContactList)
        }
    }

}


/// This intermediary view allows to consider both iOS13 and iOS14 cases. Only iOS14 supports ScrollViewReader...

fileprivate struct ContactsScrollingView: View {
    
    let nsFetchRequest: NSFetchRequest<PersistedObvContactIdentity>
    @Binding var multipleSelection: Set<PersistedObvContactIdentity>
    @Binding var changed: Bool
    let allowMultipleSelection: Bool
    let disableContactsWithoutDevice: Bool
    let userWantsToNavigateToSingleContactIdentityView: (PersistedObvContactIdentity) -> Void
    @Binding var tappedContact: PersistedObvContactIdentity?
    @Binding var contactToScrollTo: PersistedObvContactIdentity?
    @Binding var scrollToTop: Bool
    fileprivate let selectionStyle: SelectionStyle
    let floatingButtonModel: FloatingButtonModel?
    let textAboveContactList: String?
    private var fetchRequest: FetchRequest<PersistedObvContactIdentity>

    
    init(nsFetchRequest: NSFetchRequest<PersistedObvContactIdentity>, multipleSelection: Binding<Set<PersistedObvContactIdentity>>, changed: Binding<Bool>, allowMultipleSelection: Bool, disableContactsWithoutDevice: Bool, userWantsToNavigateToSingleContactIdentityView: @escaping (PersistedObvContactIdentity) -> Void, tappedContact: Binding<PersistedObvContactIdentity?>, contactToScrollTo: Binding<PersistedObvContactIdentity?>, scrollToTop: Binding<Bool>, selectionStyle: SelectionStyle, floatingButtonModel: FloatingButtonModel?, textAboveContactList: String?) {
        self.nsFetchRequest = nsFetchRequest
        self._multipleSelection = multipleSelection
        self._changed = changed
        self.allowMultipleSelection = allowMultipleSelection
        self.disableContactsWithoutDevice = disableContactsWithoutDevice
        self.userWantsToNavigateToSingleContactIdentityView = userWantsToNavigateToSingleContactIdentityView
        self._tappedContact = tappedContact
        self._contactToScrollTo = contactToScrollTo
        self._scrollToTop = scrollToTop
        self.selectionStyle = selectionStyle
        self.floatingButtonModel = floatingButtonModel
        self.textAboveContactList = textAboveContactList
        self.fetchRequest = FetchRequest(fetchRequest: nsFetchRequest)
    }

    
    var innerView: some View {
        ContactsInnerView(nsFetchRequest: nsFetchRequest,
                          multipleSelection: $multipleSelection,
                          changed: $changed,
                          allowMultipleSelection: allowMultipleSelection,
                          disableContactsWithoutDevice: disableContactsWithoutDevice,
                          userWantsToNavigateToSingleContactIdentityView: userWantsToNavigateToSingleContactIdentityView,
                          tappedContact: $tappedContact,
                          selectionStyle: selectionStyle,
                          addBottomPadding: floatingButtonModel != nil,
                          textAboveContactList: textAboveContactList)
    }

    
    var body: some View {
        ZStack {
            if fetchRequest.wrappedValue.isEmpty {
                VStack {
                    if let textAboveContactList {
                        List {
                            TextAboveContactListView(textAboveContactList: textAboveContactList)
                        }
                    }
                    Spacer()
                }
            } else {
                ScrollViewReader { scrollViewProxy in
                    innerView
                        .onChange(of: contactToScrollTo) { (_) in
                            guard let contact = contactToScrollTo else { return }
                            withAnimation {
                                scrollViewProxy.scrollTo(contact)
                            }
                        }
                        .onChange(of: scrollToTop) { (_) in
                            if let firstItem = try? ObvStack.shared.viewContext.fetch(nsFetchRequest).first {
                                withAnimation {
                                    scrollViewProxy.scrollTo(firstItem)
                                    scrollToTop = false
                                }
                            }
                        }
                }
            }
            if let floatingButtonModel {
                FloatingButtonView(model: floatingButtonModel)
            }
        }
    }
    
}


fileprivate struct TextAboveContactListView: View {
    
    let textAboveContactList: String
    
    var body: some View {
        Section {
            Text(textAboveContactList)
                .padding(4)
                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                .font(.callout)
        }
    }
    
}



fileprivate struct ContactsInnerView: View {
    
    var fetchRequest: FetchRequest<PersistedObvContactIdentity>
    @Binding var multipleSelection: Set<PersistedObvContactIdentity>
    @Binding var changed: Bool
    let allowMultipleSelection: Bool
    let disableContactsWithoutDevice: Bool
    let userWantsToNavigateToSingleContactIdentityView: (PersistedObvContactIdentity) -> Void
    @Binding var tappedContact: PersistedObvContactIdentity?
    fileprivate let selectionStyle: SelectionStyle
    let addBottomPadding: Bool
    let textAboveContactList: String?

    init(nsFetchRequest: NSFetchRequest<PersistedObvContactIdentity>, multipleSelection: Binding<Set<PersistedObvContactIdentity>>, changed: Binding<Bool>, allowMultipleSelection: Bool, disableContactsWithoutDevice: Bool, userWantsToNavigateToSingleContactIdentityView: @escaping (PersistedObvContactIdentity) -> Void, tappedContact: Binding<PersistedObvContactIdentity?>, selectionStyle: SelectionStyle, addBottomPadding: Bool, textAboveContactList: String?) {
        self.fetchRequest = FetchRequest(fetchRequest: nsFetchRequest)
        self._multipleSelection = multipleSelection
        self._changed = changed
        self.allowMultipleSelection = allowMultipleSelection
        self.disableContactsWithoutDevice = disableContactsWithoutDevice
        self.userWantsToNavigateToSingleContactIdentityView = userWantsToNavigateToSingleContactIdentityView
        self._tappedContact = tappedContact
        self.selectionStyle = selectionStyle
        self.addBottomPadding = addBottomPadding
        self.textAboveContactList = textAboveContactList
    }
    
    private func contactCellCanBeSelected(for contact: PersistedObvContactIdentity) -> Bool {
        guard allowMultipleSelection else { return false }
        if disableContactsWithoutDevice {
            guard !contact.devices.isEmpty else { return false }
        }
        return true
    }
    
    var body: some View {
        List {
            if let textAboveContactList {
                TextAboveContactListView(textAboveContactList: textAboveContactList)
            }
            Section {
                ForEach(fetchRequest.wrappedValue, id: \.self) { contact in
                    if allowMultipleSelection {
                        if contactCellCanBeSelected(for: contact) {
                            SelectableContactCellView(selection: $multipleSelection, contact: contact, selectionStyle: selectionStyle)
                        } else {
                            ContactCellView(model: contact, state: .init(chevronStyle: .hidden, showDetailsStatus: false))
                        }
                    } else {
                        ContactCellView(model: contact, state: .init(chevronStyle: .shown(selected: tappedContact == contact), showDetailsStatus: true))
                            .onTapGesture {
                                withAnimation(Animation.easeIn(duration: 0.1)) {
                                    tappedContact = contact
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                                    userWantsToNavigateToSingleContactIdentityView(contact)
                                }
                            }
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                                    withAnimation {
                                        tappedContact = nil
                                    }
                                }
                            }
                    }
                }
            } footer: {
                Rectangle()
                    .frame(height: addBottomPadding ? 40 : 0)
                    .foregroundColor(.clear)
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
    
}


enum SelectionStyle {
    case checkmark
    case multiply
}



fileprivate struct SelectableContactCellView: View {
        
    @Binding var selection: Set<PersistedObvContactIdentity>
    var contact: PersistedObvContactIdentity
    fileprivate let selectionStyle: SelectionStyle

    var imageSystemName: String {
        switch selectionStyle {
        case .checkmark: return "checkmark.circle.fill"
        case .multiply: return "multiply.circle.fill"
        }
    }
    
    var imageColor: Color {
        switch selectionStyle {
        case .checkmark: return Color.green
        case .multiply: return Color.red
        }
    }
    
    var body: some View {
        HStack {
            ContactCellView(model: contact, state: .init(chevronStyle: .hidden, showDetailsStatus: false))
            Image(systemName: selection.contains(contact) ? imageSystemName : "circle")
                .font(Font.system(size: 24, weight: .regular, design: .default))
                .foregroundColor(selection.contains(contact) ? imageColor : Color.gray)
                .padding(.leading)
        }
        .onTapGesture {
            if selection.contains(contact) {
                selection.remove(contact)
            } else {
                selection.insert(contact)
            }
        }
    }
    
}
