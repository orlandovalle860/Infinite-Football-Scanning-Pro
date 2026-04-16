//
//  NavigationHelpers.swift
//  FootballScanningAI
//
//  PBA V2 — Pop to root from deep in the training stack (one-tap Home).
//

import SwiftUI
import Combine
import UIKit

// Show only the back chevron, not the previous screen’s title (e.g. "Home"). Avoids "2 homes" when the toolbar also has a house icon.
extension UINavigationController {
    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        for vc in viewControllers {
            vc.navigationItem.backButtonDisplayMode = .minimal
        }
    }
}

/// When set to true, the top view dismisses. That view’s parent appears and also sees the flag, so it dismisses too—cascading back to root. Root clears the flag in onAppear.
final class PopToRootTrigger: ObservableObject {
    @Published var request = false
}

/// Call from a view that has `@Environment(\.dismiss)` and `@EnvironmentObject var popToRootTrigger`. Sets the trigger so each level dismisses in turn until root.
func popToRoot(trigger: PopToRootTrigger, dismiss: DismissAction) {
    trigger.request = true
    dismiss()
}

/// Attach to any pushed view so that when pop-to-root was requested, this view dismisses when it appears (e.g. after the view above it dismissed).
func onAppearPopToRootIfRequested(trigger: PopToRootTrigger, dismiss: DismissAction) {
    if trigger.request {
        dismiss()
    }
}

extension View {
    @MainActor
    func asImage() -> UIImage {
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: self)
            renderer.scale = UIScreen.main.scale
            if let image = renderer.uiImage {
                return image
            }
        }

        // Fallback path: render through a hosting controller so first-tap shares
        // still produce an image even when ImageRenderer is cold.
        let controller = UIHostingController(rootView: self)
        let view = controller.view
        view?.backgroundColor = .clear

        let targetWidth = UIScreen.main.bounds.width * 0.8
        let fittingSize = CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height)
        let targetSize = controller.sizeThatFits(in: fittingSize)
        let safeSize = CGSize(
            width: max(1, targetSize.width),
            height: max(1, targetSize.height)
        )

        view?.bounds = CGRect(origin: .zero, size: safeSize)
        view?.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: safeSize, format: format).image { _ in
            view?.drawHierarchy(in: CGRect(origin: .zero, size: safeSize), afterScreenUpdates: true)
        }
    }
}
