import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Open at a comfortable default size, centered, instead of the small nib
    // default. The user can still resize.
    let defaultSize = NSSize(width: 1280, height: 820)
    if let screen = NSScreen.main {
      let visible = screen.visibleFrame
      let origin = NSPoint(
        x: visible.midX - defaultSize.width / 2,
        y: visible.midY - defaultSize.height / 2
      )
      self.setFrame(NSRect(origin: origin, size: defaultSize), display: true)
    } else {
      self.setContentSize(defaultSize)
    }
    self.minSize = NSSize(width: 1000, height: 680)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // Set the window title after the nib/Flutter setup so it isn't overwritten
    // by the product name; reassert next run-loop turn to be safe.
    self.title = "Jellyfin Organizer"
    DispatchQueue.main.async { [weak self] in
      self?.title = "Jellyfin Organizer"
    }
  }
}
