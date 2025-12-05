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
import OSLog
import ObvAppTypes
import ObvSystemIcon
import ObvAccessibility

@MainActor
protocol PollFlowViewActionsProtocol: AnyObject {
    func userWantsToDismissPollFlowView()
    func userWantsToCreatePoll(poll: ObvPoll)
}

@available(iOS 17.0, *)
public struct PollCreationFlowView: View {
    
    let actions: any PollFlowViewActionsProtocol
    
    @State private var question: String = ""
    @State private var answers: [String] = ["", ""]
    @State private var validators: [Bool] = [true, true]
    @State private var multipleAnswers: Bool = false
    @State private var noAnswersAvailable: Bool = false
    @State private var expirationDateEnabled: Bool = false
    @State private var expirationDate = Date.now.addingTimeInterval(60 * 60)
    
    private var answersProvided: [String] {
        answers.filter { !$0.isEmpty }.compactMap { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
    }
    
    private var creationEnabled: Bool {
        !question.isEmpty && answersProvided.count >= 2 && !validators.contains(false)
    }
    
    private var questionAccessibilityAttributes: ObvAccessibilityAttributes {
        .init(label: String(localizedInThisBundle: "POLL_CREATE_QUESTION_TITLE"), value: question, actions: nil, hint: nil, traits: nil)
    }
    
    private func answerAccessibilityAttributes(for answer: String, index: Int) -> ObvAccessibilityAttributes {
        .init(label: answer, value: String(localizedInThisBundle: "POLL_ACCESSIBILITY_ANSWER_\(index + 1)"), actions: nil, hint: nil, traits: nil)
    }
    
    private var multipleChoiceAccessibilityAttributes: ObvAccessibilityAttributes {
        .init(label: String(localizedInThisBundle: "POLL_CREATE_ALLOWS_MULTIPLE_ANSWERS"),
              value: multipleAnswers ? String(localizedInThisBundle: "POLL_ACCESSIBILITY_ENABLED") : String(localizedInThisBundle: "POLL_ACCESSIBILITY_DISABLED"),
              actions: nil,
              hint: nil,
              traits: [.isToggle])
    }
    
    private var noneAccessibilityAttributes: ObvAccessibilityAttributes {
        .init(label: String(localizedInThisBundle: "POLL_CREATE_NO_ANSWERS_AVAILABLE"),
              value: noAnswersAvailable ? String(localizedInThisBundle: "POLL_ACCESSIBILITY_ENABLED") : String(localizedInThisBundle: "POLL_ACCESSIBILITY_DISABLED"),
              actions: nil,
              hint: nil,
              traits: [.isToggle])
    }
    
    private var dateAccessibilityAttributes: ObvAccessibilityAttributes {
        .init(label: String(localizedInThisBundle: "POLL_CREATE_ADD_EXPIRATION_DATE"),
              value: expirationDateEnabled ? String(localizedInThisBundle: "POLL_ACCESSIBILITY_ENABLED") : String(localizedInThisBundle: "POLL_ACCESSIBILITY_DISABLED"),
              actions: nil,
              hint: nil,
              traits: [.isToggle])
    }
    
    @ViewBuilder
    private var innerView: some View {
        Form {
            Section {
                TextField(text: $question, prompt: Text("POLL_CREATE_ASK_PLACEHOLDER"), axis: .vertical) {}
                    .multilineSubmit(for: $question)
                    .obvAccessibleComponent(accessibilityAttributes: questionAccessibilityAttributes)
            } header: {
                Text("POLL_CREATE_QUESTION_TITLE")
            }

            Section {
                ForEach(0 ..< answers.count, id: \.self) { index in
                    VStack(alignment: .leading) {
                        HStack() {
                            TextField(text: $answers[index], prompt: Text("POLL_CREATE_ADD_ANSWER_PLACEHOLDER"), axis: .vertical) {}
                                .moveDisabled(answers[index].isEmpty)
                                .modifier(AnswersManager(answers: $answers, validators: $validators, index: index))
                                .multilineSubmit(for: $answers[index])
                                .obvAccessibleComponent(accessibilityAttributes: answerAccessibilityAttributes(for: answers[index], index: index))
                            
                            if (!answers[index].isEmpty && answersProvided.count >= 2) {
                                Image(systemIcon: .line3Horizontal)
                                    .opacity(0.5)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .onMove { from, to in
                    answers.move(fromOffsets: from, toOffset: to)
                }
                
                if noAnswersAvailable {
                    Text("NO_ANSWERS_AVAILABLE")
                        .opacity(0.25)
                }
            } header: {
                Text("POLL_CREATE_ANSWERS_TITLE")
            } footer: {
                if !answersProvided.isEmpty && answersProvided.count < 2 {
                    Text("POLL_CREATE_ANSWERS_FOOTER")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .listRowInsets(EdgeInsets())
                }
            }
            
            Section {
                Toggle(isOn: $multipleAnswers) {
                    Text("POLL_CREATE_ALLOWS_MULTIPLE_ANSWERS")
                }
                .obvAccessibleComponent(accessibilityAttributes: multipleChoiceAccessibilityAttributes)
            }
            
            Section {
                Toggle(isOn: $noAnswersAvailable.animation()) {
                    Text("POLL_CREATE_NO_ANSWERS_AVAILABLE")
                }
                .obvAccessibleComponent(accessibilityAttributes: noneAccessibilityAttributes)
            }
            
            Section {
                Toggle(isOn: $expirationDateEnabled.animation()) {
                    Text("POLL_CREATE_ADD_EXPIRATION_DATE")
                }.onChange(of: expirationDateEnabled) { newValue in
                        self.expirationDate = Date.now.addingTimeInterval(60 * 60)
                }
                .obvAccessibleComponent(accessibilityAttributes: dateAccessibilityAttributes)

                if expirationDateEnabled {
                    DatePicker(selection: $expirationDate, in: Date.now..., displayedComponents: [.date, .hourAndMinute]) {
                        Text("POLL_CREATE_EXPIRATION_DATE_ENDING")
                    }
                    .datePickerStyle(.automatic)
                }
            }
        }
        .onTapGesture {
            hideKeyboard()
        }    
    }
    
    public var body: some View {
        NavigationStack {
            innerView
                .modifier(Toolbars(creationEnabled: creationEnabled, dismiss: {
                    actions.userWantsToDismissPollFlowView()
                }){
                    var candidates = answersProvided.compactMap { answer in
                        ObvPollCandidate(text: answer, uuid: UUID())
                    }
                    
                    if noAnswersAvailable {
                        candidates.append(ObvPollCandidate(text: String(localizedInThisBundle: "NO_ANSWERS_AVAILABLE"), uuid: .uuidOfPollCandidateNone))
                    }
                    let poll = ObvPoll(question: question.trimmingCharacters(in: .whitespaces),
                                       type: .string,
                                       expiration: expirationDateEnabled ? expirationDate : nil,
                                       multipleChoice: multipleAnswers,
                                       candidates: candidates)
                    actions.userWantsToCreatePoll(poll: poll)
                })
        }
    }
}

@available(iOS 17.0, *)
extension PollCreationFlowView {
    
    struct AnswersManager: ViewModifier {
        
        @Binding var answers: [String]
        @Binding var validators: [Bool]
        
        @FocusState private var FieldIsFocused: Bool
        var index: Int
        
        private var answersProvided: [String] {
            answers.filter { !$0.isEmpty }.compactMap { $0.trimmingCharacters(in: .whitespaces) }
        }
        
        private func answerAlreadyThere(for answer: String) -> Bool {
            answersProvided.count { $0 == answer.trimmingCharacters(in: .whitespaces) } >= 2
        }
        
        func body(content: Content) -> some View {
            VStack(alignment: .leading) {
                content
                    .onChange(of: self.answers[safe: index] ?? "") { newValue in
                        if newValue.isEmpty {
//                            hideKeyboard()
//                            withAnimation {
                                self.answers.remove(at: index)
                                self.validators.remove(at: index)
                                if self.answers.count <= 1 {
                                    self.answers.append("")
                                    self.validators.append(true)
                                }
//                            }
                        } else {
                            self.validators[index] = !answerAlreadyThere(for: newValue)
                            
                            if !self.answers.contains(where: { $0.isEmpty }) {
//                                withAnimation {
                                    self.answers.append("")
                                    self.validators.append(true)
//                                }
                            }
                        }
                        
                    }
                
                if !(validators[safe: index] ?? true) {
                    Text("POLL_CREATE_QUESTION_ALREADY_EXISTS")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

#if canImport(UIKit)
@available(iOS 17.0, *)
extension PollCreationFlowView {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

@available(iOS 17.0, *)
extension PollCreationFlowView {
    
    struct Toolbars: ViewModifier {
        
        var creationEnabled: Bool
        
        var dismiss: () -> ()
        var action: () -> ()
        
        func body(content: Content) -> some View {
            content
                .toolbar(content :{
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Text("POLL_CREATE_DISMISS")
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            action()
                        } label: {
                            Text("POLL_CREATE_ACTION")
                        }
                        .disabled(!creationEnabled)
                    }
                })
                .navigationTitle(Text("POLL_CREATE_TITLE"))
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#if DEBUG

@MainActor
private final class ActionsForPreviews: PollFlowViewActionsProtocol {
    func userWantsToDismissPollFlowView() {
        print("userWantsToDismissPollFlowView")
    }
    
    func userWantsToCreatePoll(poll: ObvPoll) {
        print("userWantsToCreatePoll: \(poll)")
    }
}

@MainActor
private let actionsForPreviews = ActionsForPreviews()

#Preview {
    if #available(iOS 17.0, *) {
        PollCreationFlowView(actions: actionsForPreviews)
    }
}
#endif
