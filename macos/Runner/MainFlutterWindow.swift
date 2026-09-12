import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Design spec 2.5: the traffic lights sit in the same 48px bar as
  /// everything else, starting 20pt from the left with 8pt between them, and
  /// the bar reserves 84pt for them.
  ///
  /// AppKit parks the buttons for a standard ~28pt title bar, so in a 48pt bar
  /// they float noticeably high. There is no API for "centre these in a taller
  /// bar" — repositioning them by hand is the accepted approach, and it has to
  /// be redone whenever AppKit re-lays out the title bar (resize, full screen,
  /// theme change), which is what `layoutIfNeeded` below is for.
  private let titleBarHeight: CGFloat = 48
  private let trafficLightLeftInset: CGFloat = 20
  private let trafficLightSpacing: CGFloat = 8

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
    self.title = "Jellyfin Media Management Tool"
    DispatchQueue.main.async { [weak self] in
      self?.title = "Jellyfin Media Management Tool"
      self?.positionTrafficLights()
    }
  }

  override func layoutIfNeeded() {
    super.layoutIfNeeded()
    positionTrafficLights()
  }

  /// Centres the three standard buttons vertically in a [titleBarHeight] bar
  /// and spaces them to the design's 8pt gap.
  ///
  /// Every step is guarded: if AppKit ever stops handing back these buttons or
  /// their container, the app keeps the system placement rather than losing
  /// its window controls. A misplaced traffic light is a blemish; a crash on
  /// window layout is not something to risk for one.
  private func positionTrafficLights() {
    // Full screen hides the buttons with the menu bar; the Flutter side
    // reclaims the 84pt inset, and there is nothing to place here.
    guard !styleMask.contains(.fullScreen) else { return }

    let buttons = [
      standardWindowButton(.closeButton),
      standardWindowButton(.miniaturizeButton),
      standardWindowButton(.zoomButton),
    ].compactMap { $0 }
    guard buttons.count == 3, let container = buttons[0].superview else {
      return
    }

    var x = trafficLightLeftInset
    for button in buttons {
      let size = button.frame.size
      // The container's origin is its bottom-left and its top edge is the
      // window's top edge, so counting down from `bounds.height` is counting
      // down from the top of the window.
      let y = container.bounds.height - titleBarHeight / 2 - size.height / 2
      button.setFrameOrigin(NSPoint(x: x, y: y))
      x += size.width + trafficLightSpacing
    }
  }
}
