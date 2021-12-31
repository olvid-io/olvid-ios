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

import UIKit
import CoreData

final class ComposeMessageDataSourceInMemory: NSObject, ComposeMessageDataSource {
    
    weak var collectionView: UICollectionView? {
        didSet {
            configureCollectionView()
        }
    }

    private let inMemoryDraft: InMemoryDraft
    
    
    init(inMemoryDraft: InMemoryDraft) {
        self.inMemoryDraft = inMemoryDraft
        super.init()
    }
    
    
    var draft: Draft {
        return inMemoryDraft
    }
    
    
    var body: String? {
        return inMemoryDraft.body
    }
    
    func saveBodyText(body: String) {
        inMemoryDraft.body = body
    }

    
    var replyTo: (displayName: String, messageElement: MessageCollectionViewCell.MessageElement)? { return nil }
    func deleteReplyTo(completionHandler: @escaping (Error?) -> Void) throws {}
    
    private func configureCollectionView() {
        guard let collectionView = self.collectionView else { return }
        collectionView.register(UINib(nibName: FyleCollectionViewCell.nibName, bundle: nil),
                                forCellWithReuseIdentifier: FyleCollectionViewCell.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.reloadData()
    }

    var collectionViewIsEmpty: Bool {
        return inMemoryDraft.draftFyleJoins.isEmpty
    }
    
    func longPress(on: IndexPath) {
        // Does nothing
    }
    
    func tapPerformed(on indexPath: IndexPath) {
        
        inMemoryDraft.removeDraftFyleJoin(atIndex: indexPath.item)
        collectionView?.deleteItems(at: [indexPath])
        
    }
}


extension ComposeMessageDataSourceInMemory: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard section == 0 else { return 0 }
        return inMemoryDraft.draftFyleJoins.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let draftFyleJoin = inMemoryDraft.draftFyleJoins[indexPath.item]
        let fyleCell = collectionView.dequeueReusableCell(withReuseIdentifier: FyleCollectionViewCell.identifier, for: indexPath) as! FyleCollectionViewCell
        fyleCell.configure(with: draftFyleJoin)
        fyleCell.layoutIfNeeded()
        return fyleCell
    }
    
}


// MARK: - UICollectionViewDelegateFlowLayout

extension ComposeMessageDataSourceInMemory: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return FyleCollectionViewCell.intrinsicSize
    }
    
}
