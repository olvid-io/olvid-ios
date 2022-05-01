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
import os.log
import ObvEngine
import ObvTypes



final class BackupKeyVerifierViewHostingController: UIHostingController<BackupKeyVerifierView> {
    
    private static let acceptableCharactersForKey = CharacterSet.alphanumerics
    
    private let backupKeyTester: BackupKeyTester
    
    init(obvEngine: ObvEngine, backupFileURL: URL? = nil, dismissAction: @escaping () -> Void, dismissThenGenerateNewBackupKeyAction: @escaping () -> Void) {
        let backupKeyTester = BackupKeyTester(obvEngine: obvEngine, backupFileURL: backupFileURL)
        self.backupKeyTester = backupKeyTester
        let view = BackupKeyVerifierView(backupKeyTester: backupKeyTester,
                                         dismissAction: dismissAction,
                                         dismissThenGenerateNewBackupKeyAction: dismissThenGenerateNewBackupKeyAction)
        super.init(rootView: view)
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
     
    var delegate: BackupKeyTesterDelegate? {
        get { backupKeyTester.delegate }
        set { backupKeyTester.delegate = newValue }
    }
    
}

protocol BackupKeyTesterDelegate: AnyObject {
    func userWantsToRestoreBackupIdentifiedByRequestUuid(_ requestUuid: UUID)
}


fileprivate final class BackupKeyTester: NSObject, ObservableObject, UITextFieldDelegate {
    
    @Published var keyStatusReport: KeyStatusReportType? = nil
    @Published var currentlyCheckingKey = false
    
    private var notificationTokens = [NSObjectProtocol]()
    private let obvEngine: ObvEngine
    private var internalTextFields = [UITextField?](repeating: nil, count: 8)
    private let acceptableCharactersForKey: CharacterSet
    private let backupFileURL: URL?
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "BackupKeyTester")

    weak var delegate: BackupKeyTesterDelegate?
    
    private var currentKeyParts: [String] {
        internalTextFields.map { $0?.text ?? "" }
    }

    var isInBackupRecoveryMode: Bool { backupFileURL != nil }
    
    init(obvEngine: ObvEngine, backupFileURL: URL?) {
        self.backupFileURL = backupFileURL
        self.acceptableCharactersForKey = obvEngine.getAcceptableCharactersForBackupKeyString()
        self.obvEngine = obvEngine
        super.init()
        notificationTokens.append(NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: nil, queue: OperationQueue.main) { [weak self] (notification) in
            withAnimation {
                self?.keyStatusReport = nil
            }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: nil, queue: nil) { [weak self] (notification) in
            let textField = notification.object as! UITextField
            guard self?.internalTextFields.contains(textField) == true else { return }
            let index = textField.tag
            self?.textFieldDidChange(atIndex: index)
        })
    }

    enum KeyStatusReportType {
        case backupKeyVerificationFailed
        case backupKeyVerificationSucceded
        case fullBackupRecovered(backupRequestIdentifier: UUID, fullBackupDate: Date)
        case fullBackupCouldNotBeRecovered(error: BackupRestoreError)
        case couldNotReadBackupFileData
        
    }
    
    func internalTextFieldCreated(atIndex index: Int, textField: UITextField) {
        assert(Thread.isMainThread)
        guard index < 8 else { assertionFailure(); return }
        textField.delegate = self
        internalTextFields[index] = textField
    }
    
    func textFieldDidChange(atIndex index: Int) {
        guard index < 8 else { assertionFailure(); return }
        guard let value = internalTextFields[index]?.text else { assertionFailure(); return }
        guard value.count < 5 else { assertionFailure(); return }
        computeNewIndexOfSelectedTextField(currentIndex: index)
        checkKeyCandidateIfPossible()
    }
    
    private func computeNewIndexOfSelectedTextField(currentIndex: Int) {
        assert(Thread.isMainThread)
        guard currentKeyParts[currentIndex].count >= 4 else { return }
        let allPartsAreComplete = currentKeyParts.allSatisfy { $0.count == 4 }
        if allPartsAreComplete {
            allInternalTextFieldShouldResignFirstResponder()
        } else if currentIndex == 7 {
            allInternalTextFieldShouldResignFirstResponder()
        } else {
            internalTextFields[currentIndex]?.resignFirstResponder()
            internalTextFields[currentIndex+1]?.becomeFirstResponder()
        }
    }
    
    private func allInternalTextFieldShouldResignFirstResponder() {
        for textField in internalTextFields {
            textField?.resignFirstResponder()
        }
    }
    
    private func checkKeyCandidateIfPossible() {
        assert(Thread.isMainThread)
        let allPartsAreComplete = currentKeyParts.allSatisfy { $0.count == 4 }
        guard allPartsAreComplete else { return }
        guard !currentlyCheckingKey else { return }
        allInternalTextFieldShouldResignFirstResponder()
        currentlyCheckingKey = true
        let backupKeyString = currentKeyParts.joined()
        if let backupFileURL = self.backupFileURL {
            Task {
                assert(Thread.isMainThread)
                let backupData: Data
                do {
                    backupData = try await readBackupedDataFrom(backupFileURL: backupFileURL)
                } catch {
                    assert(Thread.isMainThread)
                    withAnimation {
                        keyStatusReport = .couldNotReadBackupFileData
                        currentlyCheckingKey = false
                    }
                    return
                }
                let status = await useEnteredBackupKey(backupKeyString, forDecryptingBackupData: backupData)
                assert(Thread.isMainThread)
                withAnimation {
                    keyStatusReport = status
                    currentlyCheckingKey = false
                }
                return
            }
        } else {
            Task {
                assert(Thread.isMainThread)
                do {
                    let backupKeyStringIsCorrect = try await obvEngine.verifyBackupKeyString(backupKeyString)
                    if backupKeyStringIsCorrect {
                        withAnimation {
                            keyStatusReport = .backupKeyVerificationSucceded
                            currentlyCheckingKey = false
                        }
                        return
                    }
                } catch {
                    // Continue
                }
                assert(Thread.isMainThread)
                withAnimation {
                    keyStatusReport = .backupKeyVerificationFailed
                    currentlyCheckingKey = false
                }
            }
        }
    }
    
    
    private func readBackupedDataFrom(backupFileURL: URL) async throws -> Data {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let backupData: Data
            do {
                backupData = try Data(contentsOf: backupFileURL)
            } catch {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: backupData)
        }
    }
    
    
    private func useEnteredBackupKey(_ backupKeyString: String, forDecryptingBackupData backupData: Data) async -> KeyStatusReportType {
        do {
            let (backupRequestIdentifier, backupDate) = try await obvEngine.recoverBackupData(backupData, withBackupKey: backupKeyString)
            return .fullBackupRecovered(backupRequestIdentifier: backupRequestIdentifier, fullBackupDate: backupDate)
        } catch let error {
            if let error = error as? BackupRestoreError {
                return .fullBackupCouldNotBeRecovered(error: error)
            } else {
                assertionFailure("The engine is supposed to throw instances of BackupRestoreError")
                return .fullBackupCouldNotBeRecovered(error: BackupRestoreError.internalError(code: 10))
            }
        }
    }
    
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard internalTextFields.contains(textField) else { assertionFailure(); return true }
        textField.resignFirstResponder()
        return true
    }

    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {

        guard internalTextFields.contains(textField) else { assertionFailure(); return true }
        
        // Make sure all characters of the replacement string are acceptable
        
        if !string.isEmpty {
            let charset = CharacterSet(charactersIn: string)
            guard charset.isSubset(of: acceptableCharactersForKey) else {
                // In that case, the only acceptable situation is when all the fields are empty and we are pasting 32 characters in the first field.
                guard internalTextFields.first == textField else { return false }
                tryPasteAllCharactersAtOnceAction(string)
                return false
            }
        }
        
        // Make sure the text field will not contain more than 4 characters
        
        guard let textFieldText = textField.text, let rangeOfTextToReplace = Range(range, in: textFieldText) else {
            return false
        }
        
        let substringToReplace = textFieldText[rangeOfTextToReplace]
        let textFieldCountAfterReplacement = textFieldText.count - substringToReplace.count + string.count

        if textFieldCountAfterReplacement < 5 {
            // This is typical
            return true
        } else {
            // In that case, the only acceptable situation is when all the fields are empty and we are pasting 32 characters in the first field.
            guard internalTextFields.first == textField else { return false }
            tryPasteAllCharactersAtOnceAction(string)
            return false
        }

    }

    
    private func tryPasteAllCharactersAtOnceAction(_ string: String) {
        let filteredString = String(string.unicodeScalars.filter({
            acceptableCharactersForKey.contains($0)
        }))
        guard filteredString.utf8.count == 32 else { return }
        let allStrings = filteredString.byFour.map { String($0) }
        guard allStrings.count == 8 else { return }
        let allStringsAreComplete = allStrings.allSatisfy { $0.count == 4 }
        guard allStringsAreComplete else { return }
        for i in 0..<8 {
            internalTextFields[i]?.text = allStrings[i]
        }
        checkKeyCandidateIfPossible()
    }

    func restoreBackupNowAction() {
        assert(Thread.isMainThread)
        switch self.keyStatusReport {
        case .fullBackupRecovered(backupRequestIdentifier: let backupRequestIdentifier, fullBackupDate: _):
            DispatchQueue(label: "Queue for requesting a backup restore").async { [weak self] in
                self?.delegate?.userWantsToRestoreBackupIdentifiedByRequestUuid(backupRequestIdentifier)
            }
        default:
            assertionFailure()
        }
    }
}



struct BackupKeyVerifierView: View {
    
    @ObservedObject fileprivate var backupKeyTester: BackupKeyTester
    let dismissAction: () -> Void
    let dismissThenGenerateNewBackupKeyAction: () -> Void
    
    var body: some View {
        BackupKeyVerifierInnerView(keyStatusReport: backupKeyTester.keyStatusReport,
                                   isInBackupRecoveryMode: backupKeyTester.isInBackupRecoveryMode,
                                   disableTextFields: backupKeyTester.currentlyCheckingKey,
                                   internalTextFieldWasCreatedAction: backupKeyTester.internalTextFieldCreated,
                                   generateNewBackupKeyNowAction: dismissThenGenerateNewBackupKeyAction,
                                   restoreBackupNowAction: backupKeyTester.restoreBackupNowAction,
                                   dismissAction: dismissAction)
    }
    
}


fileprivate struct BackupKeyVerifierInnerView: View {
    
    let keyStatusReport: BackupKeyTester.KeyStatusReportType?
    let isInBackupRecoveryMode: Bool
    let disableTextFields: Bool
    let internalTextFieldWasCreatedAction: (Int, UITextField) -> Void
    let generateNewBackupKeyNowAction: () -> Void
    let restoreBackupNowAction: () -> Void
    let dismissAction: () -> Void
    @State private var showRegenerateKeyAlert = false
    
    private var okButtonInsteadOfCancel: Bool {
        switch keyStatusReport {
        case .backupKeyVerificationSucceded:
            return true
        default:
            return false
        }
    }
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack(spacing: 16) {
                    ObvCardView {
                        HStack {
                            Text("Please enter all the characters of your backup key.")
                                .font(.body)
                            Spacer()
                        }
                    }
                    BackupKeyAllTextFields(disable: disableTextFields,
                                           internalTextFieldWasCreatedAction: internalTextFieldWasCreatedAction)
                    if let keyStatusReport = self.keyStatusReport {
                        KeyStatusReportView(keyStatusReport: keyStatusReport)
                            .transition(.scale)
                            .animation(.spring())
                            
                    }
                    if isInBackupRecoveryMode {
                        switch keyStatusReport {
                        case .fullBackupRecovered:
                            OlvidButton(style: .blue,
                                        title: Text("Restore this backup"),
                                        systemIcon: .flameFill,
                                        action: restoreBackupNowAction)
                        default:
                            EmptyView()
                        }
                    } else {
                        switch keyStatusReport {
                        case .backupKeyVerificationSucceded:
                            EmptyView()
                        default:
                            OlvidButton(style: .standard,
                                        title: Text("Forgot your backup key?"),
                                        systemIcon: .questionmarkCircleFill,
                                        action: { showRegenerateKeyAlert = true })
                                .actionSheet(isPresented: $showRegenerateKeyAlert) {
                                    ActionSheet(title: Text("Generate new backup key?"),
                                                message: Text("Please note that generating a new backup key will invalidate all your previous backups. If you generate a new backup key, please create a fresh backup right afterwards."),
                                                buttons: [
                                                    Alert.Button.destructive(Text("Generate new backup key now"), action: generateNewBackupKeyNowAction),
                                                    Alert.Button.cancel(),
                                                ])
                                }
                        }
                        OlvidButton(style: okButtonInsteadOfCancel ? .blue : .standard,
                                    title: Text(okButtonInsteadOfCancel ? CommonString.Word.Ok : CommonString.Word.Cancel),
                                    systemIcon: okButtonInsteadOfCancel ? .checkmarkCircleFill : .xmarkCircleFill,
                                    action: dismissAction)
                    }
                    Spacer()
                }.padding()
            }
        }
        .navigationBarTitle(Text(isInBackupRecoveryMode ? "Enter backup key" : "Verify backup key"),
                            displayMode: isInBackupRecoveryMode ? .large : .inline)
    }
    
}


fileprivate struct KeyStatusReportView: View {
    
    let keyStatusReport: BackupKeyTester.KeyStatusReportType
        
    private var imageSystemName: String {
        switch keyStatusReport {
        case .backupKeyVerificationSucceded,
             .fullBackupRecovered:
            return "checkmark.circle.fill"
        case .backupKeyVerificationFailed,
             .fullBackupCouldNotBeRecovered,
             .couldNotReadBackupFileData:
            return "exclamationmark.circle.fill"
        }
    }
    
    private var imageColor: Color {
        switch keyStatusReport {
        case .backupKeyVerificationSucceded,
             .fullBackupRecovered:
            return .green
        case .backupKeyVerificationFailed,
             .fullBackupCouldNotBeRecovered,
             .couldNotReadBackupFileData:
            return .red
        }
    }
    
    private var localizedTitle: Text {
        switch keyStatusReport {
        case .backupKeyVerificationSucceded: return Text("The backup key is correct")
        case .backupKeyVerificationFailed: return Text("The backup key is incorrect")
        case .fullBackupCouldNotBeRecovered: return Text("The backup could not be recovered")
        case .fullBackupRecovered(fullBackupDate: _): return Text("The backup key is correct")
        case .couldNotReadBackupFileData: return Text("The backup file could not be read")
        }
    }
    
    private var localizedDescription: Text? {
        switch keyStatusReport {
        case .backupKeyVerificationSucceded,
             .backupKeyVerificationFailed,
             .couldNotReadBackupFileData,
             .fullBackupRecovered(fullBackupDate: _):
            return nil
        case .fullBackupCouldNotBeRecovered(error: let error):
            switch error {
            case .backupDataDecryptionFailed:
                return Text("The backuped data could not be decrypted.")
            case .macComparisonFailed, .macComputationFailed:
                return Text("The integrity check of the backuped data failed.")
            case .internalError(code: let code):
                return Text("The backup could not be recovered (error code: \(code)).")
            }
        }
    }
    
    
    var body: some View {
        ObvCardView {
            HStack {
                Image(systemName: imageSystemName)
                    .font(.system(size: 56.0))
                    .foregroundColor(imageColor)
                VStack(alignment: .leading, spacing: 4) {
                    localizedTitle
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    if let description = self.localizedDescription {
                        description
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    }
                }
                Spacer()
            }
        }
    }
    
}


fileprivate extension Collection {
    var byFour: [SubSequence] {
        var startIndex = self.startIndex
        let count = self.count
        let n = count/4 + count % 4
        return (0..<n).map { _ in
            let endIndex = index(startIndex, offsetBy: 4, limitedBy: self.endIndex) ?? self.endIndex
            defer { startIndex = endIndex }
            return self[startIndex..<endIndex]
        }
    }
}




struct BackupKeyVerifierInnerView_Previews: PreviewProvider {
    
    static private let acceptableCharactersForKey = CharacterSet.alphanumerics
    
    static var previews: some View {
        Group {
            BackupKeyVerifierInnerView(keyStatusReport: nil,
                                       isInBackupRecoveryMode: false,
                                       disableTextFields: false,
                                       internalTextFieldWasCreatedAction: { (_, _) in },
                                       generateNewBackupKeyNowAction: {},
                                       restoreBackupNowAction: {},
                                       dismissAction: {})
            BackupKeyVerifierInnerView(keyStatusReport: .backupKeyVerificationSucceded,
                                       isInBackupRecoveryMode: false,
                                       disableTextFields: false,
                                       internalTextFieldWasCreatedAction: { (_, _) in },
                                       generateNewBackupKeyNowAction: {},
                                       restoreBackupNowAction: {},
                                       dismissAction: {})
            BackupKeyVerifierInnerView(keyStatusReport: .backupKeyVerificationSucceded,
                                       isInBackupRecoveryMode: false,
                                       disableTextFields: false,
                                       internalTextFieldWasCreatedAction: { (_, _) in },
                                       generateNewBackupKeyNowAction: {},
                                       restoreBackupNowAction: {},
                                       dismissAction: {})
                .environment(\.colorScheme, .dark)
            BackupKeyVerifierInnerView(keyStatusReport: .backupKeyVerificationFailed,
                                       isInBackupRecoveryMode: false,
                                       disableTextFields: false,
                                       internalTextFieldWasCreatedAction: { (_, _) in },
                                       generateNewBackupKeyNowAction: {},
                                       restoreBackupNowAction: {},
                                       dismissAction: {})
            NavigationView {
                BackupKeyVerifierInnerView(keyStatusReport: .fullBackupCouldNotBeRecovered(error: .backupDataDecryptionFailed),
                                           isInBackupRecoveryMode: true,
                                           disableTextFields: false,
                                           internalTextFieldWasCreatedAction: { (_, _) in },
                                           generateNewBackupKeyNowAction: {},
                                           restoreBackupNowAction: {},
                                           dismissAction: {})
            }
            .environment(\.colorScheme, .dark)
            NavigationView {
                BackupKeyVerifierInnerView(keyStatusReport: nil,
                                           isInBackupRecoveryMode: false,
                                           disableTextFields: false,
                                           internalTextFieldWasCreatedAction: { (_, _) in },
                                           generateNewBackupKeyNowAction: {},
                                           restoreBackupNowAction: {},
                                           dismissAction: {})
            }
            .environment(\.colorScheme, .light)
        }
    }
}
