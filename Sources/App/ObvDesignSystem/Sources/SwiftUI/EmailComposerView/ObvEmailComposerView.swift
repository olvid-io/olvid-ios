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
import MessageUI


@MainActor
public protocol ObvEmailComposerViewDelegate {
    func emailComposerViewDidFinish(_ view: ObvEmailComposerView, result: Result<MFMailComposeResult, Error>)
}


public struct ObvEmailComposerView: UIViewControllerRepresentable {
    
    let model: Model
    let delegate: ObvEmailComposerViewDelegate
    
    public struct Model {
        let subject: String
        let toRecipients: [String]?
        let messageBody: String
        
        public init(subject: String, toRecipients: [String]?, messageBody: String) {
            self.subject = subject
            self.toRecipients = toRecipients
            self.messageBody = messageBody
        }
    }

    public init(model: Model, delegate: ObvEmailComposerViewDelegate) {
        self.model = model
        self.delegate = delegate
    }
    
    public func makeUIViewController(context: Context) -> some UIViewController {
        let mailComposeVC = MFMailComposeViewController()
        mailComposeVC.mailComposeDelegate = context.coordinator
        mailComposeVC.setSubject(model.subject)
        mailComposeVC.setToRecipients(model.toRecipients)
        mailComposeVC.setMessageBody(model.messageBody, isHTML: false)
        return mailComposeVC
    }
    
    public func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
    
    public static func canSendEmail() -> Bool {
        MFMailComposeViewController.canSendMail()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var parent: ObvEmailComposerView
        
        init(_ parent: ObvEmailComposerView) {
            self.parent = parent
        }
        
        public func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: (any Error)?) {
            
            if let error {
                Task {
                    await parent.delegate.emailComposerViewDidFinish(parent, result: .failure(error))
                }
                return
            }

            Task {
                await parent.delegate.emailComposerViewDidFinish(parent, result: .success(result))
            }
            
        }
        
    }
}


// MARK: - View modifier

struct ObvEmailComposerViewModifier: ViewModifier {
    
    @Binding var isPresented: Bool
    let model: ObvEmailComposerView.Model
    let delegate: any ObvEmailComposerViewDelegate
    
    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                ObvEmailComposerView(model: model, delegate: delegate)
            }
    }
    
}

extension View {
    
    public func obvEmailComposerView(isPresented: Binding<Bool>, model: ObvEmailComposerView.Model, delegate: any ObvEmailComposerViewDelegate) -> some View {
        self.modifier(ObvEmailComposerViewModifier(isPresented: isPresented, model: model, delegate: delegate))
    }
    
}
