import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 430, height: 900)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 380, height: 700)
    self.title = "Centwise"
    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }
}
