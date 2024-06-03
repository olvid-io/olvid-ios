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

import UIKit
import OSLog
import ObvTypes
import SwiftUI
import ObvUICoreData


protocol ContactsSelectionForGroupHostingViewControllerDelegate: AnyObject {
    func userDidValidateSelectedContacts(in controller: ContactsSelectionForGroupHostingViewController, selectedContacts: [PersistedObvContactIdentity]) async
    func userWantsToCancelGroupCreationFlow(in controller: ContactsSelectionForGroupHostingViewController)
}


final class ContactsSelectionForGroupHostingViewController: UIHostingController<ContactsSelectionForGroupView>, ContactsSelectionForGroupViewActions {
    
    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "GroupContactsHostingViewController")
    let searchController: UISearchController
    private let mode: Mode
    
    weak var delegate: ContactsSelectionForGroupHostingViewControllerDelegate?
    
    var viewModel: GroupContactsViewModel
    
    enum Mode {
        case modify
        case create
    }
    
    init(ownedCryptoId: ObvCryptoId, mode: Mode, preSelectedContacts: Set<PersistedObvContactIdentity>, delegate: ContactsSelectionForGroupHostingViewControllerDelegate?) {
        
        self.searchController = UISearchController(searchResultsController: nil)
        
        self.mode = mode
        
        let store = ContactsViewStore(ownedCryptoId: ownedCryptoId,
                                      mode: .all(oneToOneStatus: .any, requiredCapabilitites: [.groupsV2]),
                                      disableContactsWithoutDevice: true,
                                      allowMultipleSelection: true,
                                      showExplanation: false,
                                      selectionStyle: nil,
                                      textAboveContactList: nil,
                                      floatingButtonModel: nil)
        
        self.viewModel = GroupContactsViewModel(store: store, preSelectedContacts: preSelectedContacts)
        self.searchController.searchResultsUpdater = store
        
        let actions = Actions()
        
        let view = ContactsSelectionForGroupView(viewModel: viewModel, actions: actions)
        super.init(rootView: view)
        
        actions.delegate = self
        self.delegate = delegate
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .systemGroupedBackground
        
        switch mode {
        case .modify:
            self.navigationItem.title = Strings.updateGroupTitle
        case .create:
            self.navigationItem.title = Strings.newGroupTitle
        }

        configureSearchBar()
        
        self.navigationItem.rightBarButtonItem = .init(systemItem: .cancel, primaryAction: .init(handler: { [weak self] _ in
            guard let self else { return }
            delegate?.userWantsToCancelGroupCreationFlow(in: self)
        }))
        
    }
    
    
    private func configureSearchBar() {
        
        self.searchController.obscuresBackgroundDuringPresentation = false
        self.searchController.hidesNavigationBarDuringPresentation = true

        self.navigationItem.searchController = searchController
        self.navigationItem.hidesSearchBarWhenScrolling = false

    }

    
    // GroupContactsViewActions
    
    func userDidValidateSelectedContacts(selectedContacts: [ObvUICoreData.PersistedObvContactIdentity]) async {
        await delegate?.userDidValidateSelectedContacts(in: self, selectedContacts: selectedContacts)
    }
    
    
//    public func updateSelectedContacts(selectedContacts: Set<PersistedObvContactIdentity>) {
//        viewModel.setContacts(to: selectedContacts)
//        viewModel.store.changed.toggle()
//    }
}

//extension GroupContactsHostingViewController: GroupContactsViewActions {
//    
//    func userWantsToSelectContacts() async {
//        Task {
//            contactHostingDelegate?.userWantsToValidateSelection()
//        }
//    }
//    
//    
//}


//extension GroupContactsHostingViewController: ContactsViewStoreDelegate {
//    
//    func userWantsToSeeContactDetails(of contact: ObvUICoreData.PersistedObvContactIdentity) {
//        assert(Thread.isMainThread)
//    }
//    
//}


fileprivate final class Actions: ContactsSelectionForGroupViewActions {
        
    weak var delegate: ContactsSelectionForGroupViewActions?
    
    func userDidValidateSelectedContacts(selectedContacts: [ObvUICoreData.PersistedObvContactIdentity]) async {
        await delegate?.userDidValidateSelectedContacts(selectedContacts: selectedContacts)
    }

}


extension ContactsSelectionForGroupHostingViewController {

    struct Strings {
        static let newGroupTitle = NSLocalizedString("NEW_GROUP", comment: "View controller title")
        static let updateGroupTitle = NSLocalizedString("EDIT_GROUP", comment: "View controller title")
    }

}
