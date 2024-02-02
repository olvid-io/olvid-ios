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
  
import ObvUI
import SwiftUI
import ObvDesignSystem


// Allows to fix an iOS 14/13 bug with @available(iOS 15.0, *) @FocusState
@available(iOS 15, *)
struct FocusModifier: ViewModifier {

    @FocusState var focused: Bool
    @Binding var state: Bool

    init(_ state: Binding<Bool>) {
        self._state = state
    }

    func body(content: Content) -> some View {
        content.focused($focused, equals: true)
            .onChange(of: state, perform: changeFocus)
            .onAppear {
                self.focused = true // This is for focusing after showPassword switching.
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                    self.focused = true // This is for focusing after view appears.
                }
            }
    }

    private func changeFocus(_ value: Bool) {
        focused = value
    }
}

@available(iOS 15, *)
extension View {
    func obvFocused(state: Binding<Bool>) -> some View {
        self.modifier(FocusModifier(state))
    }
}

enum PasscodeKind: Int, CaseIterable, Identifiable {
    case pin
    case password

    var id: Self { self }
    var passcodeIsPassword: Bool {
        self == .password
    }

    var localizedDescription: String {
        switch self {
        case .pin: return NSLocalizedString("PIN", comment: "")
        case .password: return NSLocalizedString("PASSWORD", comment: "")
        }
    }
}


struct PasscodeField: View {

    @Binding var passcode: String
    @Binding var passcodeKind: PasscodeKind
    @Binding var secureFocus: Bool
    @Binding var textFocus: Bool
    @Binding var remainingLockoutTime: TimeInterval?

    @State private var showPasscode: Bool = false

    private let durationFormatter = DurationFormatter()

    private var isLockedOut: Bool {
        remainingLockoutTime != nil
    }

    private var fieldTitle: String {
        if let remainingLockoutTime = remainingLockoutTime {
            var title = NSLocalizedString("LOCKED_OUT_FOR", comment: "")
            if let duration = durationFormatter.string(from: remainingLockoutTime) {
                title += duration
            }
            return title
        } else {
            return NSLocalizedString(passcodeKind.passcodeIsPassword ? "PASSWORD" : "PIN", comment: "")
        }
    }

    private var textField: some View {
        TextField(fieldTitle, text: $passcode)
            .autocapitalization(.none)
            .disableAutocorrection(true)
    }

    private var secureField: some View {
        SecureField(fieldTitle, text: $passcode)
            .autocapitalization(.none)
            .disableAutocorrection(true)
    }

    @ViewBuilder
    private var field: some View {
        if showPasscode {
            textField
                .obvFocused(state: $textFocus)
        } else {
            secureField
                .obvFocused(state: $secureFocus)
        }
    }

    var body: some View {
        HStack {
            field
                .keyboardType(passcodeKind.passcodeIsPassword ? .alphabet : .numberPad)
            if isLockedOut {
                Image(systemIcon: .lock(.none, .none))
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
            } else {
                Button(action: {
                    withAnimation {
                        showPasscode.toggle()
                    }
                }, label: {
                    Image(systemIcon: .eyes)
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .rotation3DEffect(showPasscode ? .zero : .degrees(180), axis: (x: 0, y: 1, z: 0))
                })
            }
        }
        .padding()
        .background(Color(AppTheme.shared.colorScheme.systemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10.0, style: .continuous))
    }

}
