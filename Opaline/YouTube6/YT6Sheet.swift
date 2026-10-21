// The iPodOS sheet is called through its Objective-C methods' IMPs, whose
// C signatures take NSString.
// swiftlint:disable legacy_objc_type
import UIKit

/// Every Opaline menu (the ⋮ menus, the player's settings and quality, save
/// and download choices — all `PlayerMenuOverlay`) as the iOS 6 action
/// sheet 2.0.0 used: its «Add to…» and «Share» sheets on iPhone are system
/// `UIActionSheet`s, no title, default style (REQUEST710, ipodos27
/// research/YOUTUBE6-ACTIONSHEET-2026-10-21.md). iPodOS draws that sheet
/// from 6.1.3's code in `IP6UActionSheet` (`/usr/lib/libip6ui.dylib`: 46 pt
/// buttons on a 53 pt pitch, cancel 21 pt apart); it is loaded on first use.
/// Without it the menu stays upstream's.
enum YT6Sheet {
    private typealias Handler = @convention(block) () -> Void
    private typealias Make = @convention(c) (
        AnyObject, Selector, NSString?, ObjCBool
    ) -> Unmanaged<AnyObject>
    private typealias Add = @convention(c) (
        AnyObject, Selector, NSString, ObjCBool, Handler?
    ) -> Void
    private typealias AddCancel = @convention(c) (AnyObject, Selector, NSString, Handler?) -> Void
    private typealias Show = @convention(c) (AnyObject, Selector, UIView) -> Void

    private struct Button {
        let title: String
        let destructive: Bool
        let handler: (() -> Void)?
    }

    /// `kIP6USheetFirstY` + `CancelGap` + button + `Bottom` (IP6UActionSheet.m).
    private static let frame: CGFloat = 21 + 21 + 46 + 20
    private static let pitch: CGFloat = 53

    private static let sheetClass: AnyClass? = {
        _ = dlopen("/usr/lib/libip6ui.dylib", RTLD_NOW)
        return NSClassFromString("IP6UActionSheet")
    }()

    private static var cancelTitle: String {
        let uikit = Bundle(for: UIApplication.self)
        return uikit.localizedString(forKey: "Cancel", value: "Cancel", table: nil)
    }

    private static var moreTitle: String {
        YT6.isRussianInterface ? "Ещё…" : "More…"
    }

    /// False when the iOS 6 sheet is not available.
    static func show(title: String?, items: [PlayerMenuItem], in view: UIView) -> Bool {
        guard let sheetClass, !items.isEmpty else {
            return false
        }
        let host = view.window ?? view
        // What fits above the cancel button; the rest goes behind «More…».
        let room = host.bounds.height - frame - (title == nil ? 0 : 40) + 7
        let fit = max(Int(room / pitch), 2)
        let page = items.count > fit ? Array(items.prefix(fit - 1)) : items
        let rest = Array(items.dropFirst(page.count))
        var buttons = page.map {
            Button(title: $0.title, destructive: $0.isDestructive, handler: $0.handler)
        }
        if !rest.isEmpty {
            buttons.append(Button(title: moreTitle, destructive: false) {
                _ = show(title: nil, items: rest, in: view)
            })
        }
        return present(sheetClass, title: title, buttons: buttons, in: host)
    }

    private static func present(
        _ sheetClass: AnyClass,
        title: String?,
        buttons: [Button],
        in host: UIView
    ) -> Bool {
        let make = NSSelectorFromString("sheetWithTitle:black:")
        let add = NSSelectorFromString("addButtonWithTitle:destructive:handler:")
        let cancel = NSSelectorFromString("addCancelButtonWithTitle:handler:")
        let show = NSSelectorFromString("showInView:")
        guard let makeIMP = imp(sheetClass, make, ofClass: true),
              let addIMP = imp(sheetClass, add),
              let cancelIMP = imp(sheetClass, cancel),
              let showIMP = imp(sheetClass, show)
        else {
            return false
        }
        let makeSheet = unsafeBitCast(makeIMP, to: Make.self)
        let sheet = makeSheet(sheetClass, make, title as NSString?, false).takeUnretainedValue()
        let addButton = unsafeBitCast(addIMP, to: Add.self)
        for button in buttons {
            let title = button.title as NSString
            addButton(sheet, add, title, ObjCBool(button.destructive), block(button))
        }
        unsafeBitCast(cancelIMP, to: AddCancel.self)(sheet, cancel, cancelTitle as NSString, nil)
        unsafeBitCast(showIMP, to: Show.self)(sheet, show, host)
        return true
    }

    private static func block(_ button: Button) -> Handler? {
        guard let action = button.handler else {
            return nil
        }
        let handler: Handler = {
            action()
        }
        return handler
    }

    private static func imp(_ cls: AnyClass, _ sel: Selector, ofClass: Bool = false) -> IMP? {
        let method = ofClass ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel)
        return method.map(method_getImplementation)
    }
}
// swiftlint:enable legacy_objc_type
