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
import os.log
import ObvUI
import ObvUICoreData
import ObvSettings
import ObvDesignSystem


enum VerifyPasscodeViewResult {
    case succeed
    case lockedOut
    case cancelled
}

final class VerifyPasscodeViewController: UIHostingController<VerifyPasscodeView>, VerifyPasscodeModelDelegate {

    private let model: VerifyPasscodeModel
    private let continuationHolder = CheckedContinuationHolder<VerifyPasscodeViewResult>()

    private var observationTokens = [NSObjectProtocol]()

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "VerifyPasscodeViewController")

    init(verifyPasscodeDelegate: VerifyPasscodeDelegate) {
        assert(Thread.isMainThread)
        self.model = VerifyPasscodeModel(verifyPasscodeDelegate: verifyPasscodeDelegate)
        let view = VerifyPasscodeView(model: model)
        super.init(rootView: view)
        self.model.delgate = self
        observeNotifications()
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func getResult() async -> VerifyPasscodeViewResult {
        return await withCheckedContinuation { (continuation: CheckedContinuation<VerifyPasscodeViewResult, Never>) in
            Task {
                await continuationHolder.setContinuation(continuation)
            }
        }
    }

    fileprivate func setResult(_ result: VerifyPasscodeViewResult) {
        Task {
            await self.continuationHolder.setResult(result)
        }
        self.dismiss(animated: true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Task {
            if await self.continuationHolder.result == nil {
                // The view disappeared after swiping downwards, the result is not set, we cancel to avoid to be stuck.
                await self.continuationHolder.setResult(.cancelled)
            }
        }
    }

    private func observeNotifications() {
        observationTokens.append(contentsOf: [
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] (notification) in
                os_log("VerifyPasscodeViewController processes didEnterBackgroundNotification starts", log: Self.log, type: .info)
                self?.setResult(.cancelled)
                os_log("VerifyPasscodeViewController processes didEnterBackgroundNotification ends", log: Self.log, type: .info)
            }
        ])
    }

}

fileprivate protocol VerifyPasscodeModelDelegate: AnyObject {
    func setResult(_ result: VerifyPasscodeViewResult)
}

final class VerifyPasscodeModel: ObservableObject {

    @Published var passcode: String
    let passcodeKind: PasscodeKind
    private(set) weak var verifyPasscodeDelegate: VerifyPasscodeDelegate?

    fileprivate weak var delgate: VerifyPasscodeModelDelegate?
    private let notificationGenerator = UINotificationFeedbackGenerator()

    init(verifyPasscodeDelegate: VerifyPasscodeDelegate) {
        self.passcode = ""
        self.verifyPasscodeDelegate = verifyPasscodeDelegate
        if ObvMessengerSettings.Privacy.passcodeIsPassword {
            self.passcodeKind = .password
        } else {
            self.passcodeKind = .pin
        }
    }

    func verifyAction(result: VerifyPasscodeViewResult) {
        self.delgate?.setResult(result)
    }

    func cancel() {
        self.delgate?.setResult(.cancelled)
    }

    func errorHaptic() {
        notificationGenerator.notificationOccurred(.error)
    }

    func warningHaptic() {
        notificationGenerator.notificationOccurred(.warning)
    }
}

struct VerifyPasscodeView: View {

    @ObservedObject fileprivate var model: VerifyPasscodeModel

    var body: some View {
        NavigationView {
            InnerVerifyPasscodeView(model: model)
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

fileprivate struct InnerVerifyPasscodeView: View {

    @ObservedObject fileprivate var model: VerifyPasscodeModel

    @State private var passcode: String = ""
    @State private var passcodeAttemptCount: Int = 0
    @State private var isLockedOut: Bool = false
    @State private var remainingLockoutTime: TimeInterval? = nil
    @State private var secureFocus: Bool = true
    @State private var verifyPasscodeHasBeenCalled: Bool = false

    init(model: VerifyPasscodeModel) {
        self.model = model
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    func setLockout(_ isLockedOut: Bool) async {
        if isLockedOut {
            guard let verifyPasscodeDelegate = model.verifyPasscodeDelegate else {
                assertionFailure(); return
            }
            self.secureFocus = false
            self.remainingLockoutTime = await verifyPasscodeDelegate.remainingLockoutTime
            if !self.passcode.isEmpty {
                self.passcode = ""
            }
        } else {
            self.remainingLockoutTime = nil
        }
        self.isLockedOut = isLockedOut
    }

    var body: some View {
        VStack(alignment: .center, spacing: 16.0) {
            Image(systemIcon: .lock(.none, .shield))
                .font(.system(size: 80))
                .foregroundColor(.green)
            Text("ENTER_YOUR_PASSCODE")
                .font(.headline)
            PasscodeField(passcode: $passcode,
                          passcodeKind: .constant(model.passcodeKind),
                          secureFocus: $secureFocus,
                          textFocus: .constant(false),
                          remainingLockoutTime: $remainingLockoutTime)
            .disabled(isLockedOut)
            .onReceive(Just(self.passcode), perform: { value in
                Task {
                    guard let verifyPasscodeDelegate = model.verifyPasscodeDelegate else {
                        assertionFailure(); return
                    }
                    let result = await verifyPasscodeDelegate.verifyPasscode(value, firstTryForThisSession: !verifyPasscodeHasBeenCalled)
                    if !value.isEmpty {
                        verifyPasscodeHasBeenCalled = true
                    }
                    switch result {
                    case .valid:
                        self.model.verifyAction(result: .succeed)
                    case .lockedOut:
                        await setLockout(true)
                        self.model.verifyAction(result: .lockedOut)
                        withAnimation {
                            self.passcodeAttemptCount = ObvMessengerSettings.Privacy.passcodeAttemptCount
                        }
                        model.errorHaptic()
                    case .wrong(let passcodeFailedCountWasIncremented):
                        await setLockout(false)
                        if passcodeFailedCountWasIncremented {
                            withAnimation {
                                self.passcodeAttemptCount = ObvMessengerSettings.Privacy.passcodeAttemptCount
                            }
                            model.warningHaptic()
                        }
                    }
                }
            })
            .modifier(Shake(animatableData: CGFloat(self.passcodeAttemptCount)))
            .onReceive(timer) { _ in
                Task {
                    guard let verifyPasscodeDelegate = model.verifyPasscodeDelegate else {
                        assertionFailure(); return
                    }
                    let isLockedOut = await verifyPasscodeDelegate.isLockedOut
                    await setLockout(isLockedOut)
                }
            }
            .onAppear {
                Task {
                    guard let verifyPasscodeDelegate = model.verifyPasscodeDelegate else {
                        assertionFailure(); return
                    }
                    self.isLockedOut = await verifyPasscodeDelegate.isLockedOut
                    self.remainingLockoutTime = await verifyPasscodeDelegate.remainingLockoutTime
                }
            }
            Spacer()
        }
        .padding(.horizontal, 30)
    }

}

struct Shake: GeometryEffect {
    var amount: CGFloat = 10
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * 4),
                                              y: 0))
    }
}
