import Cocoa
import FinderSync
import OSLog
import UniformTypeIdentifiers

/// Finder 右键增强工具：扩展主体
final class FinderSync: FIFinderSync {

    private static let log = Logger(subsystem: "com.finderquickactions.app", category: "FinderSync")

    private struct Config: Codable {
        var targetFolders: [String] = []
    }

    override init() {
        super.init()
        // 监控整个文件系统，从而在任意目录/任意选中项上弹出菜单
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - 配置访问

    /// 沙盒下 homeDirectoryForCurrentUser 会指向容器目录，必须用 getpwuid 取真实主目录
    private var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private var configURL: URL {
        realHome.appendingPathComponent(".finderquickactions/config.json")
    }

    private var templateDir: URL {
        realHome.appendingPathComponent(".finderquickactions/templates")
    }

    private func loadTargetFolders() -> [URL] {
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(Config.self, from: data),
           !config.targetFolders.isEmpty {
            Self.log.info("已加载配置，目标数=\(config.targetFolders.count) 来自 \(self.configURL.path, privacy: .public)")
            return config.targetFolders.map(URL.init(fileURLWithPath:))
        }
        // 缺省目标：下载 / 文稿 / 桌面
        Self.log.info("未找到配置，使用缺省目标（真实主目录=\(self.realHome.path, privacy: .public)）")
        let home = realHome
        return ["Downloads", "Documents", "Desktop"].map {
            home.appendingPathComponent($0)
        }
    }

    // MARK: - 菜单构建

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        Self.log.info("menu(for:) 被调用 kind=\(menuKind.rawValue)")
        switch menuKind {
        case .contextualMenuForContainer:
            return containerMenu()
        case .contextualMenuForItems:
            return filesMenu()
        default:
            return nil
        }
    }

    /// 空白处右键：新建文件（子菜单，每项独立 selector）
    private func containerMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let newItem = menu.addItem(withTitle: "新建文件", action: nil, keyEquivalent: "")
        newItem.isEnabled = true

        let sub = NSMenu()
        sub.autoenablesItems = false
        let defs: [(String, Selector, String)] = [
            ("TXT 文本", #selector(newTXT(_:)), "txt"),
            ("Markdown", #selector(newMD(_:)), "md"),
            ("Word 文档", #selector(newWord(_:)), "docx"),
            ("Excel 表格", #selector(newExcel(_:)), "xlsx"),
            ("PowerPoint 演示", #selector(newPPT(_:)), "pptx")
        ]
        for (i, d) in defs.enumerated() {
            let item = sub.addItem(withTitle: d.0, action: d.1, keyEquivalent: "")
            item.target = self
            item.tag = i
            item.image = Self.menuIcon(forExtension: d.2)
        }
        newItem.submenu = sub
        return menu
    }

    /// 取该扩展名对应的系统图标，并缩放到适合菜单的尺寸
    private static func menuIcon(forExtension ext: String) -> NSImage? {
        guard let type = UTType(filenameExtension: ext) else { return nil }
        let icon = NSWorkspace.shared.icon(for: type)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    /// 选中文件右键：复制到 / 移动到（两个子菜单）+ 复制路径
    private func filesMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let folders = loadTargetFolders()

        let copyItem = menu.addItem(withTitle: "复制到", action: nil, keyEquivalent: "")
        copyItem.isEnabled = true
        copyItem.submenu = folderSubmenu(folders: folders,
                                         action: #selector(copyToFolder(_:)),
                                         chooseAction: #selector(chooseCopyFolder(_:)))

        let moveItem = menu.addItem(withTitle: "移动到", action: nil, keyEquivalent: "")
        moveItem.isEnabled = true
        moveItem.submenu = folderSubmenu(folders: folders,
                                         action: #selector(moveToFolder(_:)),
                                         chooseAction: #selector(chooseMoveFolder(_:)))

        let pathItem = menu.addItem(withTitle: "复制绝对路径",
                                    action: #selector(copyFullPath(_:)),
                                    keyEquivalent: "")
        pathItem.target = self
        let nameItem = menu.addItem(withTitle: "复制文件名",
                                    action: #selector(copyFileName(_:)),
                                    keyEquivalent: "")
        nameItem.target = self
        return menu
    }

    /// 目标文件夹子菜单：本地化名称 + 文件夹图标
    private func folderSubmenu(folders: [URL], action: Selector, chooseAction: Selector) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        for (index, folder) in folders.enumerated() {
            let name = displayName(for: folder)
            let item = sub.addItem(withTitle: name, action: action, keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = Self.menuIcon(forFile: folder.path)
            Self.log.info("目标项：\(name, privacy: .public) <- \(folder.path, privacy: .public)")
        }
        sub.addItem(.separator())
        let choose = sub.addItem(withTitle: "选择文件夹…", action: chooseAction, keyEquivalent: "")
        choose.target = self
        choose.image = Self.genericFolderIcon()
        return sub
    }

    /// 文件夹的本地化显示名（如 下载/文稿/桌面）
    /// displayName(atPath:) 在扩展进程里不生效，故直接查系统的 SystemFolderLocalizations
    private func displayName(for folder: URL) -> String {
        let base = folder.lastPathComponent
        if let localized = Self.localizedFolderNames()[base] { return localized }
        let name = FileManager.default.displayName(atPath: folder.path)
        return name.isEmpty ? base : name
    }

    private static var cachedFolderNames: [String: String]?

    private static func localizedFolderNames() -> [String: String] {
        if let cached = cachedFolderNames { return cached }
        Self.log.info("系统语言偏好=\(Locale.preferredLanguages.joined(separator: ","), privacy: .public)")
        let fm = FileManager.default
        let root = "/System/Library/CoreServices/SystemFolderLocalizations"
        var result: [String: String] = [:]
        for lang in Locale.preferredLanguages {
            for cand in lprojCandidates(lang) {
                let path = "\(root)/\(cand).lproj/SystemFolderLocalizations.strings"
                if fm.fileExists(atPath: path),
                   let dict = NSDictionary(contentsOfFile: path) as? [String: String] {
                    result = dict
                    Self.log.info("使用本地化文件 \(cand).lproj，条目数=\(dict.count)")
                    break
                }
            }
            if !result.isEmpty { break }
        }
        cachedFolderNames = result
        return result
    }

    /// 把 zh-Hans-CN 这类标识符转成 zh_CN / zh_Hans / zh 等候选 lproj 名
    private static func lprojCandidates(_ id: String) -> [String] {
        let p = id.split(separator: "-").map(String.init)
        var out: [String] = []
        if p.count >= 3 { out.append("\(p[0])_\(p[2])") }
        if p.count >= 2 { out.append("\(p[0])_\(p[1])") }
        if let first = p.first { out.append(first) }
        out.append(id.replacingOccurrences(of: "-", with: "_"))
        return out
    }

    /// 取文件/文件夹的系统图标并缩放到菜单尺寸
    private static func menuIcon(forFile path: String) -> NSImage? {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    /// 通用文件夹图标（用于「选择文件夹…」）
    private static func genericFolderIcon() -> NSImage? {
        let icon = NSWorkspace.shared.icon(for: .folder)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    // MARK: - 动作：新建文件

    @objc func newTXT(_ s: NSMenuItem)  { Self.log.info("ACTION newTXT tag=\(s.tag)"); performNew("txt") }
    @objc func newMD(_ s: NSMenuItem)   { Self.log.info("ACTION newMD tag=\(s.tag)"); performNew("md") }
    @objc func newWord(_ s: NSMenuItem) { Self.log.info("ACTION newWord tag=\(s.tag)"); performNew("docx") }
    @objc func newExcel(_ s: NSMenuItem){ Self.log.info("ACTION newExcel tag=\(s.tag)"); performNew("xlsx") }
    @objc func newPPT(_ s: NSMenuItem)  { Self.log.info("ACTION newPPT tag=\(s.tag)"); performNew("pptx") }

    private func performNew(_ kind: String) {
        guard let dir = FIFinderSyncController.default().targetedURL() else {
            Self.log.error("targetedURL() 返回 nil，无法获取当前目录")
            presentError("无法获取当前目录（targetedURL 为空），无法新建文件。")
            return
        }
        Self.log.info("目标目录=\(dir.path, privacy: .public)")
        _ = createFile(ofKind: kind, in: dir)
    }

    private func createFile(ofKind kind: String, in dir: URL) -> Bool {
        let fm = FileManager.default
        switch kind {
        case "txt", "md":
            let ext = kind == "txt" ? "txt" : "md"
            return createPlainFile(extension: ext, in: dir, fm: fm)
        case "docx", "xlsx", "pptx":
            let template = templateDir.appendingPathComponent("template.\(kind)")
            guard let data = try? Data(contentsOf: template) else {
                Self.log.error("读取模板失败 \(template.path, privacy: .public)")
                presentError("未找到模板文件 \(template.path)")
                return false
            }
            let target = uniqueDestination(dir: dir, base: "未命名", ext: kind)
            do {
                try data.write(to: target)
                Self.log.info("已新建 \(target.path, privacy: .public)")
                return true
            } catch {
                Self.log.error("新建失败 \(target.path, privacy: .public)：\(error.localizedDescription)")
                presentError("新建失败：\(error.localizedDescription)")
                return false
            }
        default:
            Self.log.error("未知新建类型 \(kind, privacy: .public)")
            return false
        }
    }

    private func createPlainFile(extension ext: String, in dir: URL, fm: FileManager) -> Bool {
        let target = uniqueDestination(dir: dir, base: "未命名", ext: ext)
        let ok = fm.createFile(atPath: target.path, contents: Data(), attributes: nil)
        if !ok {
            Self.log.error("createFile 失败 \(target.path, privacy: .public)")
            presentError("新建失败：无法写入 \(target.path)")
        } else {
            Self.log.info("已新建 \(target.path, privacy: .public)")
        }
        return ok
    }

    /// 生成不覆盖已有文件的目标路径：未命名 / 未命名 2 / 未命名 3 …
    private func uniqueDestination(dir: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(index).\(ext)")
            index += 1
        }
        return candidate
    }

    // MARK: - 动作：移动 / 复制

    @objc func moveToFolder(_ sender: NSMenuItem) {
        Self.log.info("ACTION move tag=\(sender.tag)")
        let folders = loadTargetFolders()
        guard folders.indices.contains(sender.tag) else {
            Self.log.error("无效目标索引 tag=\(sender.tag)")
            return
        }
        operate(items: selectedItems(), destination: folders[sender.tag], move: true)
    }

    @objc func copyToFolder(_ sender: NSMenuItem) {
        Self.log.info("ACTION copy tag=\(sender.tag)")
        let folders = loadTargetFolders()
        guard folders.indices.contains(sender.tag) else {
            Self.log.error("无效目标索引 tag=\(sender.tag)")
            return
        }
        operate(items: selectedItems(), destination: folders[sender.tag], move: false)
    }

    @objc func chooseCopyFolder(_ sender: NSMenuItem) {
        Self.log.info("ACTION chooseCopy")
        chooseFolderThen(move: false)
    }

    @objc func chooseMoveFolder(_ sender: NSMenuItem) {
        Self.log.info("ACTION chooseMove")
        chooseFolderThen(move: true)
    }

    /// 扩展不能直接弹 UI，改为把请求交给容器 App，由它弹选择器并完成操作
    private func chooseFolderThen(move: Bool) {
        let items = selectedItems()
        guard !items.isEmpty else { return }
        let request: [String: Any] = [
            "action": move ? "move" : "copy",
            "items": items.map { $0.path }
        ]
        let dir = realHome.appendingPathComponent(".finderquickactions")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let requestURL = dir.appendingPathComponent("request.json")
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              (try? data.write(to: requestURL)) != nil else {
            Self.log.error("写入请求失败 \(requestURL.path, privacy: .public)")
            return
        }
        Self.log.info("已写入请求（\(move ? "移动" : "复制")，\(items.count) 项）")

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.finderquickactions.app") else {
            Self.log.error("找不到容器 App com.finderquickactions.app")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error {
                Self.log.error("启动容器 App 失败：\(error.localizedDescription)")
            } else {
                Self.log.info("已启动容器 App")
            }
        }
    }

    private func operate(items: [URL], destination: URL, move: Bool) {
        guard !items.isEmpty else { return }
        let fm = FileManager.default
        var failure: String?
        for item in items {
            let dest = uniqueCollisionFreeDestination(item: item, in: destination)
            do {
                if move {
                    try fm.moveItem(at: item, to: dest)
                } else {
                    try fm.copyItem(at: item, to: dest)
                }
            } catch {
                failure = error.localizedDescription
                break
            }
        }
        if let failure {
            presentError((move ? "移动" : "复制") + "失败：\(failure)")
        }
    }

    /// 目标已存在时自动改名，避免覆盖他人文件
    private func uniqueCollisionFreeDestination(item: URL, in dir: URL) -> URL {
        let fm = FileManager.default
        let name = item.lastPathComponent
        let ext = item.pathExtension
        let stem = (ext.isEmpty ? name : String(name.dropLast(ext.count + 1)))
        var candidate = dir.appendingPathComponent(name)
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(ext.isEmpty
                                                   ? "\(stem) \(index)"
                                                   : "\(stem) \(index).\(ext)")
            index += 1
        }
        return candidate
    }

    // MARK: - 动作：复制路径

    @objc func copyFullPath(_ sender: NSMenuItem) {
        copyToPasteboard(selectedItems().map(\.path).joined(separator: "\n"))
    }

    @objc func copyFileName(_ sender: NSMenuItem) {
        copyToPasteboard(selectedItems().map(\.lastPathComponent).joined(separator: "\n"))
    }

    private func copyToPasteboard(_ string: String) {
        guard !string.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    // MARK: - 辅助

    private func selectedItems() -> [URL] {
        FIFinderSyncController.default().selectedItemURLs() ?? []
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "右键助手"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}