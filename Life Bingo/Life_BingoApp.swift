//
//  Life_BingoApp.swift
//  Life Bingo
//
//  Created by Jason Li on 2026-02-02.
//

import SwiftUI

@main
struct Life_BingoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
