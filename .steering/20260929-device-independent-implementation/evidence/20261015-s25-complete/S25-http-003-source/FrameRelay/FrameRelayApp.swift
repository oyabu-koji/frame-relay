//
//  FrameRelayApp.swift
//  FrameRelay
//
//  Created by Koji Oyabu on 2026/09/22.
//

import SwiftUI

@main
struct FrameRelayApp: App {
    @State private var composition = ProductComposition()
    var body: some Scene {
        WindowGroup {
            ContentView(composition: composition)
        }
    }
}
