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

@available(iOS 17.0, *)
struct ConfirmDialogModifier<Model: StorageManagementFileListViewModelProtocol>: ViewModifier {
    var model: Model
    
    func body(content: Content) -> some View {
        content
            .confirmationDialog("",
                                isPresented: Binding(get: { self.model.showDeletionAlert }, set: { self.model.showDeletionAlert(value: $0) }),
                                titleVisibility: .hidden) {
                if model.selectionProperties.multipleSelections.count <= 1 {
                    if let selectFyleMessageJoin = model.selectionProperties.multipleSelections.first ?? model.selectionProperties.singleSelected, model.itemHasDuplicate(selectFyleMessageJoin) { // If fyle selected has duplicate, we delete all duplicates.
                        Button("DELETE_ITEMS_WITH_DUP", role: .destructive) {
                            model.performDeletion(deletionMode: .all)
                        }
                    }
                    Button("DELETE_ITEM", role: .destructive) {
                        model.performDeletion(deletionMode: .unique)
                    }
                } else {
                    Button("DELETE_ITEMS", role: .destructive) {
                        model.performDeletion(deletionMode: .unique)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}
