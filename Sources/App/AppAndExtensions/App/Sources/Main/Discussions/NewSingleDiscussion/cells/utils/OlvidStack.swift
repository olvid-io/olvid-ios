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

class ViewForOlvidStack: UIView {
    
    var showInStack: Bool {
        didSet {
            if showInStack != oldValue {
                isHidden = !showInStack
                assert(containingStack != nil)
                containingStack?.setNeedsUpdateConstraints()
            }
        }
    }
    
    // Attribute used in order to know if the view can be popped into a preview when long press occurs.
    // default value is `true` only if the view is displayed in the stack
    var isPopable: Bool {
        return showInStack
    }
    
    fileprivate(set) weak var containingStack: OlvidStack?
    
    override init(frame: CGRect) {
        self.showInStack = true
        super.init(frame: frame)
        self.isHidden = !self.showInStack
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var debugDescription: String {
        "\(super.debugDescription) showInStack: \(showInStack) isHidden: \(self.isHidden)"
    }
    
}


class OlvidStack: ViewForOlvidStack {
    
    fileprivate init(gap: CGFloat, debugName: String, showInStack: Bool) {
        self.gap = gap
        self.debugName = debugName
        super.init(frame: .zero)
        self.showInStack = showInStack
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    let debugName: String
    let gap: CGFloat

}


final class OlvidVerticalStackView: OlvidStack {
    
    enum Side {
        case leading
        case trailing
        case bothSides
    }
        
    init(gap: CGFloat, side: Side, debugName: String, showInStack: Bool) {
        self.side = side
        super.init(gap: gap, debugName: debugName, showInStack: showInStack)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var shownArrangedSubviews: [ViewForOlvidStack] {
        arrangedSubviews.filter({ $0.showInStack })
    }
    
    var arrangedSubviews: [ViewForOlvidStack] {
        allViewsAndBottomConstraints.map({ $0.view })
    }
    
    var popableSubviews: [ViewForOlvidStack] {
        arrangedSubviews.filter({ $0.isPopable })
    }

    private let side: Side
    private var allViewsAndBottomConstraints = [ViewAndBottomConstraints]()
    private var topConstraints = [OlvidLayoutConstraintWrapper]()
    private var bottomConstraints = [OlvidLayoutConstraintWrapper]()
    private var widthConstraints = [OlvidLayoutConstraintWrapper]()

    func addArrangedSubview(_ view: ViewForOlvidStack) {
        assert(view.superview == nil)
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.containingStack = self
        
        do {
            let constraint = view.topAnchor.constraint(equalTo: self.topAnchor)
            topConstraints.append(OlvidLayoutConstraintWrapper(constraint: constraint))
        }
        
        for viewAndBottomConstraints in allViewsAndBottomConstraints {
            viewAndBottomConstraints.constrainToLowerView(view, gap: gap)
        }
        
        do {
            let constraint = view.bottomAnchor.constraint(equalTo: self.bottomAnchor)
            constraint.priority = .defaultHigh
            bottomConstraints.append(OlvidLayoutConstraintWrapper(constraint: constraint))
        }
        
        switch side {
        case .leading:
            widthConstraints.append(contentsOf: [
                OlvidLayoutConstraintWrapper(constraint: view.leadingAnchor.constraint(equalTo: self.leadingAnchor)),
                OlvidLayoutConstraintWrapper(constraint: self.widthAnchor.constraint(greaterThanOrEqualTo: view.widthAnchor)),
            ])
        case .trailing:
            widthConstraints.append(contentsOf: [
                OlvidLayoutConstraintWrapper(constraint: view.trailingAnchor.constraint(equalTo: self.trailingAnchor)),
                OlvidLayoutConstraintWrapper(constraint: self.widthAnchor.constraint(greaterThanOrEqualTo: view.widthAnchor)),
            ])
        case .bothSides:
            widthConstraints.append(contentsOf: [
                OlvidLayoutConstraintWrapper(constraint: view.centerXAnchor.constraint(equalTo: self.centerXAnchor)),
                OlvidLayoutConstraintWrapper(constraint: self.widthAnchor.constraint(greaterThanOrEqualTo: view.widthAnchor)),
            ])
        }
        
        allViewsAndBottomConstraints.append(ViewAndBottomConstraints(view: view))
        
        setNeedsUpdateConstraints()
    }
    
    
    func insertArrangedSubview(_ view: ViewForOlvidStack, at stackIndex: Int) {
        assert(view.superview == nil)
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.containingStack = self

        do {
            let constraint = view.topAnchor.constraint(equalTo: self.topAnchor)
            topConstraints.insert(OlvidLayoutConstraintWrapper(constraint: constraint), at: stackIndex)
        }

        for viewAndBottomConstraints in allViewsAndBottomConstraints[0..<stackIndex] {
            viewAndBottomConstraints.constrainToLowerView(view, gap: gap)
        }

        for viewAndBottomConstraints in allViewsAndBottomConstraints[stackIndex..<allViewsAndBottomConstraints.count] {
            viewAndBottomConstraints.constrainToAboveView(view, gap: gap)
        }
        
        do {
            let constraint = view.bottomAnchor.constraint(equalTo: self.bottomAnchor)
            constraint.priority = .defaultHigh
            bottomConstraints.insert(OlvidLayoutConstraintWrapper(constraint: constraint), at: stackIndex)
        }

        switch side {
        case .leading:
            widthConstraints.append(contentsOf: [
                OlvidLayoutConstraintWrapper(constraint: view.leadingAnchor.constraint(equalTo: self.leadingAnchor)),
                OlvidLayoutConstraintWrapper(constraint: self.widthAnchor.constraint(greaterThanOrEqualTo: view.widthAnchor)),
            ])
        case .trailing:
            widthConstraints.append(contentsOf: [
                OlvidLayoutConstraintWrapper(constraint: view.trailingAnchor.constraint(equalTo: self.trailingAnchor)),
                OlvidLayoutConstraintWrapper(constraint: self.widthAnchor.constraint(greaterThanOrEqualTo: view.widthAnchor)),
            ])
        case .bothSides:
            widthConstraints.append(contentsOf: [
                OlvidLayoutConstraintWrapper(constraint: view.centerXAnchor.constraint(equalTo: self.centerXAnchor)),
                OlvidLayoutConstraintWrapper(constraint: self.widthAnchor.constraint(greaterThanOrEqualTo: view.widthAnchor)),
            ])
        }

        allViewsAndBottomConstraints.insert(ViewAndBottomConstraints(view: view), at: stackIndex)

        setNeedsUpdateConstraints()
    }

    
    override func updateConstraints() {
        
        var constraintsToActivate = Set<NSLayoutConstraint>()
        var constraintsToDeactivate = Set<NSLayoutConstraint>()
        
        if !topConstraints.isEmpty {
            var topConstraintFound = false
            for constraint in topConstraints {
                if topConstraintFound {
                    constraint.isActive = false
                    if constraint.isDirty {
                        constraintsToDeactivate.insert(constraint.constraint)
                    }
                } else {
                    if constraint.bothViewsAreShownInStack {
                        constraint.isActive = true
                        if constraint.isDirty {
                            constraintsToActivate.insert(constraint.constraint)
                        }
                        topConstraintFound = true
                    } else {
                        constraint.isActive = false
                        if constraint.isDirty {
                            constraintsToDeactivate.insert(constraint.constraint)
                        }
                    }
                }
            }
        }

        for viewAndBottomConstraints in allViewsAndBottomConstraints {
            let constraints = viewAndBottomConstraints.activateAppropriateConstraint()
            constraintsToDeactivate.formUnion(constraints.constraintsToDeactivate)
            if let constraint = constraints.constraintToActivate {
                constraintsToActivate.insert(constraint)
            }
            
        }
        
        if !bottomConstraints.isEmpty {
            var bottomConstraintFound = false
            for constraint in bottomConstraints.reversed() {
                if bottomConstraintFound {
                    constraint.isActive = false
                    if constraint.isDirty {
                        constraintsToDeactivate.insert(constraint.constraint)
                    }
                } else {
                    if constraint.bothViewsAreShownInStack {
                        constraint.isActive = true
                        if constraint.isDirty {
                            constraintsToActivate.insert(constraint.constraint)
                        }
                        bottomConstraintFound = true
                    } else {
                        constraint.isActive = false
                        if constraint.isDirty {
                            constraintsToDeactivate.insert(constraint.constraint)
                        }
                    }
                }
            }
        }

        for widthConstraint in widthConstraints {
            if widthConstraint.bothViewsAreShownInStack {
                widthConstraint.isActive = true
                if widthConstraint.isDirty {
                    constraintsToActivate.insert(widthConstraint.constraint)
                }
            } else {
                widthConstraint.isActive = false
                if widthConstraint.isDirty {
                    constraintsToDeactivate.insert(widthConstraint.constraint)
                }
            }
        }
        
        NSLayoutConstraint.deactivate(Array(constraintsToDeactivate))
        NSLayoutConstraint.activate(Array(constraintsToActivate))

        super.updateConstraints()
    }
    
}


private final class ViewAndBottomConstraints {
    
    let view: ViewForOlvidStack
    private(set) var bottomConstraints: [OlvidLayoutConstraintWrapper]
    
    init(view: ViewForOlvidStack) {
        self.view = view
        self.bottomConstraints = [OlvidLayoutConstraintWrapper]()
    }
    
    func constrainToLowerView(_ lowerView: ViewForOlvidStack, gap: CGFloat) {
        let constraint = lowerView.topAnchor.constraint(equalTo: view.bottomAnchor, constant: gap)
        bottomConstraints.append(OlvidLayoutConstraintWrapper(constraint: constraint))
    }
    
    func constrainToAboveView(_ aboveView: ViewForOlvidStack, gap: CGFloat) {
        let constraint = view.topAnchor.constraint(equalTo: aboveView.bottomAnchor, constant: gap)
        bottomConstraints.append(OlvidLayoutConstraintWrapper(constraint: constraint))
    }
    
    func activateAppropriateConstraint() -> (constraintToActivate: NSLayoutConstraint?, constraintsToDeactivate: [NSLayoutConstraint]) {

        guard !bottomConstraints.isEmpty else {
            return (nil, [])
        }

        var constraintToActivate: NSLayoutConstraint?
        var constraintsToDeactivate = [NSLayoutConstraint]()
        var constraintFound = false
        
        if view.showInStack {
            
            for constraint in bottomConstraints {
                if constraintFound {
                    constraint.isActive = false
                    if constraint.isDirty {
                        constraintsToDeactivate.append(constraint.constraint)
                    }
                } else {
                    if constraint.bothViewsAreShownInStack {
                        constraint.isActive = true
                        if constraint.isDirty {
                            assert(constraintToActivate == nil)
                            constraintToActivate = constraint.constraint
                        }
                        constraintFound = true
                    } else {
                        constraint.isActive = false
                        if constraint.isDirty {
                            constraintsToDeactivate.append(constraint.constraint)
                        }
                    }
                }
            }

        } else {

            for constraint in bottomConstraints {
                constraint.isActive = false
                if constraint.isDirty {
                    constraintsToDeactivate.append(constraint.constraint)
                }
            }

        }
                
        return (constraintToActivate, constraintsToDeactivate)
    }
}


private extension NSLayoutConstraint {
    
    var bothViewsAreShownInStack: Bool {
        guard let firstView = self.firstItem as? ViewForOlvidStack else { assertionFailure(); return false }
        guard let secondView = self.secondItem as? ViewForOlvidStack else { assertionFailure(); return false }
        return firstView.showInStack && secondView.showInStack
    }
    
}


final class OlvidHorizontalStackView: OlvidStack {
    
    
    enum Side {
        case top
        case bottom
        case bothSides
    }

    
    init(gap: CGFloat, side: Side, debugName: String, showInStack: Bool) {
        self.side = side
        super.init(gap: gap, debugName: debugName, showInStack: showInStack)
    }

    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    var shownArrangedSubviews: [ViewForOlvidStack] {
        arrangedSubviews.filter({ $0.showInStack })
    }
    
    var arrangedSubviews: [ViewForOlvidStack] {
        allViewsAndTrailingConstraints.map({ $0.view })
    }

    
    private let side: Side
    private var allViewsAndTrailingConstraints = [ViewAndTrailingConstraints]()
    private var leadingConstraints = [OlvidLayoutConstraintWrapper]()
    private var trailingConstraints = [OlvidLayoutConstraintWrapper]()
    private var heightConstraints = [OlvidLayoutConstraintWrapper]()

    func addArrangedSubview(_ view: ViewForOlvidStack) {
        assert(view.superview == nil)
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.containingStack = self

        do {
            let constraint = view.leadingAnchor.constraint(equalTo: self.leadingAnchor)
            leadingConstraints.append(OlvidLayoutConstraintWrapper(constraint: constraint))
        }
        
        for viewAndLeadingConstraints in allViewsAndTrailingConstraints {
            viewAndLeadingConstraints.constrainToNextView(view, gap: gap)
        }
        
        do {
            let constraint = view.trailingAnchor.constraint(equalTo: self.trailingAnchor)
            trailingConstraints.append(OlvidLayoutConstraintWrapper(constraint: constraint))
        }
        
        switch side {
        case .top:
            heightConstraints.append(contentsOf: [
                OlvidLayoutConstraintWrapper(constraint: view.topAnchor.constraint(equalTo: self.topAnchor)),
                OlvidLayoutConstraintWrapper(constraint: self.heightAnchor.constraint(greaterThanOrEqualTo: view.heightAnchor)),
            ])
        case .bottom:
            heightConstraints.append(contentsOf: [
                OlvidLayoutConstraintWrapper(constraint: view.bottomAnchor.constraint(equalTo: self.bottomAnchor)),
                OlvidLayoutConstraintWrapper(constraint: self.heightAnchor.constraint(greaterThanOrEqualTo: view.heightAnchor)),
            ])
        case .bothSides:
            heightConstraints.append(contentsOf: [
                OlvidLayoutConstraintWrapper(constraint: view.centerYAnchor.constraint(equalTo: self.centerYAnchor)),
                OlvidLayoutConstraintWrapper(constraint: self.heightAnchor.constraint(greaterThanOrEqualTo: view.heightAnchor)),
            ])
        }
        
        allViewsAndTrailingConstraints.append(ViewAndTrailingConstraints(view: view))
        
        setNeedsUpdateConstraints()
    }


    override func updateConstraints() {
        
        var constraintsToActivate = Set<NSLayoutConstraint>()
        var constraintsToDeactivate = Set<NSLayoutConstraint>()
        
        if !leadingConstraints.isEmpty {
            var leadingConstraintFound = false
            for constraint in leadingConstraints {
                if leadingConstraintFound {
                    constraint.isActive = false
                    if constraint.isDirty {
                        constraintsToDeactivate.insert(constraint.constraint)
                    }
                } else {
                    if constraint.bothViewsAreShownInStack {
                        constraint.isActive = true
                        if constraint.isDirty {
                            constraintsToActivate.insert(constraint.constraint)
                        }
                        leadingConstraintFound = true
                    } else {
                        constraint.isActive = false
                        if constraint.isDirty {
                            constraintsToDeactivate.insert(constraint.constraint)
                        }
                    }
                }
            }
        }

        for viewAndTrailingConstraints in allViewsAndTrailingConstraints {
            let constraints = viewAndTrailingConstraints.activateAppropriateConstraint()
            constraintsToDeactivate.formUnion(constraints.constraintsToDeactivate)
            if let constraint = constraints.constraintToActivate {
                constraintsToActivate.insert(constraint)
            }
        }
        
        if !trailingConstraints.isEmpty {
            var trailingConstraintFound = false
            for constraint in trailingConstraints.reversed() {
                if trailingConstraintFound {
                    constraint.isActive = false
                    if constraint.isDirty {
                        constraintsToDeactivate.insert(constraint.constraint)
                    }
                } else {
                    if constraint.bothViewsAreShownInStack {
                        constraint.isActive = true
                        if constraint.isDirty {
                            constraintsToActivate.insert(constraint.constraint)
                        }
                        trailingConstraintFound = true
                    } else {
                        constraint.isActive = false
                        if constraint.isDirty {
                            constraintsToDeactivate.insert(constraint.constraint)
                        }
                    }
                }
            }
        }
        
        for heightConstraint in heightConstraints {
            if heightConstraint.bothViewsAreShownInStack {
                heightConstraint.isActive = true
                if heightConstraint.isDirty {
                    constraintsToActivate.insert(heightConstraint.constraint)
                }
            } else {
                heightConstraint.isActive = false
                if heightConstraint.isDirty {
                    constraintsToDeactivate.insert(heightConstraint.constraint)
                }
            }
        }

        NSLayoutConstraint.deactivate(Array(constraintsToDeactivate))
        NSLayoutConstraint.activate(Array(constraintsToActivate))

        super.updateConstraints()

    }

}


private final class ViewAndTrailingConstraints {
    
    let view: ViewForOlvidStack
    private(set) var trailingConstraints: [OlvidLayoutConstraintWrapper]
    
    init(view: ViewForOlvidStack) {
        self.view = view
        self.trailingConstraints = [OlvidLayoutConstraintWrapper]()
    }
    
    func constrainToNextView(_ nextView: ViewForOlvidStack, gap: CGFloat) {
        let constraint = nextView.leadingAnchor.constraint(equalTo: view.trailingAnchor, constant: gap)
        constraint.priority -= 1
        trailingConstraints.append(OlvidLayoutConstraintWrapper(constraint: constraint))
    }
    
    func activateAppropriateConstraint() -> (constraintToActivate: NSLayoutConstraint?, constraintsToDeactivate: [NSLayoutConstraint]) {

        guard !trailingConstraints.isEmpty else {
            return (nil, [])
        }

        var constraintToActivate: NSLayoutConstraint?
        var constraintsToDeactivate = [NSLayoutConstraint]()
        var constraintFound = false
        
        for constraint in trailingConstraints {
            if constraintFound {
                constraint.isActive = false
                if constraint.isDirty {
                    constraintsToDeactivate.append(constraint.constraint)
                }
            } else {
                if constraint.bothViewsAreShownInStack {
                    constraint.isActive = true
                    if constraint.isDirty {
                        assert(constraintToActivate == nil)
                        constraintToActivate = constraint.constraint
                    }
                    constraintFound = true
                } else {
                    constraint.isActive = false
                    if constraint.isDirty {
                        constraintsToDeactivate.append(constraint.constraint)
                    }
                }
            }
        }
        
        return (constraintToActivate, constraintsToDeactivate)
    }
}


fileprivate class OlvidLayoutConstraintWrapper {
    
    var constraint: NSLayoutConstraint
    var isActive: Bool {
        didSet {
            isDirty = (isActive != oldValue)
        }
    }
    var isDirty: Bool

    var bothViewsAreShownInStack: Bool {
        constraint.bothViewsAreShownInStack
    }
    
    init(constraint: NSLayoutConstraint) {
        self.isActive = constraint.isActive
        self.constraint = constraint
        self.isDirty = false
        assert(!self.isActive)
    }
    
}
