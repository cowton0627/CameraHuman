//
//  RootTabBarController.swift
//  CameraHuman
//

import UIKit

final class RootTabBarController: UITabBarController {
    static let dockContentSize: CGFloat = 32
    private static let dockIconPointSize: CGFloat = 18
    private static let dockSidePadding: CGFloat = 12

    private struct DockItem {
        let title: String
        let imageName: String
        let selectedImageName: String
    }

    private let dockView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let dockSeparator = UIView()
    private let dockStackView = UIStackView()
    private var dockButtons: [UIButton] = []
    private var portraitDockConstraints: [NSLayoutConstraint] = []
    private var landscapeDockConstraints: [NSLayoutConstraint] = []
    private var usesLandscapeDock = false

    private let dockItems = [
        DockItem(title: "Camera", imageName: "camera", selectedImageName: "camera.fill"),
        DockItem(title: "Media", imageName: "film", selectedImageName: "film.fill"),
        DockItem(title: "Chat", imageName: "bubble.left.and.bubble.right", selectedImageName: "bubble.left.and.bubble.right.fill"),
        DockItem(title: "Settings", imageName: "gearshape", selectedImageName: "gearshape.fill")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        tabBar.isHidden = true
        view.backgroundColor = .black

        let cameraViewController = CameraViewController()
        let mediaViewController = MediaViewController()
        let chatViewController = ChatViewController()
        let settingsViewController = SettingsViewController()

        viewControllers = [
            cameraViewController,
            mediaViewController,
            chatViewController,
            settingsViewController
        ]

        configureDock()
        updateDockSelection()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateDockLayoutIfNeeded()
    }

    override var childForStatusBarHidden: UIViewController? {
        selectedViewController
    }

    private func configureDock() {
        dockView.translatesAutoresizingMaskIntoConstraints = false
        dockView.backgroundColor = .clear

        dockSeparator.translatesAutoresizingMaskIntoConstraints = false
        dockSeparator.backgroundColor = UIColor.white.withAlphaComponent(0.08)

        dockStackView.translatesAutoresizingMaskIntoConstraints = false
        dockStackView.spacing = 0
        dockStackView.distribution = .fillEqually
        dockStackView.alignment = .fill

        view.addSubview(dockView)
        dockView.contentView.addSubview(dockSeparator)
        dockView.contentView.addSubview(dockStackView)

        for index in dockItems.indices {
            let button = UIButton(type: .system)
            button.tag = index
            button.addTarget(self, action: #selector(dockButtonTapped(_:)), for: .touchUpInside)
            dockButtons.append(button)
            dockStackView.addArrangedSubview(button)
        }

        portraitDockConstraints = [
            dockView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dockView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dockView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dockView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Self.dockContentSize),

            dockSeparator.leadingAnchor.constraint(equalTo: dockView.leadingAnchor),
            dockSeparator.trailingAnchor.constraint(equalTo: dockView.trailingAnchor),
            dockSeparator.topAnchor.constraint(equalTo: dockView.topAnchor),
            dockSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            dockStackView.leadingAnchor.constraint(equalTo: dockView.safeAreaLayoutGuide.leadingAnchor, constant: Self.dockSidePadding),
            dockStackView.trailingAnchor.constraint(equalTo: dockView.safeAreaLayoutGuide.trailingAnchor, constant: -Self.dockSidePadding),
            dockStackView.topAnchor.constraint(equalTo: dockView.safeAreaLayoutGuide.topAnchor),
            dockStackView.bottomAnchor.constraint(equalTo: dockView.safeAreaLayoutGuide.bottomAnchor)
        ]

        landscapeDockConstraints = [
            dockView.topAnchor.constraint(equalTo: view.topAnchor),
            dockView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dockView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dockView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Self.dockContentSize),

            dockSeparator.topAnchor.constraint(equalTo: dockView.topAnchor),
            dockSeparator.bottomAnchor.constraint(equalTo: dockView.bottomAnchor),
            dockSeparator.leadingAnchor.constraint(equalTo: dockView.leadingAnchor),
            dockSeparator.widthAnchor.constraint(equalToConstant: 0.5),

            dockStackView.leadingAnchor.constraint(equalTo: dockView.safeAreaLayoutGuide.leadingAnchor),
            dockStackView.trailingAnchor.constraint(equalTo: dockView.safeAreaLayoutGuide.trailingAnchor),
            dockStackView.topAnchor.constraint(equalTo: dockView.safeAreaLayoutGuide.topAnchor, constant: Self.dockSidePadding),
            dockStackView.bottomAnchor.constraint(equalTo: dockView.safeAreaLayoutGuide.bottomAnchor, constant: -Self.dockSidePadding)
        ]

        updateDockLayoutIfNeeded(force: true)
    }

    @objc private func dockButtonTapped(_ sender: UIButton) {
        selectedIndex = sender.tag
        updateDockSelection()
        updateSelectedControllerInsets()
    }

    private func updateDockLayoutIfNeeded(force: Bool = false) {
        let shouldUseLandscapeDock = view.bounds.width > view.bounds.height
        guard force || shouldUseLandscapeDock != usesLandscapeDock else { return }

        NSLayoutConstraint.deactivate(usesLandscapeDock ? landscapeDockConstraints : portraitDockConstraints)
        NSLayoutConstraint.activate(shouldUseLandscapeDock ? landscapeDockConstraints : portraitDockConstraints)
        usesLandscapeDock = shouldUseLandscapeDock

        dockStackView.axis = shouldUseLandscapeDock ? .vertical : .horizontal
        updateDockSelection()
        updateSelectedControllerInsets()
    }

    private func updateDockSelection() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: Self.dockIconPointSize, weight: .regular)

        for (index, button) in dockButtons.enumerated() {
            let item = dockItems[index]
            let isSelected = index == selectedIndex
            let symbolName = isSelected ? item.selectedImageName : item.imageName
            let image = UIImage(systemName: symbolName, withConfiguration: symbolConfig)
            let foreground: UIColor = isSelected ? .white : UIColor.white.withAlphaComponent(0.45)

            if #available(iOS 15.0, *) {
                var configuration = UIButton.Configuration.plain()
                configuration.image = image
                configuration.title = nil
                configuration.contentInsets = .zero
                configuration.baseForegroundColor = foreground
                button.configuration = configuration
            } else {
                button.setImage(image, for: .normal)
                button.setTitle(nil, for: .normal)
                button.tintColor = foreground
                button.backgroundColor = .clear
            }
        }
    }

    private func updateSelectedControllerInsets() {
        let bottomInset: CGFloat = usesLandscapeDock ? 0 : Self.dockContentSize
        let rightInset: CGFloat = usesLandscapeDock ? Self.dockContentSize : 0
        let inset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: rightInset)

        for controller in viewControllers ?? [] {
            controller.additionalSafeAreaInsets = inset
        }
    }
}
