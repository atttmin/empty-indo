//
//  EmptyApp.swift
//  Empty
//

import SwiftData
import SwiftUI

@main
struct EmptyApp: App {
    @StateObject private var appSession = AppSession()

    var body: some Scene {
        #if os(macOS)
        // The Mac "深读工作台": hidden title bar so the sidebar runs the
        // full window height, traffic lights floating over it.
        WindowGroup {
            MacRootView()
                .id(appSession.containerRevision)
                .environmentObject(appSession)
        }
        .modelContainer(appSession.container)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        #else
        WindowGroup {
            IOSRootView()
                .id(appSession.containerRevision)
                .environmentObject(appSession)
        }
        .modelContainer(appSession.container)
        #endif
    }
}
