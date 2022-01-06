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

@available(iOS 14.0, *)
class UIButtonViewController: UIViewController {

    var hostingController: UIHostingController<AnyView> = UIHostingController(rootView: AnyView(EmptyView()))

    let menuTitle: String
    var actions: [UIAction]

    init(menuTitle: String, actions: [UIAction]) {
        self.menuTitle = menuTitle
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    lazy var button: UIButton = {
        let b = UIButton()
        b.showsMenuAsPrimaryAction = true
        b.menu = UIMenu(title: menuTitle, children: actions)
        return b
    }()

    func updateAction(with actions: [UIAction]) {
        self.actions = actions
        button.menu = UIMenu(title: menuTitle, children: actions)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addSubview(self.button)
        self.button.translatesAutoresizingMaskIntoConstraints = false
        self.view.pinAllSidesToSides(of: self.button)
        
        self.button.addSubview(hostingController.view)
        self.hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        self.button.pinAllSidesToSides(of: self.hostingController.view)
        self.hostingController.willMove(toParent: self)
        self.addChild(self.hostingController)
        self.hostingController.didMove(toParent: self)
        
        hostingController.view.backgroundColor = .clear
    }
    
}

@available(iOS 14.0, *)
struct UIButtonWrapper<Content: View>: UIViewControllerRepresentable {

    let title: String?
    let actions: [UIAction]
    let content: Content

    init(title: String?, actions: [UIAction], @ViewBuilder content: () -> Content) {
        self.title = title
        self.actions = actions
        self.content = content()
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<UIButtonWrapper>) -> UIButtonViewController {
        let vc = UIButtonViewController(menuTitle: title ?? "", actions: actions)
        vc.hostingController.rootView = AnyView(self.content)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIButtonViewController, context: UIViewControllerRepresentableContext<UIButtonWrapper>) {
        uiViewController.hostingController.rootView = AnyView(self.content)
        uiViewController.updateAction(with: actions)
    }
}

@available(iOS 14.0, *)
struct UIButtonWrapper_Previews: PreviewProvider {

    static var cameraButtonActions: [UIAction] {
        return  [
            UIAction(title: NSLocalizedString("TAKE_PICTURE", comment: "")) { _ in },
            UIAction(title: NSLocalizedString("CHOOSE_PICTURE", comment: "")) { _ in },
            UIAction(title: NSLocalizedString("REMOVE_PICTURE", comment: "")) { _ in }
        ]
    }
    
    static var previews: some View {
        UIButtonWrapper(title: "Test", actions: UIButtonWrapper_Previews.cameraButtonActions) {
            Image(systemName: "camera.circle.fill")
                .foregroundColor(.blue)
                .font(.system(size: 50))
                .scaledToFill()
        }
        .frame(width: 100, height: 100, alignment: .center)
    }
}
