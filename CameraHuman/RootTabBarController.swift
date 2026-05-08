//
//  RootTabBarController.swift
//  CameraHuman
//

import UIKit

final class RootTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let cameraViewController: CameraViewController = CameraViewController()
        cameraViewController.tabBarItem = UITabBarItem(
            title: "相機",
            image: UIImage(systemName: "camera"),
            selectedImage: UIImage(systemName: "camera.fill")
        )

        let soundViewController: SoundViewController = SoundViewController()
        soundViewController.tabBarItem = UITabBarItem(
            title: "聲音",
            image: UIImage(systemName: "waveform"),
            selectedImage: UIImage(systemName: "waveform.circle.fill")
        )

        viewControllers = [
            cameraViewController,
            soundViewController
        ]
        configureAppearance()
    }

    private func configureAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground

        let normalColor = UIColor.systemGray
        let selectedColor = UIColor.systemBlue

        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]

        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        } else {
            // Fallback on earlier versions
        }
        tabBar.tintColor = selectedColor
        tabBar.unselectedItemTintColor = normalColor
        tabBar.isTranslucent = false
    }
}
