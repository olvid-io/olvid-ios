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

import UIKit
import CoreData
import UniformTypeIdentifiers
import os.log
import ObvUICoreData


@available(iOS 15.0, *)
final class ReplyToView: UIView {
    
    private let replyingToLabel = UILabel()
    private let bodyLabel = UILabel()
    private var xmarkButton: UIButton!
    private let horizontalStack = UIStackView()
    private let verticalStack = UIStackView()
    private let padding = CGFloat(8)
    private let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>
    private let buttonSize = CGFloat(44)
    private let imageSize = CGFloat(44)
    private let imageView = UIImageViewForHardLink()

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "ReplyToView")

    /// Implementing `UIViewWithThumbnailsForUTI`
    var imageForUTI = [String: UIImage]()

    weak var cacheDelegate: DiscussionCacheDelegate?

    init(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, cacheDelegate: DiscussionCacheDelegate?) {
        assert(cacheDelegate != nil)
        self.draftObjectID = draftObjectID
        self.cacheDelegate = cacheDelegate
        super.init(frame: .zero)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func setupInternalViews() {
                
        addSubview(horizontalStack)
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        horizontalStack.axis = .horizontal
        horizontalStack.alignment = .center
        
        horizontalStack.addArrangedSubview(verticalStack)
        verticalStack.axis = .vertical
        verticalStack.distribution = .fillProportionally
        verticalStack.alignment = .leading
        verticalStack.spacing = 4.0
        
        verticalStack.addArrangedSubview(replyingToLabel)
        replyingToLabel.font = UIFont.rounded(ofSize: 17.0, weight: .bold)
        replyingToLabel.textColor = .label
        
        verticalStack.addArrangedSubview(bodyLabel)
        bodyLabel.font = UIFont.preferredFont(forTextStyle: .body)
        bodyLabel.textColor = .secondaryLabel

        horizontalStack.addArrangedSubview(imageView)
        imageView.isHidden = true
        imageView.layer.cornerRadius = CGFloat(8.0)
        imageView.clipsToBounds = true
        
        let symbolConfig = UIImage.SymbolConfiguration(textStyle: .body)
        let xmark = UIImage(systemIcon: .xmarkCircleFill, withConfiguration: symbolConfig)!
        xmarkButton = UIButton.systemButton(with: xmark, target: self, action: #selector(xmarkButtonTapped))
        horizontalStack.addArrangedSubview(xmarkButton)

        let constraints = [
            horizontalStack.topAnchor.constraint(equalTo: topAnchor),
            horizontalStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            horizontalStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            horizontalStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),

            xmarkButton.widthAnchor.constraint(equalToConstant: buttonSize),
            xmarkButton.heightAnchor.constraint(equalToConstant: buttonSize),
            
            imageView.widthAnchor.constraint(equalToConstant: imageSize),
            imageView.heightAnchor.constraint(equalToConstant: imageSize),


        ]
        NSLayoutConstraint.activate(constraints)
        
    }
    

    private var hardlinkForFyleMessageJoinWithStatus = [TypeSafeManagedObjectID<FyleMessageJoinWithStatus>: HardLinkToFyle]()

    
    func configureWithMessage(_ message: PersistedMessage) {
        if let messageReceived = message as? PersistedMessageReceived {
            if let contact = messageReceived.contactIdentity {
                self.replyingToLabel.textColor = contact.cryptoId.colors.text
                self.replyingToLabel.text = MessageCellStrings.replyingTo(contact.customOrFullDisplayName)
            } else {
                self.replyingToLabel.textColor = .label
                self.replyingToLabel.text = NewSingleDiscussionViewController.Strings.replying
            }
        } else if message is PersistedMessageSent {
            self.replyingToLabel.textColor = .label
            self.replyingToLabel.text = NewSingleDiscussionViewController.Strings.replyingToYourself
        } else {
            self.replyingToLabel.textColor = .label
            self.replyingToLabel.text = NewSingleDiscussionViewController.Strings.replying
        }
        self.bodyLabel.text = message.textBody
        let size = CGSize(width: imageSize, height: imageSize)
        let readingRequiresUserAction = (message as? PersistedMessageReceived)?.readingRequiresUserAction ?? false
        if let fyleMessageJoinWithStatus = message.fyleMessageJoinWithStatus, !readingRequiresUserAction {
            for join in fyleMessageJoinWithStatus {
                if let hardlink = hardlinkForFyleMessageJoinWithStatus[join.typedObjectID], hardlink.hardlinkURL != nil {
                    setOrRequestImage(hardlink: hardlink, size: size)
                    imageView.isHidden = false
                    return
                }
            }
            // If we reach this point, we could not find a hardlink with a proper hardlinkURL
            for join in fyleMessageJoinWithStatus {
                if let hardlink = hardlinkForFyleMessageJoinWithStatus[join.typedObjectID] {
                    setOrRequestImage(hardlink: hardlink, size: size)
                    imageView.isHidden = false
                    return
                }
            }
            // If we reach this point, we could not find a hardlink
            imageView.reset()
            imageView.isHidden = false
            if let join = fyleMessageJoinWithStatus.first(where: { $0.fullFileIsAvailable }) ?? fyleMessageJoinWithStatus.first {
                let joinObjectID = join.typedObjectID
                if let fyleElements = join.fyleElement {
                    HardLinksToFylesNotifications.requestHardLinkToFyle(fyleElement: fyleElements) { result in
                        DispatchQueue.main.async { [weak self] in
                            switch result {
                            case .success(let hardlink):
                                self?.hardlinkForFyleMessageJoinWithStatus[joinObjectID] = hardlink
                                self?.setOrRequestImage(hardlink: hardlink, size: size)
                                self?.imageView.isHidden = false
                            case .failure(let error):
                                assertionFailure(error.localizedDescription)
                            }
                        }
                    }.postOnDispatchQueue()
                }
            }
        } else {
            imageView.isHidden = true
        }
    }
    
    
    @MainActor
    private func setOrRequestImage(hardlink: HardLinkToFyle, size: CGSize) {
        if let image = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: size) {
            imageView.setHardlink(newHardlink: hardlink, withImage: image)
        } else {
            imageView.setHardlink(newHardlink: hardlink, withImage: nil)
            Task {
                do {
                    let image = try await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: size)
                    imageView.setHardlink(newHardlink: hardlink, withImage: image)
                } catch {
                    os_log("The request for an image for the hardlink to fyle %{public}@ failed: %{public}@", log: Self.log, type: .error, hardlink.fyleURL.lastPathComponent, error.localizedDescription)
                }
            }
        }
    }
    
    
    @objc private func xmarkButtonTapped() {
        NewSingleDiscussionNotification.userWantsToRemoveReplyToMessage(draftObjectID: draftObjectID)
            .postOnDispatchQueue()
    }
}
