//
//  SnakeGameApp.swift
//  SnakeGame
//
//  Created by Chandra Shrestha on 2026-02-24.
//
import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        GameCenterManager.shared.authenticate()
        return true
    }
}

@main
struct SnakeGameApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
