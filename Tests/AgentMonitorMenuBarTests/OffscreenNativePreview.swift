import AppKit

@MainActor func mountOffscreenNativePreview(_ host: NSView) async -> NSWindow {
    let frame = host.frame
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.frame = frame
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    return window
}
