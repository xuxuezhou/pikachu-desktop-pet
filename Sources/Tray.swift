import AppKit

// MARK: - System tray icon + menu

final class TrayController: NSObject, NSMenuDelegate {
    private weak var coordinator: AppCoordinator?
    private var statusItem: NSStatusItem?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⚡️"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    func updateTitle(_ title: String) {
        statusItem?.button?.title = title
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let coordinator else { return }
        let settings = SaveManager.shared.data.settings
        menu.removeAllItems()

        menu.addItem(item(coordinator.isPetVisible ? "隐藏皮卡丘" : "显示皮卡丘") {
            coordinator.togglePetVisibility()
        })
        menu.addItem(item("随机动作 ⌃⇧R") { coordinator.randomAction() })
        menu.addItem(item("今日状态") { coordinator.showStatusBubble() })
        menu.addItem(item("回到主屏幕 ⌃⇧H") { coordinator.recallToMainScreen() })
        menu.addItem(.separator())

        menu.addItem(item(coordinator.pomodoro.menuTitle) { coordinator.togglePomodoro() })
        menu.addItem(.separator())

        menu.addItem(toggle("安静模式", settings.quietMode) { coordinator.toggleQuietMode() })
        menu.addItem(toggle("锁定位置 ⌃⇧L", settings.positionLocked) { coordinator.toggleLockPosition() })
        menu.addItem(toggle("鼠标穿透 ⌃⇧G", settings.clickThrough) { coordinator.toggleClickThrough() })
        menu.addItem(toggle("气泡", settings.bubblesEnabled) { coordinator.toggleBubbles() })
        menu.addItem(toggle("重力", settings.gravityEnabled) { coordinator.toggleGravity() })
        menu.addItem(toggle("窗口置顶", settings.alwaysOnTop) { coordinator.toggleAlwaysOnTop() })
        menu.addItem(.separator())

        menu.addItem(item("退出") { NSApp.terminate(nil) })
    }

    private func item(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let result = ClosureMenuItem(title: title, closure: action)
        result.isEnabled = true
        return result
    }

    private func toggle(_ title: String, _ isOn: Bool, action: @escaping () -> Void) -> NSMenuItem {
        let result = item(title, action: action)
        result.state = isOn ? .on : .off
        return result
    }
}
