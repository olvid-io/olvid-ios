/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvUI


protocol PersonalNoteViewModelProtocol: ObservableObject {
    var text: String? { get }
}


struct PersonalNoteView<Model: PersonalNoteViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    
    var body: some View {
        ObvCardView {
            VStack(alignment: .leading) {
                HStack {
                    Text("PERSONAL_NOTE")
                        .font(.headline)
                        .padding(.bottom, 4)
                    Spacer(minLength: 0)
                }
                Text(verbatim: model.text ?? "")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
    
}


struct PersonalNoteView_Previews: PreviewProvider {
    
    final class ModelForPreviews: PersonalNoteViewModelProtocol {

        let text: String?

        init(text: String?) {
            self.text = text
        }
        
    }
    
    static var previews: some View {
        Group {
            PersonalNoteView(
                model: ModelForPreviews(text: "The text of the personal note"))
        }
    }
    
}
