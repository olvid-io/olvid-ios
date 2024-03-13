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

import Foundation
import CoreData
import OSLog
import Combine
import ObvUICoreData

/// This class is used in the single discussion view, and serves as the `searchResultsUpdater` of the `UISearchController` used to search a word within all the messages of a discussion.
@MainActor
final class SingleDiscussionSearchControllerDelegate: NSObject, UISearchBarDelegate {

    @Published private(set) var searchResults: [TypeSafeManagedObjectID<PersistedMessage>]?

    private lazy var contextForSearch: NSManagedObjectContext? = ObvStack.shared.newBackgroundContext()
    private let subject = PassthroughSubject<String, Never>()
    private var cancellables = Set<AnyCancellable>()

    private let textSubject = PassthroughSubject<String?, Never>()
    private var textPublisher: AnyPublisher<String?, Never> {
        textSubject.eraseToAnyPublisher()
    }
    
    init(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        super.init()
        continuouslyProcessSearches(in: discussionObjectID)
    }
    
    deinit {
        cancellables.forEach({ $0.cancel() })
    }

    // Updating search results
   
    @MainActor
    private func updateSearchResults(with newSearchResults: [TypeSafeManagedObjectID<PersistedMessage>]?) async {
        self.searchResults = newSearchResults
        debugPrint("New search results: \(newSearchResults?.count ?? 0) results")
    }
    
}

// MARK: - UISearchResultsUpdating

extension SingleDiscussionSearchControllerDelegate: UISearchResultsUpdating {
    
    /// Part of the UISearchResultsUpdating protocol.
    /// Called when the results of the search need to be updated (e.g., when the user changes the searched text).
    func updateSearchResults(for searchController: UISearchController) {
        let searchedText = searchController.searchBar.text
        textSubject.send(searchedText)
    }

    
    private func continuouslyProcessSearches(in discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        textPublisher
            .debounce(for: 0.3, scheduler: RunLoop.main)
            .sink { [weak self] searchedText in
                guard let self else { return }
                guard let searchedText, !searchedText.isEmpty else {
                    Task { [weak self] in await self?.updateSearchResults(with: nil) }
                    return
                }
                Task { [weak self] in
                    guard let self, let contextForSearch else { return }
                    contextForSearch.perform {
                        do {
                            let results = try PersistedMessage.searchForAllMessagesWithinDiscussion(discussionObjectID: discussionObjectID, searchTerm: searchedText, within: contextForSearch)
                            Task { [weak self] in await self?.updateSearchResults(with: results) }
                        } catch {
                            assertionFailure()
                            Task { [weak self] in await self?.updateSearchResults(with: nil) }
                        }
                    }
                    debugPrint("Searched text: \(searchedText)")
                }
            }
            .store(in: &cancellables)
    }
    
}
