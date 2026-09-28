import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSOpenPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Finder 扩展无法直接显示 UI，故由本 App 代其弹出文件夹选择器
        let requestURL = Self.realHome().appendingPathComponent(".finderquickactions/request.json")
        guard let data = try? Data(contentsOf: requestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [String], !items.isEmpty,
              let action = json["action"] as? String else {
            NSApp.terminate(nil)
            return
        }
        try? FileManager.default.removeItem(at: requestURL)

        let move = (action == "move")
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = move ? "选择要移动到的文件夹" : "选择要复制到的文件夹"
        panel.prompt = move ? "移动到这里" : "复制到这里"
        self.panel = panel

        guard panel.runModal() == .OK, let destination = panel.url else {
            NSApp.terminate(nil)
            return
        }

        let fm = FileManager.default
        var failure: String?
        for path in items {
            let source = URL(fileURLWithPath: path)
            let target = Self.uniqueDestination(for: source, in: destination)
            do {
                if move {
                    try fm.moveItem(at: source, to: target)
                } else {
                    try fm.copyItem(at: source, to: target)
                }
            } catch {
                failure = error.localizedDescription
                break
            }
        }
        if let failure {
            let alert = NSAlert()
            alert.messageText = "右键助手"
            alert.informativeText = (move ? "移动" : "复制") + "失败：" + failure
            alert.runModal()
        }
        NSApp.terminate(nil)
    }

    /// 沙盒下 homeDirectoryForCurrentUser 指向容器目录，需用 getpwuid 取真实主目录
    private static func realHome() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func uniqueDestination(for item: URL, in dir: URL) -> URL {
        let fm = FileManager.default
        let name = item.lastPathComponent
        let ext = item.pathExtension
        let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var candidate = dir.appendingPathComponent(name)
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)")
            index += 1
        }
        return candidate
    }
}