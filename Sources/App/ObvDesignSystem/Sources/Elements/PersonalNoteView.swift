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

@MainActor
public protocol PersonalNoteViewModelProtocol: ObservableObject {
    var personalNote: String? { get }
}


public struct PersonalNoteView<Model: PersonalNoteViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    
    public init(model: Model) {
        self.model = model
    }
    
    public var body: some View {
        PersonalNoteStaticView(personalNote: model.personalNote)
    }
    
}


public struct PersonalNoteStaticView: View {

    private let personalNote: String?

    public init(personalNote: String?) {
        self.personalNote = personalNote
    }
    
    public var body: some View {
        ObvCardView {
            VStack(alignment: .leading) {
                HStack {
                    Text("PERSONAL_NOTE")
                        .font(.headline)
                        .padding(.bottom, 4)
                    Spacer(minLength: 0)
                }
                Text(verbatim: personalNote ?? "")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
    
}


struct PersonalNoteView_Previews: PreviewProvider {
    
    final class ModelForPreviews: PersonalNoteViewModelProtocol {

        let personalNote: String?

        init(personalNote: String?) {
            self.personalNote = personalNote
        }
        
    }
    
    static var previews: some View {
        Group {
            PersonalNoteView(
                model: ModelForPreviews(personalNote: "The text of the personal note"))
        }
    }
    
}
