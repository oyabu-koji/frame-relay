//
//  ContentView.swift
//  FrameRelay
//
//  Created by Koji Oyabu on 2026/09/22.
//

import SwiftUI

struct ContentView: View {
    @State private var model = ExplorationComposition.makeModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ExplorationView(model: model)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    Task { await model.stop() }
                }
            }
    }
}

#Preview {
    ContentView()
}
