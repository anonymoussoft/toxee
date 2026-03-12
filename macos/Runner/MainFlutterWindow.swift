import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
    super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    // Set window background color to white as early as possible
    // This prevents black background flash on startup
    self.backgroundColor = NSColor.white
    self.isOpaque = true
  }
  
  override func awakeFromNib() {
    // Ensure background color is set (in case awakeFromNib is called before init)
    self.backgroundColor = NSColor.white
    self.isOpaque = true
    
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    super.awakeFromNib()
  }
}
