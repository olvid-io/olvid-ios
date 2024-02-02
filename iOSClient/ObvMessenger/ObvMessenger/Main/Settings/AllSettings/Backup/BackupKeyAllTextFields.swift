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

import SwiftUI



struct BackupKeyAllTextFields: View {
    
    let disable: Bool
    let internalTextFieldWasCreatedAction: (Int, UITextField) -> Void
       
    var body: some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                ForEach(0..<4) { index in
                    BackupKeyPartTextField(index: index,
                                           textFieldWasCreatedAction: { textField in internalTextFieldWasCreatedAction(index, textField) })
                    if index < 3 {
                        Text(verbatim: "-")
                    }
                }
                Spacer(minLength: 0)
            }
            HStack {
                Spacer(minLength: 0)
                ForEach(4..<8) { index in
                    BackupKeyPartTextField(index: index,
                                           textFieldWasCreatedAction: { textField in internalTextFieldWasCreatedAction(index, textField) })
                    if index < 7 {
                        Text(verbatim: "-")
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .font(Font(BackupKeyPartTextField.fontForDigits))
        .multilineTextAlignment(.center)
        .disabled(disable)
    }
}



struct BackupKeyAllTextFields_Previews: PreviewProvider {

    private static let acceptableCharactersForKey = CharacterSet.alphanumerics

    static var previews: some View {
        BackupKeyAllTextFields(disable: false,
                               internalTextFieldWasCreatedAction: { (_, _) in })
    }
}
