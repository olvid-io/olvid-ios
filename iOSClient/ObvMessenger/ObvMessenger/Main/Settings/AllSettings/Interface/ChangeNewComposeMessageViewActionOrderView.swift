/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

@available(iOS 15, *)
final class ChangeNewComposeMessageViewActionOrderViewController: UIHostingController<ChangeNewComposeMessageViewActionOrderView> {

    fileprivate let model: ChangeNewComposeMessageViewActionOrderViewModel
    init() {
        model = ChangeNewComposeMessageViewActionOrderViewModel()
        let view = ChangeNewComposeMessageViewActionOrderView(model: model)
        super.init(rootView: view)
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}

@available(iOS 15, *)
fileprivate final class ChangeNewComposeMessageViewActionOrderViewModel: ObservableObject {

    @ObservedObject var interfaceSettings = ObvMessengerInterfaceSettingsObservable()

}

@available(iOS 15, *)
struct ChangeNewComposeMessageViewActionOrderView: View {

    @ObservedObject fileprivate var model: ChangeNewComposeMessageViewActionOrderViewModel

    var body: some View {
        ChangeNewComposeMessageViewActionOrderInnerView(interfaceSettings: model.interfaceSettings)
    }

}

@available(iOS 15, *)
struct ChangeNewComposeMessageViewActionOrderInnerView: View {

    @ObservedObject var interfaceSettings: ObvMessengerInterfaceSettingsObservable

    @Environment(\.presentationMode) var presentationMode

    private var currentActionIsDefault: Bool {
        interfaceSettings.preferredComposeMessageViewActions == NewComposeMessageViewAction.defaultActions
    }

    private var floatingButtonModel: FloatingButtonModel {
        return FloatingButtonModel(title: CommonString.Word.Reset,
                                   systemIcon: .pencilSlash,
                                   isEnabled: !currentActionIsDefault) {
            withAnimation {
                interfaceSettings.preferredComposeMessageViewActions = NewComposeMessageViewAction.defaultActions
            }
        }
    }

    var body: some View {
        VStack {
            Form {
                Section {
                    ForEach(interfaceSettings.preferredComposeMessageViewActions.filter({ $0.canBeReordered }), id: \.self) { action in
                        Label(action.title, systemIcon: action.icon)
                            .listRowInsets(EdgeInsets())
                    }
                    .onMove(perform: move)
                    .padding(.leading, -24)
                } header: {
                    Text("NEW_COMPOSE_MESSAGE_VIEW_ACTION_ORDER_HEADER")
                } footer: {
                    Text("NEW_COMPOSE_MESSAGE_VIEW_ACTION_ORDER_FOOTER")
                }
                
            }
            .environment(\.editMode, .constant(EditMode.active))
            HStack {
                OlvidButton(style: .blue, title: Text(CommonString.Word.Reset), systemIcon: .pencilSlash) {
                    withAnimation {
                        interfaceSettings.preferredComposeMessageViewActions = NewComposeMessageViewAction.defaultActions
                    }
                }
                .disabled(currentActionIsDefault)
                OlvidButton(style: .blue, title: Text(CommonString.Word.Ok), systemIcon: .checkmark) {
                    presentationMode.wrappedValue.dismiss()
                }

            }
            .padding()
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var preferredComposeMessageViewActions = interfaceSettings.preferredComposeMessageViewActions
        preferredComposeMessageViewActions.move(fromOffsets: source, toOffset: destination)
        interfaceSettings.preferredComposeMessageViewActions = preferredComposeMessageViewActions
    }

}
