import AppKit
import SwiftUI
import Synchronization
import Testing

final class NativeTextLayoutRecorder: Sendable {
    struct Measurement: Sendable {
        let isTruncated: Bool
        let lineCount: Int
    }

    let measurements = Mutex<[Measurement]>([])

    struct Renderer: TextRenderer {
        let recorder: NativeTextLayoutRecorder

        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            recorder.measurements.withLock {
                $0.append(Measurement(isTruncated: layout.isTruncated, lineCount: layout.count))
            }
            for line in layout { context.draw(line) }
        }
    }

    var renderer: Renderer { Renderer(recorder: self) }
}

@Test(arguments: [false, true]) @MainActor
func nativeTextLayoutDistinguishesWrappingFromTruncation(truncated: Bool) async throws {
    let recorder = NativeTextLayoutRecorder()
    let host = NSHostingView(
        rootView: Text("/work/alpha/long-project/important-path-suffix")
            .lineLimit(truncated ? 1 : nil).fixedSize(horizontal: false, vertical: true)
            .frame(width: 100).textRenderer(recorder.renderer))
    host.frame.size = host.fittingSize
    let window = await mountOffscreenNativePreview(host)
    defer { window.close() }
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let measurements = recorder.measurements.withLock { $0 }
    #expect(!measurements.isEmpty)
    #expect(measurements.allSatisfy { $0.isTruncated == truncated })
    #expect(measurements.allSatisfy { truncated ? $0.lineCount == 1 : $0.lineCount > 1 })
}
