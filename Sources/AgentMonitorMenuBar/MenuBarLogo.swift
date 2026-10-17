import AppKit

@MainActor enum MenuBarLogo {
    static let resourceURL = Bundle.module.url(forResource: "agent-monitor", withExtension: "webp")
    // Sampling refreshes reuse this decoded artwork rather than loading the resource in the view body.
    static let image: NSImage? = {
        guard let resourceURL, let data = try? Data(contentsOf: resourceURL),
            let bitmap = NSBitmapImageRep(data: data)
        else { return nil }
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }()
}
