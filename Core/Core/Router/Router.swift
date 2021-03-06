//
// This file is part of Canvas.
// Copyright (C) 2018-present  Instructure, Inc.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import UIKit

public enum RouteOptions: Equatable {
    case push
    case detail
    case modal(
        _ style: UIModalPresentationStyle? = nil,
        isDismissable: Bool = true,
        embedInNav: Bool = false,
        addDoneButton: Bool = false
    )

    public var isModal: Bool {
        if case .modal = self {
            return true
        }
        return false
    }

    public var isDetail: Bool {
        if case .detail = self {
            return true
        }
        return false
    }

    public var embedInNav: Bool {
        switch self {
        case .detail, .modal(_, _, embedInNav: true, _):
            return true
        default:
            return false
        }
    }

    public static let noOptions = RouteOptions.push
}

public protocol RouterProtocol {
    func match(_ url: URLComponents) -> UIViewController?
    func route(to: Route, from: UIViewController, options: RouteOptions)
    func route(to url: URL, from: UIViewController, options: RouteOptions)
    func route(to url: String, from: UIViewController, options: RouteOptions)
    func route(to url: URLComponents, from: UIViewController, options: RouteOptions)
    func show(_ view: UIViewController, from: UIViewController, options: RouteOptions, completion: (() -> Void)?)
    func pop(from: UIViewController)
    func dismiss(_ view: UIViewController, completion: (() -> Void)?)
}

public extension RouterProtocol {
    func route(to: Route, from: UIViewController, options: RouteOptions = .noOptions) {
        return route(to: to.url, from: from, options: options)
    }

    func route(to url: URL, from: UIViewController, options: RouteOptions = .noOptions) {
        return route(to: .parse(url), from: from, options: options)
    }

    func route(to url: String, from: UIViewController, options: RouteOptions = .noOptions) {
        return route(to: .parse(url), from: from, options: options)
    }

    func show(_ view: UIViewController, from: UIViewController, options: RouteOptions = .noOptions) {
        show(view, from: from, options: options, completion: nil)
    }

    func show(_ view: UIViewController, from: UIViewController, options: RouteOptions = .noOptions, completion: (() -> Void)?) {
        if view is UIAlertController { return from.present(view, animated: true, completion: completion) }

        if let displayModeButton = from.displayModeButtonItem,
            from.splitViewController?.isCollapsed == false,
            options.isDetail || from.isInSplitViewDetail,
            !options.isModal {
            view.addNavigationButton(displayModeButton, side: .left)
            view.navigationItem.leftItemsSupplementBackButton = true
        }

        var nav: UINavigationController?
        if options.embedInNav {
            nav = view as? UINavigationController ?? UINavigationController(rootViewController: view)
        }

        switch options {
        case let .modal(style, isDismissable, _, addDoneButton):
            if addDoneButton {
                view.addDoneButton(side: .left)
            }
            nav?.navigationBar.useModalStyle()
            if let presentationStyle = style {
                (nav ?? view).modalPresentationStyle = presentationStyle
            }
            if #available(iOS 13, *), !isDismissable {
                (nav ?? view).isModalInPresentation = true
            }
            from.present(nav ?? view, animated: true, completion: completion)
        case .detail:
            if from.splitViewController == nil || from.isInSplitViewDetail || from.splitViewController?.isCollapsed == true {
                from.show(view, sender: nil)
            } else {
                from.showDetailViewController(nav ?? view, sender: from)
            }
        case .push:
            from.show(nav ?? view, sender: nil)
        }
    }

    func pop(from: UIViewController) {
        guard let navController = from.navigationController else {
            return
        }
        if navController.viewControllers.count == 1 {
            navController.viewControllers = [EmptyViewController(nibName: nil, bundle: nil)]
        } else {
            navController.popViewController(animated: true)
        }
    }

    func dismiss(_ view: UIViewController) {
        dismiss(view, completion: nil)
    }

    func dismiss(_ view: UIViewController, completion: (() -> Void)?) {
        view.dismiss(animated: true, completion: completion)
    }
}

// The Router stores all routes that can be routed to in the app
public class Router: RouterProtocol {
    public typealias FallbackHandler = (URLComponents, UIViewController, RouteOptions) -> Void

    private let handlers: [RouteHandler]
    private let fallback: FallbackHandler

    public init(routes: [RouteHandler], fallback: @escaping FallbackHandler) {
        self.handlers = routes
        self.fallback = fallback
    }

    public var count: Int {
        return handlers.count
    }

    private func cleanURL(_ url: URLComponents) -> URLComponents {
        // URLComponents does all the encoding we care about except we often have + meaning space in query
        var url = url
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        return url
    }

    public func match(_ url: URLComponents) -> UIViewController? {
        let url = cleanURL(url)
        for route in handlers {
            if let params = route.match(url) {
                return route.factory(url, params)
            }
        }
        return nil
    }

    public func route(to url: URLComponents, from: UIViewController, options: RouteOptions = .noOptions) {
        let url = cleanURL(url)
        #if DEBUG
        DeveloperMenuViewController.recordRouteInHistory(url.url?.absoluteString)
        #endif
        Analytics.shared.logEvent("route", parameters: ["url": String(describing: url)])
        for route in handlers {
            if let params = route.match(url) {
                if let view = route.factory(url, params) {
                    show(view, from: from, options: options)
                }
                return // don't fall back if a matched route returns no view
            }
        }
        fallback(url, from, options)
    }
}
