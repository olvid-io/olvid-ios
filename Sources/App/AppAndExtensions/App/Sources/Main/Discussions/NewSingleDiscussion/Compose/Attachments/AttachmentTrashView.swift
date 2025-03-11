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
import CoreData
import ObvUICoreData

final class AttachmentTrashView: UIView {

    private let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>
    
    private let trashButton = UIButton(type: .system)
    private let padding = CGFloat(8)
    private let buttonSize = CGFloat(44)
    
    init(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        self.draftObjectID = draftObjectID
        super.init(frame: .zero)
        setupInternalViews()
    }
    
    weak var delegate: AttachmentTrashViewDelegate?
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func setupInternalViews() {
        
        addSubview(trashButton)
        trashButton.translatesAutoresizingMaskIntoConstraints = false
        let configuration = UIImage.SymbolConfiguration(pointSize: 20)
        let trash = UIImage(systemIcon: .trashCircle, withConfiguration: configuration)
        trashButton.setImage(trash, for: .normal)
        trashButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(trashButtonTapped)))

        let constraints = [
            trashButton.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -padding),
            trashButton.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: padding),
            trashButton.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            
            trashButton.widthAnchor.constraint(equalToConstant: buttonSize),
            trashButton.heightAnchor.constraint(equalToConstant: buttonSize),
            
            self.heightAnchor.constraint(greaterThanOrEqualTo: trashButton.heightAnchor),
        ]
        NSLayoutConstraint.activate(constraints)

    }
    
    
    @objc private func trashButtonTapped() {
        guard let delegate else { assertionFailure(); return }
        let draftObjectID = self.draftObjectID
        Task {
            await delegate.userWantsToDeleteAttachmentsFromDraft(draftObjectID: draftObjectID, draftTypeToDelete: .notPreview)
        }
    }

}


protocol AttachmentTrashViewDelegate: AnyObject {
    func userWantsToDeleteAttachmentsFromDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftTypeToDelete: DeleteAllDraftFyleJoinOfDraftOperation.DraftType) async
}
