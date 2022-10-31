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
  

import Foundation
import SwiftUI
import Combine

enum CreatePasscodeViewResult {
    case passcode(passcode: String, passcodeIsPassword: Bool)
    case cancelled
}

final class CreatePasscodeViewController: UIHostingController<CreatePasscodeView>, CreatePasscodeModelDelegate {

    private let model: CreatePasscodeModel
    private let continuationHolder = CheckedContinuationHolder<CreatePasscodeViewResult>()

    init() {
        assert(Thread.isMainThread)
        self.model = CreatePasscodeModel()
        let view = CreatePasscodeView(model: model)
        super.init(rootView: view)
        self.model.delegate = self
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func getResult() async -> CreatePasscodeViewResult {
        return await withCheckedContinuation { (continuation: CheckedContinuation<CreatePasscodeViewResult, Never>) in
            Task {
                await continuationHolder.setContinuation(continuation)
            }
        }
    }

    fileprivate func setResult(_ result: CreatePasscodeViewResult) {
        Task {
            await continuationHolder.setResult(result)
        }
        self.dismiss(animated: true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Task {
            if await self.continuationHolder.result == nil {
                // The view disappear by swiping downwards, the result is not set, we cancel to avoid to be stuck.
                await self.continuationHolder.setResult(.cancelled)
            }
        }
    }
}

fileprivate protocol CreatePasscodeModelDelegate: AnyObject {
    func setResult(_ result: CreatePasscodeViewResult)
}

fileprivate enum PasscodeError {
    case tooSmall
    case notAllNumbers
}

fileprivate final class CreatePasscodeModel: ObservableObject {

    @Published var passcode: String {
        didSet {
            withAnimation {
                self.passcodeError = checkPasscode()
            }
        }
    }
    @Published var passcodeError: PasscodeError?
    @Published var passcodeKind: PasscodeKind = .pin
    @Published var secureFocus: Bool = true
    @Published var textFocus: Bool = true

    fileprivate weak var delegate: CreatePasscodeModelDelegate?

    init() {
        self.passcode = ""
        self.passcodeError = .tooSmall
        assert(checkPasscode() == self.passcodeError)
    }

    func cancel() {
        self.delegate?.setResult(.cancelled)
    }

    func resetPasscode() {
        self.passcode = ""
        self.passcodeError = checkPasscode()
    }

    private func checkPasscode() -> PasscodeError? {
        switch passcodeKind {
        case .pin:
            guard passcode.allSatisfy({ $0.isNumber }) else {
                return .notAllNumbers
            }
        case .password:
            break
        }
        guard passcode.count >= 4 else {
            return .tooSmall
        }
        return nil
    }

    func confirmPasscode(passcode: String) {
        guard passcode == self.passcode else { return }
        assert(checkPasscode() == nil)
        self.delegate?.setResult(.passcode(passcode: passcode, passcodeIsPassword: passcodeKind.passcodeIsPassword))
    }

}

struct CreatePasscodeView: View {

    fileprivate var model: CreatePasscodeModel

    var body: some View {
        NavigationView {
            InnerCreatePasscodeView(model: model)
                .navigationBarItems(leading:
                                        Button(action: model.cancel,
                                               label: {
                    Image(systemIcon: .xmarkCircleFill)
                        .font(Font.system(size: 24, weight: .semibold, design: .default))
                })
                                            .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
                )
        }
    }
}

fileprivate struct InnerCreatePasscodeView: View {

    @ObservedObject fileprivate var model: CreatePasscodeModel

    @State private var showVerificationView = false

    var body: some View {
        VStack(alignment: .center, spacing: 16.0) {
            Image(systemIcon: .lock(.none, .shield))
                .font(.system(size: 80))
                .foregroundColor(.green)
            Text("CREATE_YOUR_PASSCODE")
                .font(.headline)
            PasscodeField(passcode: $model.passcode,
                          passcodeKind: $model.passcodeKind,
                          secureFocus: $model.secureFocus,
                          textFocus: $model.textFocus,
                          remainingLockoutTime: .constant(nil))
            if #available(iOS 15.0, *) {
                Picker("Passcode", selection: $model.passcodeKind.animation()) {
                    ForEach(PasscodeKind.allCases) { kind in
                        Text(kind.localizedDescription)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: model.passcodeKind) { _ in
                    let secureFocus = model.secureFocus
                    let textFocus  = model.textFocus
                    model.secureFocus = false
                    model.textFocus = false
                    model.passcode = ""
                    model.secureFocus = secureFocus
                    model.textFocus = textFocus
                }
            }
            NavigationLink(destination: VerifyCreatedPasscodeView(model: model),
                           isActive: $showVerificationView) {
                OlvidButton(style: .blue, title: Text("CREATE_MY_PASSCODE")) {
                    showVerificationView = true
                }
            }
                           .disabled(model.passcodeError != nil)
            ScrollView {
                HStack {
                    Spacer()
                    Text("PLEASE_NOTE_THAT_YOUR_CUSTOM_PASSCODE_CANNOT_BE_RECOVERED")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 30)
    }
}

struct VerifyCreatedPasscodeView: View {

    @ObservedObject fileprivate var model: CreatePasscodeModel

    @State private var passcode: String = ""

    var body: some View {
        VStack(alignment: .center, spacing: 16.0) {
            Image(systemIcon: .lock(.none, .shield))
                .font(.system(size: 80))
                .foregroundColor(.green)
            Text("CONFIRM_YOUR_PASSCODE")
                .font(.headline)
            PasscodeField(passcode: $passcode.animation(),
                          passcodeKind: $model.passcodeKind,
                          secureFocus: $model.secureFocus,
                          textFocus: $model.textFocus,
                          remainingLockoutTime: .constant(nil))
            OlvidButton(style: .blue, title: Text("CREATE_MY_PASSCODE")) {
                model.confirmPasscode(passcode: passcode)
            }
            .disabled(model.passcode != passcode)
            Spacer()
        }
        .padding(.horizontal, 30)
    }
}
