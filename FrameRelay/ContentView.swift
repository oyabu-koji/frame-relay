//
//  ContentView.swift
//  FrameRelay
//
//  Created by Koji Oyabu on 2026/09/22.
//

import SwiftUI

struct ContentView: View {
    @Bindable var composition: ProductComposition
    @State private var showsExploration = false
    @State private var showsConnection = false
    @State private var showsCapture = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let library = composition.library {
                LibraryView(model: library, showCapture: { showsCapture = true },
                            showExploration: { showsExploration = true },
                            showConnection: { showsConnection = true })
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if composition.isOpening {
                                ProgressView("保存記録を開いています")
                            }
                            if let issue = composition.openingIssue {
                                Text(issue).accessibilityIdentifier("product.openFailure")
                                Button("再試行") { Task { await composition.open() } }
                                    .accessibilityIdentifier("product.retry")
                            }
                            Button("撮影基盤の探索") { showsExploration = true }
                                .accessibilityIdentifier("product.exploration")
                        }.padding()
                    }.navigationTitle("ライブラリ")
                }
            }
        }
            .task { await composition.open() }
            .sheet(isPresented: $showsCapture, onDismiss: {
                Task { await composition.capture?.leaveCapture(); await composition.presentationEnded() }
            }) {
                if let capture = composition.capture {
                    ProductCaptureView(model: capture, close: {
                        Task {
                            await capture.leaveCapture()
                            await composition.presentationEnded()
                            showsCapture = false
                        }
                    })
                    .interactiveDismissDisabled()
                }
            }
            .sheet(isPresented: $showsConnection) {
                if let connection = composition.connection { ConnectionView(model: connection) }
            }
            .sheet(isPresented: $showsExploration, onDismiss: {
                Task { await composition.exploration.stop(); await composition.presentationEnded() }
            }) {
                ExplorationView(model: composition.exploration)
                    .safeAreaInset(edge: .top) {
                        HStack {
                            Spacer()
                            Button("ライブラリへ戻る") {
                                Task { await composition.exploration.stop(); showsExploration = false }
                            }.padding()
                                .accessibilityIdentifier("product.closeExploration")
                        }
                    }
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: Binding(get: { composition.playback?.target != nil }, set: { _ in }),
                   onDismiss: { Task { await composition.presentationEnded() } }) {
                if let playback = composition.playback {
                    OriginalPlaybackView(model: playback, dismiss: {})
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    Task { await composition.enteredBackground() }
                }
            }
    }
}

#Preview {
    ContentView(composition: ProductComposition())
}
