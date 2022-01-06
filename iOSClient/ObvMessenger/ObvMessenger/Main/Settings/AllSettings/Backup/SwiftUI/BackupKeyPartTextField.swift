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
import Combine


@available(iOS 13, *)
fileprivate struct UITextFieldWrapper: UIViewRepresentable {
    
    let index: Int
    let textFieldWasCreatedAction: (UITextField) -> Void
    
    init(index: Int, textFieldWasCreatedAction: @escaping (UITextField) -> Void) {
        self.index = index
        self.textFieldWasCreatedAction = textFieldWasCreatedAction
    }
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.font = BackupKeyPartTextField.fontForDigits
        textField.placeholder = "XXXX"
        textField.smartInsertDeleteType = .no
        textField.spellCheckingType = .no
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .allCharacters
        textField.tag = index
        textFieldWasCreatedAction(textField)
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {}
    
}


@available(iOS 13, *)
struct BackupKeyPartTextField: View {
    
    let index: Int
    let textFieldWasCreatedAction: (UITextField) -> Void

    static let normalFontsize: CGFloat = 24
    static let smallFontsize: CGFloat = 19

    static let fontForDigits: UIFont = {
        let font: UIFont
        if let _font = UIFont(name: "Courier-Bold", size: normalFontsize) {
            font = _font
        } else {
            font = UIFont.preferredFont(forTextStyle: .largeTitle)
        }
        return UIFontMetrics(forTextStyle: .headline).scaledFont(for: font)
    }()

    var body: some View {
        UITextFieldWrapper(index: index, textFieldWasCreatedAction: textFieldWasCreatedAction)
            .fixedSize()
    }
}






@available(iOS 13, *)
struct BackupKeyPartTextField_Previews: PreviewProvider {
       
    static var previews: some View {
        BackupKeyPartTextField(index: 0, textFieldWasCreatedAction: { _ in })
            .padding()
            .fixedSize(horizontal: true, vertical: true)
            .previewLayout(.sizeThatFits)
    }
}
