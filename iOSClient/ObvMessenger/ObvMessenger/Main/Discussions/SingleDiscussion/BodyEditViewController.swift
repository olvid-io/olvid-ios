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


final class BodyEditViewController: UIHostingController<BodyEditView>, BodyEditViewStoreDelegate {

    fileprivate let store: BodyEditViewStore
    let dismiss: () -> Void
    let send: (String?) -> Void

    init(currentBody: String?, dismiss: @escaping () -> Void, send: @escaping (String?) -> Void) {
        self.dismiss = dismiss
        self.send = send
        self.store = BodyEditViewStore(currentBody: currentBody)
        let view = BodyEditView(store: store)
        super.init(rootView: view)
        store.delegate = self
        self.isModalInPresentation = true
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.backgroundColor = .clear
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

protocol BodyEditViewStoreDelegate: AnyObject {
    var dismiss: () -> Void { get }
    var send: (String?) -> Void { get }
}


fileprivate final class BodyEditViewStore: ObservableObject {
    
    @Published var body: String
    let initialBody: String?
    
    weak var delegate: BodyEditViewStoreDelegate? = nil
    
    init(currentBody: String?) {
        self.initialBody = currentBody
        self.body = currentBody ?? ""
    }
    
    func dismissAction() {
        delegate?.dismiss()
    }
    
    func sendAction() {
        delegate?.send(body.mapToNilIfZeroLength())
    }
}


struct BodyEditView: View {
    
    @ObservedObject fileprivate var store: BodyEditViewStore
    
    var body: some View {
        BodyEditInnerView(text: $store.body,
                          initialBody: store.initialBody,
                          dismissAction: store.dismissAction,
                          sendAction: store.sendAction)
    }
    
}



struct BodyEditInnerView: View {
    
    @Binding var text: String
    let initialBody: String?
    let dismissAction: () -> Void
    let sendAction: () -> Void
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0.0) {
                Spacer()
                VStack(spacing: 0.0) {
                    Text("EDIT_YOUR_MESSAGE")
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                        .multilineTextAlignment(.center)
                        .font(.title)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                        .padding(.bottom, 4.0)
                    Text("UPDATE_YOUR_ALREADY_SENT_MESSAGE")
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .padding(.bottom, 8.0)
                    ZStack(alignment: Alignment(horizontal: .center, vertical: .center)) {
                        RoundedRectangle(cornerRadius: 10.0)
                            .foregroundColor(Color(AppTheme.shared.colorScheme.systemFill))
                        MultilineTextView(text: $text)
                            .padding(8.0)
                    }
                    .padding(.bottom, 16.0)
                    HStack {
                        OlvidButton(style: .standard, title: Text("Cancel"), systemIcon: .xmarkCircleFill, action: dismissAction)
                        OlvidButton(style: .blue, title: Text("Send"), systemIcon: .paperplaneFill, action: sendAction)
                            .disabled(text.trimmingWhitespacesAndNewlines().mapToNilIfZeroLength() == initialBody)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
        }
    }
}



fileprivate struct MultilineTextView: UIViewRepresentable {

    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isScrollEnabled = true
        view.isEditable = true
        view.isUserInteractionEnabled = true
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.delegate = context.coordinator
        return view
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text.isEmpty {
            uiView.text = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator($text)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        private var text: Binding<String>
        init(_ text: Binding<String>) {
            self.text = text
        }
        func textViewDidChange(_ textView: UITextView) {
            self.text.wrappedValue = textView.text
        }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            self.text.wrappedValue = textView.text // This  is used to catch predictive text change event
            return true // We always accept changes
        }
    }
}






struct BodyEditInnerView_Previews: PreviewProvider {
    static var previews: some View {
        BodyEditInnerView(text: .constant("Test"),
                          initialBody: "Foo",
                          dismissAction: {},
                          sendAction: {})
    }
}
