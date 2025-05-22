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
import LocalAuthentication


struct BackupKeyView: View {
    
    struct Constant {
        static let width: CGFloat = 310.0
        static let fontSizeForFixedValue: CGFloat = 26.0
        static let fontSizeForEditableValue: CGFloat = 30.0
    }

    enum Kind {
        case editable(value: Binding<String>)
        case fixedValue(_ value: String, isBackupSeedHidden: Binding<Bool>)
    }
    
    private let kind: Kind
    
    init(kind: Kind) {
        self.kind = kind
    }
            
    var body: some View {
        switch kind {
        case .editable(value: let value):
            BackupKeyViewEditable(value: value)
        case .fixedValue(let fixedValue, isBackupSeedHidden: let isBackupSeedHidden):
            BackupKeyViewFixed(fixedValue: fixedValue, isBackupSeedHidden: isBackupSeedHidden)
        }
    }
    
}


// MARK: - Private structs


private struct BackupKeyViewEditable: View {
    
    @Binding var value: String
    
    private var textOpacity: Double {
        value.isEmpty ? 1.0 : 0
    }

    private func keepAcceptableCharactersOnly(_ input: String) -> String {
        String(value.filter({ $0.isLetter || $0.isNumber }).prefix(32))
    }

    var body: some View {
        Group {
            if #available(iOS 16, *) {
                ZStack {
                    TextField("", text: $value, axis: .vertical)
                        .lineLimit(2, reservesSpace: true)
                        .frame(width: BackupKeyView.Constant.width)
                    Text(verbatim: "0123456789ABCDEFGHIJKLMNOPQRSTUV")
                        .lineLimit(2)
                        .frame(width: BackupKeyView.Constant.width)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .opacity(textOpacity)
                }
            } else {
                ZStack {
                    TextField("", text: $value)
                        .lineLimit(1)
                        .frame(width: BackupKeyView.Constant.width)
                    Text(verbatim: "0123456789ABCDEFGHIJKLMNOPQRSTUV")
                        .lineLimit(1)
                        .frame(width: BackupKeyView.Constant.width)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .opacity(textOpacity)
                }
            }
        }
        .font(.system(size: BackupKeyView.Constant.fontSizeForEditableValue, weight: .semibold, design: .monospaced))
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .textFieldStyle(.roundedBorder)
        .onChange(of: value) { newValue in
            let parsed = keepAcceptableCharactersOnly(newValue)
            if value != parsed {
                value = parsed
            }
        }
    }
}


private struct BackupKeyViewFixed: View {
    
    let fixedValue: String
    @Binding var isBackupSeedHidden: Bool
    
    private var fixValueWithSpaces: String {
        guard fixedValue.count == 32 else {
            return fixedValue
        }
        let slices = [Character](fixedValue).toSlices(ofMaxSize: 4)
        let result = slices
            .map { slice in
                return String(slice).appending(" ")
            }
            .joined()
        return result
    }
    
    private func userTappedShowBackupSeedButton() {
        Task {
            guard await authenticateUserIfPossible() else { return }
            try? await Task.sleep(seconds: 0.3)
            withAnimation {
                isBackupSeedHidden = false
            }
            Task {
                try? await Task.sleep(seconds: 20)
                withAnimation {
                    isBackupSeedHidden = true
                }
            }
        }
    }
    
    
    private func authenticateUserIfPossible() async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return true
        } else {
            return await authenticateUser()
        }
        #else
        return await authenticateUser()
        #endif
    }
    
    
    private func authenticateUser() async -> Bool {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return true
        }
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = String(localizedInThisBundle: "AUTHENTICATION_REQUIRED_TO_SHOW_YOUR_KEY")
            do {
                if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
                    return true
                } else {
                    return false
                }
            } catch {
                return false
            }
        } else {
            return true
        }
    }
    
    
    var body: some View {
        ZStack {
            Text(fixValueWithSpaces)
                .lineLimit(2)
                .lineSpacing(8)
                .font(.system(size: BackupKeyView.Constant.fontSizeForFixedValue, weight: .bold, design: .monospaced))
                .frame(width: BackupKeyView.Constant.width)
                .blur(radius: isBackupSeedHidden ? 15 : 0)
                .opacity(isBackupSeedHidden ? 0.8 : 1)
                .scaleEffect(isBackupSeedHidden ? 0.85 : 1.0, anchor: .center)
            if isBackupSeedHidden {
                Button(action: userTappedShowBackupSeedButton) {
                    Text("SHOW_BACKUP_KEY")
                }
                .buttonStyle(.borderedProminent)
                .animation(nil, value: isBackupSeedHidden)
            }
        }
    }
}



// MARK: - Previews

private struct EditableBackupKeyPreview: View {
    
    @State private var value = ""
    
    var body: some View {
        VStack {
            BackupKeyView(kind: .editable(value: $value))
            Text(verbatim: "\(value.count)")
        }
    }
}


private struct FixedBackupKeyPreview: View {
    
    @State private var isBackupSeedHidden = true
    
    var body: some View {
        BackupKeyView(kind: .fixedValue("0123456789ABCDEFGHIJKLMNOPQRSTUV", isBackupSeedHidden: $isBackupSeedHidden))
    }
}

#Preview("Editable") {
    EditableBackupKeyPreview()
}

#Preview("Fixed value") {
    FixedBackupKeyPreview()
}
