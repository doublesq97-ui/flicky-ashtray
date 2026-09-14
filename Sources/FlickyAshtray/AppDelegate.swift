import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var petWindowController: PetWindowController!
    private var statusPanelController: StatusPanelController!
    private var controlPanelWindowController: ControlPanelWindowController!
    private var statusItem: NSStatusItem!
    private var countMenuItem: NSMenuItem!
    private var undoMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Flicky is a real macOS app with a normal control window. The desktop
        // pet may be hidden independently, but the app must remain discoverable
        // from the Dock as well as the menu bar.
        NSApp.setActivationPolicy(.regular)
        configureMainMenu()

        statusPanelController = StatusPanelController(model: model)
        let petView = PetSurfaceView(
            model: model,
            onHover: { [weak self] inside in
                guard let self else { return }
                self.statusPanelController.petHoverChanged(inside, relativeTo: self.petWindowController.frame)
            },
            onTogglePin: { [weak self] in
                guard let self else { return }
                self.statusPanelController.togglePinned(relativeTo: self.petWindowController.frame)
            },
            onShowControlPanel: { [weak self] in self?.showControlPanel() },
            onHide: { [weak self] in self?.hidePet() }
        )
        petWindowController = PetWindowController(model: model, rootView: petView)
        petWindowController.onDragBegan = { [weak self] in self?.statusPanelController.hideForDrag() }
        petWindowController.onDragEnded = { [weak self] in
            guard let self else { return }
            self.statusPanelController.dragEnded(relativeTo: self.petWindowController.frame)
        }
        petWindowController.onShowControlPanel = { [weak self] in self?.showControlPanel() }
        petWindowController.onHide = { [weak self] in self?.hidePet() }
        controlPanelWindowController = ControlPanelWindowController(model: model) { [weak self] in
            self?.controlPanelWindowController.hide()
        }
        model.onHideWindow = { [weak self] in self?.hidePet() }
        model.onShowSettings = { [weak self] in self?.showControlPanel() }
        model.onPetConfigurationChange = { [weak self] scale, style in
            guard let self else { return }
            self.petWindowController.updateConfiguration(scale: scale, style: style)
            self.statusPanelController.dragEnded(relativeTo: self.petWindowController.frame)
        }
        model.onPersistenceError = { [weak self] _ in
            // The banner is persistent and non-modal; repeatedly failing actions
            // bring the same control panel forward instead of stacking alerts.
            self?.showControlPanel()
        }
        model.onFirstRunComplete = { [weak self] in
            self?.controlPanelWindowController.hide()
            self?.petWindowController.show()
        }
        model.onStateChange = { [weak self] in self?.refreshMenu() }

        configureStatusItem()
        if model.persistenceErrorMessage != nil {
            petWindowController.show()
            controlPanelWindowController.show()
        } else if model.isOnboardingPresented {
            controlPanelWindowController.show()
        } else {
            petWindowController.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        petWindowController.show()
        showControlPanel()
        return true
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Flicky Ashtray")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        countMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        countMenuItem.isEnabled = false
        menu.addItem(countMenuItem)
        menu.addItem(.separator())
        menu.addItem(item("显示桌宠", #selector(showPet), ""))
        menu.addItem(item("查看记录与设置…", #selector(showControlPanelAction), ","))
        menu.addItem(item("记一根", #selector(addRecord), ""))
        undoMenuItem = item("撤销今日上一根", #selector(undoRecord), "")
        menu.addItem(undoMenuItem)
        menu.addItem(.separator())
        menu.addItem(item("退出 Flicky Ashtray", #selector(quit), "q"))
        statusItem.menu = menu
        refreshMenu()
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let value = NSMenuItem(title: title, action: action, keyEquivalent: key)
        value.target = self
        return value
    }

    private func refreshMenu() {
        guard countMenuItem != nil else { return }
        countMenuItem.title = "今天 \(model.snapshot.count) / \(model.snapshot.limit) 根"
        undoMenuItem?.isEnabled = model.canUndoToday
    }

    private func hidePet() {
        statusPanelController.hideImmediately()
        petWindowController.hide()
    }

    private func showControlPanel() {
        statusPanelController.hideImmediately()
        controlPanelWindowController.show()
    }

    @objc private func showPet() { petWindowController.show() }
    @objc private func showControlPanelAction() { showControlPanel() }
    @objc private func addRecord() { model.addRecord() }
    @objc private func undoRecord() { model.undoToday() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func configureMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(title: "Flicky Ashtray", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Flicky Ashtray")
        appMenu.addItem(
            withTitle: "关于 Flicky Ashtray",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(item("设置…", #selector(showControlPanelAction), ","))
        appMenu.addItem(.separator())

        let servicesMenu = NSMenu(title: "服务")
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "隐藏 Flicky Ashtray",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = appMenu.addItem(
            withTitle: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: "全部显示",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Flicky Ashtray", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(
            withTitle: "关闭窗口",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "全部移到前面",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}
