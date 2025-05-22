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

import Foundation
import SwiftUI
import os.log
import ObvTypes
import ObvEngine
import Combine
import ObvUICoreData
import ObvUI
import ObvDesignSystem
import ObvAppCoreConstants
import ObvKeycloakManager


protocol KeycloakSearchViewControllerDelegate: AnyObject {
    func userSelectedContactOnKeycloakSearchView(ownedCryptoId: ObvCryptoId, userDetails: ObvKeycloakUserDetails)
}

final class KeycloakSearchViewController: UIHostingController<KeycloakSearchView>, KeycloakSearchViewDelegate {

    let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "KeycloakSearchViewController")

    let searchController: UISearchController
    private let store: KeycloakSearchViewStore

    weak var delegate: KeycloakSearchViewControllerDelegate?
    
    init(ownedCryptoId: ObvCryptoId, delegate: KeycloakSearchViewControllerDelegate) {
        self.store = KeycloakSearchViewStore(ownedCryptoId: ownedCryptoId)
        self.searchController = UISearchController(searchResultsController: nil)
        self.searchController.obscuresBackgroundDuringPresentation = false
        self.searchController.hidesNavigationBarDuringPresentation = false
        self.searchController.searchResultsUpdater = self.store
        self.searchController.automaticallyShowsCancelButton = false
        let view = KeycloakSearchView(store: store)
        super.init(rootView: view)
        navigationItem.searchController = self.searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        store.delegate = self
        title = CommonString.Word.Directory
        self.delegate = delegate
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let closeBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .cancel, target: self, action: #selector(userDidTapCloseButton))
        navigationItem.setLeftBarButton(closeBarButtonItem, animated: false)
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

    func userSelectedContact(ownedCryptoId: ObvCryptoId, userDetails: ObvKeycloakUserDetails) {
        assert(Thread.isMainThread)
        delegate?.userSelectedContactOnKeycloakSearchView(ownedCryptoId: ownedCryptoId, userDetails: userDetails)
    }

}


protocol KeycloakSearchViewDelegate: UIViewController {
    func userSelectedContact(ownedCryptoId: ObvCryptoId, userDetails: ObvKeycloakUserDetails)
    func startSpinner()
    func stopSpinner()
}


final class KeycloakSearchViewStore: NSObject, ObservableObject, UISearchResultsUpdating {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "KeycloakSearchViewStore")

    @Published var searchResult: [ObvKeycloakUserDetails]?
    @Published var numberOfMissingResults: Int = 0
    @Published var searchEncounteredAnError: Bool = false
    @Published private var searchedText: String = ""

    private let ownedCryptoId: ObvCryptoId
    
    weak var delegate: KeycloakSearchViewDelegate?

    private var cancellables = [AnyCancellable]()

    
    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        super.init()
        continuouslyProcessSearchedText()
    }
    
    deinit {
        cancellables.forEach({ $0.cancel() })
    }
    
    func userSelectedContact(userDetails: ObvKeycloakUserDetails) {
        delegate?.userSelectedContact(ownedCryptoId: ownedCryptoId, userDetails: userDetails)
    }
    
    // UISearchResultsUpdating
    
    func updateSearchResults(for searchController: UISearchController) {
        self.searchedText = searchController.searchBar.text ?? ""
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
    
    fileprivate func performInitialSearchOnAppear() {
        Task {
            await performKeycloakSearchNow(textToSearchNow: searchedText)
        }
    }
    
    @MainActor
    private func performKeycloakSearchNow(textToSearchNow: String) async {

        delegate?.startSpinner()
        defer { delegate?.stopSpinner() }
        
        do {
            let newSearchResults = try await KeycloakManagerSingleton.shared.search(ownedCryptoId: ownedCryptoId, searchQuery: textToSearchNow)
            assert(Thread.isMainThread)
            mergeReceivedSearchResults(newSearchResults.userDetails, numberOfMissingResults: newSearchResults.numberOfMissingResults)
        } catch let searchError as KeycloakManager.SearchError {
            Self.logger.error("Search error: \(searchError.localizedDescription)")
            searchEncounteredAnError = true
        } catch {
            Self.logger.error("Search error: \(error.localizedDescription)")
            searchEncounteredAnError = true
        }
    }
    
    
    private func mergeReceivedSearchResults(_ newSearchResults: [ObvKeycloakUserDetails], numberOfMissingResults: Int) {
        assert(Thread.isMainThread)
        let sortedSearchResult = newSearchResults.filter({ $0.identity != ownedCryptoId.getIdentity() }).sorted()
        withAnimation {
            self.searchResult = sortedSearchResult
            self.numberOfMissingResults = numberOfMissingResults
        }
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
        }
        .onAppear(perform: store.performInitialSearchOnAppear)
    }
}

struct KeycloakSearchViewInner: View {

    var searchResults: [ObvKeycloakUserDetails]?
    var numberOfMissingResults: Int
    var userSelectedContact: (ObvKeycloakUserDetails) -> Void
    @Binding var searchEncounteredAnError: Bool

    @State private var showAddContactAlert = false
    
    var body: some View {
        Group {
            if let searchResults = searchResults {
                if searchResults.isEmpty {
                    ObvContentUnavailableView.search
                } else {
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
                }
            } else {
                ProgressView()
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
