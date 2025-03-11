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
import Foundation
import ObvTypes
import ObvUICoreData
import OSLog


/// Responsible for retrieving search results from our database. Used both in ``NewDiscussionsSelectionViewController`` and in ``DiscussionsSearchViewController``.
@MainActor
public final class DiscussionsSearchStore: NSObject, UISearchResultsUpdating {
    
    private let log = OSLog(subsystem: ObvUIConstants.logSubsystem, category: String(describing: DiscussionsSearchStore.self))
    private var frc: NSFetchedResultsController<PersistedDiscussion>?
    public private(set) var ownedCryptoId: ObvCryptoId
    public let viewContext: NSManagedObjectContext
    private weak var delegate: NSFetchedResultsControllerDelegate?
    private var currentSearchTerm: String? = nil
    private let restrictToActiveDiscussions: Bool
    
    
    public init(ownedCryptoId: ObvCryptoId, restrictToActiveDiscussions: Bool, viewContext: NSManagedObjectContext) {
        self.ownedCryptoId = ownedCryptoId
        self.restrictToActiveDiscussions = restrictToActiveDiscussions
        self.viewContext = viewContext
        super.init()
    }
    
    
    /// Sets the delegate of this store to which search results are sent
    /// - Parameter delegate: The delegate to receive search results
    public func setDelegate(_ delegate: NSFetchedResultsControllerDelegate) {
        self.delegate = delegate
        frc?.delegate = delegate
    }
    
    
    /// Updates the crypto id
    /// - Parameter cryptoId: The new crypto id
    public func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = newOwnedCryptoId
        performInitialFetch()
    }
        
}


// MARK: - UISearchResultsUpdating

extension DiscussionsSearchStore {
    
    public func updateSearchResults(for searchController: UISearchController) {
        if let searchTerm = searchController.searchBar.text, !searchTerm.isEmpty {
            currentSearchTerm = searchTerm
        } else {
            currentSearchTerm = nil
        }
        refreshFetchRequest()
    }

    
    func performInitialFetch() {
        currentSearchTerm = nil
        refreshFetchRequest()
    }
    
    
    /// Refreshes the fetch request for our database for the given search term
    /// - Parameter searchTerm: The search term to search for
    private func refreshFetchRequest() {
        
        let frcModel = PersistedDiscussion.getFetchRequestForSearchTermForDiscussionsForOwnedIdentity(with: ownedCryptoId, restrictToActiveDiscussions: restrictToActiveDiscussions, searchTerm: currentSearchTerm)

        let fetchRequest = frcModel.fetchRequest
        
        if frc == nil {
            frc = NSFetchedResultsController(fetchRequest: fetchRequest,
                                             managedObjectContext: viewContext,
                                             sectionNameKeyPath: frcModel.sectionNameKeyPath,
                                             cacheName: nil)
            frc?.delegate = delegate
        } else {
            frc?.fetchRequest.predicate = fetchRequest.predicate
        }
        
        assert(frc != nil)
        
        do {
            try frc?.performFetch()
        } catch {
            assertionFailure()
            os_log("Could not perform fetch %{public}@", log: log, type: .fault, error.localizedDescription)
        }
    }

}
