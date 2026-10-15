import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentMonitorMenuBar

@Test(.enabled(if: ProcessInfo.processInfo.environment["MENUBAR_PREVIEW_PATH"] != nil))
@MainActor func menuBarNativeLayoutRendersAtPopoverSize() async throws {
    let output = try #require(ProcessInfo.processInfo.environment["MENUBAR_PREVIEW_PATH"])
    let snapshot = try menuBarFixture()
    let model = MenuBarModel { receive in try await receive(snapshot) }
    model.open()
    await model.waitForCollection()
    _ = NSApplication.shared
    let host = NSHostingView(
        rootView: MenuBarView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 560)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: output))
    await model.stop()
}
