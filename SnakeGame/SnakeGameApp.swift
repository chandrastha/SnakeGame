//
//  SnakeGameApp.swift
//  SnakeGame
//
//  Created by Chandra Shrestha on 2026-02-24.
//
import SwiftUI
import FirebaseCore


class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    if AppFeatureFlags.isOnlineModeEnabled {
        FirebaseApp.configure()
    }

    return true
  }
}

@main
struct SnakeGameApp: App {
    // AppDelegate handles FirebaseApp.configure() via UIApplicationDelegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
