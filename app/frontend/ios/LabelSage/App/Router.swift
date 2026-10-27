import Foundation
import Observation

/// Navigation and modal presentation (flows board `design/screens/70-flows-ai-first.png`).
///
/// Shape: chat home owns `path`. The camera opens as a full-screen cover; a product found there opens
/// as `cameraSheet`, attached inside the cover, so the sheet sits over the camera. Every sheet is a
/// `ModalLayer` with its own `NavigationStack` path and an optional `child` sheet, so a product sheet
/// can push a page or present another sheet. `push` and `present` act on the top-most layer.
/// Screen tasks add the route and sheet cases they need.
@Observable
final class Router {
    /// Pages pushed on a `NavigationStack`.
    enum Route: Hashable {
        /// Product page as a page (spec 04, `as: .page`). Resolve with `AppModel.product(id:)`.
        case product(id: String)
        /// Family (spec 06), pushed so the system back returns to the chat.
        case family
    }

    /// Content of a sheet with detents.
    enum Sheet: Hashable {
        /// Product page as a sheet (spec 04, `as: .sheet`). Resolve with `AppModel.product(id:)`.
        case product(id: String)
        /// Compare with (spec 05): picks the second product for `baseId`.
        case compareWith(baseId: String)
        /// Compare (spec 05) as a large sheet.
        case compare(leftId: String, rightId: String)
    }

    /// Full-screen covers.
    enum Cover: Hashable, Identifiable {
        /// Check a product (spec 03).
        case camera
        var id: Self { self }
    }

    /// One presented sheet: its content, its own navigation path, and a sheet it presents.
    @Observable
    final class ModalLayer: Identifiable {
        let id = UUID()
        /// Its content; `replaceTop` swaps it in place (Compare with becomes Compare in the same sheet).
        var sheet: Sheet
        var path: [Route] = []
        var child: ModalLayer?
        init(_ sheet: Sheet) { self.sheet = sheet }

        /// This layer or the deepest sheet presented from it.
        var top: ModalLayer { child?.top ?? self }
    }

    /// Chat home's navigation path.
    var path: [Route] = []
    /// A sheet over chat home.
    var sheet: ModalLayer?
    var cover: Cover?
    /// A sheet over the camera; attach with `.sheet(item:)` inside the cover's content.
    var cameraSheet: ModalLayer?

    /// The sheet the person sees now, if any (inside the cover when the camera is open).
    var topLayer: ModalLayer? { cover == nil ? sheet?.top : cameraSheet?.top }

    /// Pushes onto the visible stack: the top sheet's path, or chat home's.
    func push(_ route: Route) {
        // Ends when the page appears (RootView).
        Perf.beginPending("sheet.open")
        if let layer = topLayer {
            layer.path.append(route)
        } else if cover == nil {
            path.append(route)
        }
        else { assertionFailure("push with the camera open and no sheet over it") }
    }

    /// Presents `sheet` over whatever is visible: chat home, the camera, or another sheet.
    func present(_ sheet: Sheet) {
        // Ends when the sheet's content appears (RootView).
        Perf.beginPending("sheet.open")
        let layer = ModalLayer(sheet)
        if let top = topLayer {
            top.child = layer
        } else if cover != nil {
            cameraSheet = layer
        } else {
            self.sheet = layer
        }
    }

    /// Swaps the top sheet's content without a dismiss and present (one sheet at a time, HIG).
    func replaceTop(with sheet: Sheet) {
        guard let top = topLayer else { return present(sheet) }
        top.sheet = sheet
        top.path = []
    }

    /// The camera covers everything: a home sheet closes first, because SwiftUI can't show a
    /// full-screen cover over a sheet presented from the same root.
    func openCamera() {
        sheet = nil
        cameraSheet = nil
        cover = .camera
    }

    /// Closes the camera and anything over it.
    func closeCamera() {
        cameraSheet = nil
        cover = nil
    }

    /// Dismisses the top-most sheet.
    func dismissTop() {
        let root = cover == nil ? sheet : cameraSheet
        guard let root else { return }
        if root.child == nil {
            if cover == nil { sheet = nil } else { cameraSheet = nil }
            return
        }
        var parent = root
        while let child = parent.child, child.child != nil { parent = child }
        parent.child = nil
    }

    /// Back to chat home with nothing on top.
    func popToRoot() {
        path.removeAll()
        sheet = nil
        closeCamera()
    }
}
