//
//  NHL_EdgeApp.swift
//  NHL Edge
//
//  Created by Evan Thomas on 1/18/26.
//

import SwiftUI

@main
struct NHL_EdgeApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
    }
}
