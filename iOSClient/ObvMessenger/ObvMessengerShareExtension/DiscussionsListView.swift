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
  
import CoreData
import Foundation
import ObvTypes
import ObvUI
import ObvUICoreData
import OlvidUtils
import os.log
import SwiftUI


@available(iOS 16.0, *)
struct NewDiscussionsListView: UIViewControllerRepresentable, ObvErrorMaker {
    static let errorDomain: String = "NewDiscussionsListView"
    
    typealias UIViewControllerType = NewDiscussionsSelectionViewController

    private let viewModel: NewDiscussionsListViewModel
    
    init(ownedCryptoId: ObvCryptoId, discussionsViewModel: DiscussionsViewModel) {
        self.viewModel = NewDiscussionsListViewModel(ownedCryptoId: ownedCryptoId, discussionsViewModel: discussionsViewModel)
    }
    
    func makeUIViewController(context: Context) -> UIViewControllerType {
        
        let vcViewModel = NewDiscussionsSelectionViewController.ViewModel(
            viewContext: ObvStack.shared.viewContext,
            preselectedDiscussions: viewModel.selectedObjectIds,
            ownedCryptoId: viewModel.ownedCryptoId,
            attachSearchControllerToParent: true,
            buttonTitle: CommonString.Word.Choose,
            buttonSystemIcon: .checkmarkCircleFill)
        
        let vc = NewDiscussionsSelectionViewController(viewModel: vcViewModel, delegate: viewModel)

        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        // Updates the state of the specified view controller with new information from SwiftUI.
    }
}


@available(iOS 15.0, *)
struct DiscussionsListView: UIViewControllerRepresentable, ObvErrorMaker {
    static let errorDomain: String = "DiscussionsListView"
    
    typealias UIViewControllerType = DiscussionsSelectionViewController

    private let viewModel: DiscussionsListViewModel
    
    init(ownedCryptoId: ObvCryptoId, discussionsViewModel: DiscussionsViewModel) {
        self.viewModel = DiscussionsListViewModel(ownedCryptoId: ownedCryptoId, discussionsViewModel: discussionsViewModel)
    }
    
    func makeUIViewController(context: Context) -> UIViewControllerType {
        
        let vc = DiscussionsSelectionViewController(ownedCryptoId: viewModel.ownedCryptoId,
                                                    within: ObvStack.shared.viewContext,
                                                    preselectedDiscussions: viewModel.preselectedDiscussions,
                                                    delegate: viewModel,
                                                    acceptButtonTitle: CommonString.Word.Choose)

        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        // Updates the state of the specified view controller with new information from SwiftUI.
    }
}
