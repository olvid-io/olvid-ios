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

import Foundation
import SwiftUI
import os.log
import ObvTypes
import ObvEngine
import Combine


protocol KeycloakSearchViewControllerDelegate: AnyObject {
    func showMyIdButtonTappedAction()
    func userSelectedContactOnKeycloakSearchView(ownedCryptoId: ObvCryptoId, userDetails: UserDetails)
}

final class KeycloakSearchViewController: UIHostingController<KeycloakSearchView>, KeycloakSearchViewDelegate {

    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "KeycloakSearchViewController")

    let searchController: UISearchController
    private let store: KeycloakSearchViewStore

    weak var delegate: KeycloakSearchViewControllerDelegate?
    
    init(ownedCryptoId: ObvCryptoId, delegate: KeycloakSearchViewControllerDelegate) {
        self.store = KeycloakSearchViewStore(ownedCryptoId: ownedCryptoId)
        self.searchController = UISearchController(searchResultsController: nil)
        self.searchController.obscuresBackgroundDuringPresentation = false
        self.searchController.hidesNavigationBarDuringPresentation = true
        self.searchController.searchResultsUpdater = self.store
        let view = KeycloakSearchView(store: store)
        super.init(rootView: view)
        navigationItem.searchController = self.searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        store.delegate = self
        title = CommonString.Word.Search
        self.delegate = delegate
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let closeButton = UIBarButtonItem.forClosing(target: self, action: #selector(userDidTapCloseButton))
        navigationItem.setLeftBarButton(closeButton, animated: false)
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // KeycloakSearchViewDelegate
    
    private var spinner: UIActivityIndicatorView = {
        UIActivityIndicatorView(style: .medium)
    }()

    func startSpinner() {
        assert(Thread.isMainThread)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        spinner.startAnimating()
    }
    
    func stopSpinner() {
        assert(Thread.isMainThread)
        spinner.stopAnimating()
        navigationItem.rightBarButtonItem = nil
    }
    
    @objc func userDidTapCloseButton() {
        self.dismiss(animated: true)
    }

    func userSelectedContact(ownedCryptoId: ObvCryptoId, userDetails: UserDetails) {
        assert(Thread.isMainThread)
        delegate?.userSelectedContactOnKeycloakSearchView(ownedCryptoId: ownedCryptoId, userDetails: userDetails)
    }

    func showMyIdButtonTappedAction() {
        delegate?.showMyIdButtonTappedAction()
    }
    
}


protocol KeycloakSearchViewDelegate: UIViewController {
    func userSelectedContact(ownedCryptoId: ObvCryptoId, userDetails: UserDetails)
    func showMyIdButtonTappedAction()
    func startSpinner()
    func stopSpinner()
}


final class KeycloakSearchViewStore: NSObject, ObservableObject, UISearchResultsUpdating {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "KeycloakSearchViewStore")

    @Published var searchResult: [UserDetails]?
    @Published var numberOfMissingResults: Int = 0
    @Published var searchEncounteredAnError: Bool = false

    private let ownedCryptoId: ObvCryptoId
    
    weak var delegate: KeycloakSearchViewDelegate?

    private var cancellables = [AnyCancellable]()

    @Published private var searchedText: String?
    
    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        super.init()
        continuouslyProcessSearchedText()
    }
    
    func userSelectedContact(userDetails: UserDetails) {
        delegate?.userSelectedContact(ownedCryptoId: ownedCryptoId, userDetails: userDetails)
    }
    
    // UISearchResultsUpdating
    
    func updateSearchResults(for searchController: UISearchController) {
        self.searchedText = searchController.searchBar.text
    }
    
    // Handling search

    private func continuouslyProcessSearchedText() {
        cancellables.append(contentsOf: [
            self.$searchedText
                .debounce(for: 0.5, scheduler: RunLoop.main)
                .removeDuplicates()
                .sink(receiveValue: { [weak self] (textToSearchNow) in
                    Task { await self?.performKeycloakSearchNow(textToSearchNow: textToSearchNow) }
                })
        ])
    }
    
    @MainActor
    private func performKeycloakSearchNow(textToSearchNow: String?) async {
        assert(Thread.isMainThread)
        guard let searchQuery = textToSearchNow else {
            withAnimation { [weak self] in
                self?.searchResult = nil
            }
            return
        }
        delegate?.startSpinner()
        defer { delegate?.stopSpinner() }
        
        do {
            let newSearchResults = try await KeycloakManagerSingleton.shared.search(ownedCryptoId: ownedCryptoId, searchQuery: searchQuery)
            assert(Thread.isMainThread)
            mergeReceivedSearchResults(newSearchResults.userDetails, numberOfMissingResults: newSearchResults.numberOfMissingResults)
        } catch let searchError as KeycloakManager.SearchError {
            os_log("Search error: %{public}@", log: Self.log, type: .error, searchError.localizedDescription)
            searchEncounteredAnError = true
        } catch {
            os_log("Search error: %{public}@", log: Self.log, type: .error, error.localizedDescription)
            searchEncounteredAnError = true
        }
    }
    
    
    private func mergeReceivedSearchResults(_ newSearchResults: [UserDetails], numberOfMissingResults: Int) {
        assert(Thread.isMainThread)
        let sortedSearchResult = newSearchResults.filter({ $0.identity != ownedCryptoId.getIdentity() }).sorted()
        withAnimation {
            self.searchResult = sortedSearchResult
            self.numberOfMissingResults = numberOfMissingResults
        }
    }
    
    
    func showMyIdButtonTappedAction() {
        delegate?.showMyIdButtonTappedAction()
    }
    
}


// MARK: - KeycloakSearchView

struct KeycloakSearchView: View {

    @ObservedObject fileprivate var store: KeycloakSearchViewStore

    var body: some View {
        VStack {
            KeycloakSearchViewInner(searchResults: store.searchResult,
                                    numberOfMissingResults: store.numberOfMissingResults,
                                    userSelectedContact: store.userSelectedContact,
                                    searchEncounteredAnError: $store.searchEncounteredAnError)
            Spacer()
            OlvidButton(style: .blue, title: Text("Show my Id"), systemIcon: .qrcode, action: store.showMyIdButtonTappedAction)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }
}

struct KeycloakSearchViewInner: View {

    var searchResults: [UserDetails]?
    var numberOfMissingResults: Int
    var userSelectedContact: (UserDetails) -> Void
    @Binding var searchEncounteredAnError: Bool

    @State private var showAddContactAlert = false
    
    var body: some View {
        Group {
            if let searchResults = searchResults {
                List {
                    ForEach(searchResults) { userDetails in
                        HStack {
                            IdentityCardContentView(model: SingleIdentity(userDetails: userDetails))
                            Spacer()
                        }
                        .padding(.vertical, 6.0)
                        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
                        .onTapGesture {
                            userSelectedContact(userDetails)
                        }
                    }
                    if numberOfMissingResults > 0 {
                        Text(String.localizedStringWithFormat(NSLocalizedString("KEYCLOAK_MISSING_SEARCH_RESULT", comment: ""), numberOfMissingResults))
                            .font(Font.system(.callout, design: .default))
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                            .padding(.vertical)
                    }
                }
            } else {
                ExplanationView()
            }
        }
        .alert(isPresented: $searchEncounteredAnError) {
            Alert(title: Text("😧 Oups..."),
                  message: Text("UNABLE_TO_PERFORM_KEYCLOAK_SEARCH"),
                  dismissButton: Alert.Button.default(Text("Ok"))
            )
        }
    }

}

fileprivate struct ExplanationView: View {
    
    var body: some View {
        VStack(alignment: .center) {
            Group {
                Text("SEARCH_HERE")
                    .multilineTextAlignment(.center)
                    .font(Font.system(size: 26, weight: .bold, design: .rounded))
                    .frame(maxWidth: 200)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .padding(10)
                    .offset(CGSize(width: 0, height: 20))
                    .background(
                        Image(systemName: "bubble.middle.top.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .foregroundColor(Color(AppTheme.shared.colorScheme.systemFill))
                    )
            }
            .offset(CGSize(width: 0, height: 50))
            Spacer()
       }
    }
    
}
