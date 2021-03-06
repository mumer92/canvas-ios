//
// This file is part of Canvas.
// Copyright (C) 2020-present  Instructure, Inc.
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

import Foundation
import UIKit
import WebKit

public class DiscussionDetailsViewController: UIViewController, ColoredNavViewProtocol, CoreWebViewLinkDelegate, ErrorViewController {
    @IBOutlet weak var pointsLabel: UILabel!
    @IBOutlet weak var pointsView: UIView!
    @IBOutlet weak var publishedIcon: UIImageView!
    @IBOutlet weak var publishedLabel: UILabel!
    @IBOutlet weak var publishedView: UIView!
    let refreshControl = CircleRefreshControl()
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var spinnerView: CircleProgressView!
    public var titleSubtitleView = TitleSubtitleView.create()
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var webViewPlaceholder: UIView!
    var webView = CoreWebView()

    public var color: UIColor?
    var context: Context = ContextModel.currentUser
    let env = AppEnvironment.shared
    var keyboard: KeyboardTransitioning?
    var maxDepth = 3
    var search: String?
    var topicID = ""

    var assignment: Store<GetAssignment>?
    lazy var colors = env.subscribe(GetCustomColors()) { [weak self] in
        self?.updateNavBar()
    }
    lazy var course = env.subscribe(GetCourse(courseID: context.id)) { [weak self] in
        self?.updateNavBar()
    }
    lazy var entries = env.subscribe(GetDiscussionView(context: context, topicID: topicID)) { [weak self] in
        self?.update()
    }
    lazy var group = env.subscribe(GetGroup(groupID: context.id)) { [weak self] in
        self?.updateNavBar()
    }
    lazy var permissions = env.subscribe(GetContextPermissions(context: context, permissions: [ .postToForum ])) { [weak self] in
        self?.update()
    }
    lazy var topic = env.subscribe(GetDiscussionTopic(context: context, topicID: topicID)) { [weak self] in
        self?.update()
    }

    public static func create(context: Context, topicID: String) -> DiscussionDetailsViewController {
        let controller = loadFromStoryboard()
        controller.context = context
        controller.topicID = topicID
        return controller
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupTitleViewInNavbar(title: NSLocalizedString("Discussion Details", bundle: .core, comment: ""))

        pointsView.isHidden = true
        publishedView.isHidden = true

        refreshControl.addTarget(self, action: #selector(refresh), for: .primaryActionTriggered)
        scrollView.refreshControl = refreshControl

        titleLabel.text = nil

        // Can't put in storyboard because that breaks cookie sharing
        // & discussion view is cached without verifiers on images
        webViewPlaceholder.addSubview(webView)
        webView.pin(inside: webViewPlaceholder)
        webView.heightAnchor.constraint(equalToConstant: 100).isActive = true

        webView.autoresizesHeight = true // will update the height constraint
        webView.backgroundColor = .named(.backgroundLightest)
        webView.linkDelegate = self
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.alwaysBounceVertical = false

        colors.refresh()
        if context.contextType == .course {
            course.refresh()
        } else {
            group.refresh()
        }
        topic.refresh()
        entries.refresh()
        permissions.refresh()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let color = color {
            navigationController?.navigationBar.useContextColor(color)
        }
        env.pageViewLogger.startTrackingTimeOnViewController()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        env.pageViewLogger.stopTrackingTimeOnViewController(eventName: "\(context.pathComponent)/discussion_topics/\(topicID)", attributes: [:])
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let depth = view.traitCollection.horizontalSizeClass == .compact ? 2 : 4
        if maxDepth != depth {
            maxDepth = depth
            loadHTML()
        }
    }

    func updateNavBar() {
        guard
            let name = context.contextType == .course ? course.first?.name : group.first?.name,
            let color = context.contextType == .course ? course.first?.color : group.first?.color
        else {
            return
        }
        spinnerView.color = color
        refreshControl.color = color
        updateNavBar(subtitle: name, color: color)
    }

    func update() {
        if assignment?.useCase.assignmentID != topic.first?.assignmentID {
            assignment = topic.first?.assignmentID.map {
                env.subscribe(GetAssignment(courseID: context.id, assignmentID: $0)) { [weak self] in
                    self?.update()
                }
            }
            assignment?.refresh()
        }

        let pending = topic.pending || entries.pending
        let error = topic.error ?? entries.error
        spinnerView.isHidden = !pending || (!topic.isEmpty && !entries.isEmpty) || error != nil || refreshControl.isRefreshing

        titleLabel.text = topic.first?.title
        pointsLabel.text = assignment?.first?.pointsPossibleText
        pointsView.isHidden = assignment?.first?.pointsPossible == nil

        if topic.first?.published == true {
            publishedIcon.image = .icon(.publish, .solid)
            publishedIcon.tintColor = .named(.textSuccess)
            publishedLabel.text = NSLocalizedString("Published", bundle: .core, comment: "")
            publishedLabel.textColor = .named(.textSuccess)
        } else {
            publishedIcon.image = .icon(.no, .solid)
            publishedIcon.tintColor = .named(.textDark)
            publishedLabel.text = NSLocalizedString("Unpublished", bundle: .core, comment: "")
            publishedLabel.textColor = .named(.textDark)
        }
        publishedView.isHidden = env.app != .teacher

        loadHTML()
    }

    @objc func refresh() {
        topic.refresh(force: true)
        entries.refresh(force: true) { [weak self] _ in
            self?.refreshControl.endRefreshing()
        }
        assignment?.refresh(force: true)
        permissions.refresh(force: true)
    }

    public func handleLink(_ url: URL) -> Bool {
        guard
            url.host == env.currentSession?.baseURL.host,
            url.path.hasPrefix("/\(context.pathComponent)/discussion_topics/\(topicID)/")
        else {
            env.router.route(to: url, from: self)
            return true
        }
        let path = Array(url.pathComponents.dropFirst(5))
        if path.count == 1, path[0] == "reply" {
            env.router.route(to: url, from: self, options: .modal(.formSheet, isDismissable: false, embedInNav: true))
            return true
        }
        if path.count == 3, path[0] == "entries", !path[1].isEmpty, path[2] == "replies" {
            env.router.route(to: url, from: self, options: .modal(.formSheet, isDismissable: false, embedInNav: true))
            return true
        }
        if path.count == 2, path[0] == "replies" {
            guard let entry: DiscussionEntry = env.database.viewContext.first(where: #keyPath(DiscussionEntry.id), equals: path[1]) else { return true }
            let controller = CoreWebViewController()
            let titleView = TitleSubtitleView.create()
            titleView.title = NSLocalizedString("Discussion Replies", bundle: .core, comment: "")
            titleView.subtitle = titleSubtitleView.subtitle
            controller.navigationItem.titleView = titleView
            controller.webView.linkDelegate = self
            let html = controller.webView.html(for: entryHTML(entry, depth: 0))
            controller.webView.loadHTMLString(html, baseURL: topic.first?.htmlUrl)
            env.router.show(controller, from: self)
            return true
        }
        env.router.route(to: url, from: self)
        return true
    }

    var canRate: Bool {
        topic.first?.allowRating == true && (
            topic.first?.onlyGradersCanRate != true ||
            course.first?.enrollments?.contains { $0.isTeacher || $0.isTA } == true
        )
    }
}

extension DiscussionDetailsViewController {
    // shortcuts to encode text for html
    static func t(_ text: String?) -> String { CoreWebView.htmlString(text) }
    func t(_ text: String?) -> String { CoreWebView.htmlString(text) }

    func loadHTML() {
        guard let topic = topic.first, !entries.pending || !entries.isEmpty else { return }
        var entries = self.entries.all
        if topic.sortByRating {
            entries = entries.sorted { $0.likeCount > $1.likeCount }
        }
        webView.loadHTMLString(webView.html(for: """
            \(Self.topicHTML(topic))
            \(topicReplyButton)
            <div style="border-top:0.3px solid var(--color-borderMedium); margin:16px 0;"></div>
            <h2 style="font-size:20px; font-weight:600; margin:0; padding:0;">
                \(t(NSLocalizedString("Replies", bundle: .core, comment: "")))
            </h2>
            \(entries.map { entryHTML($0, depth: 0) } .joined(separator: "\n"))
            """
        ), baseURL: topic.htmlUrl)
    }

    public static func topicHTML(_ topic: DiscussionTopic) -> String {
        return """
        \(entryHeader(author: topic.author, date: topic.postedAt, isTopic: true))
        \(topic.message ?? "")
        \(attachmentLink(topic.attachments?.first))
        """
    }

    static func entryHeader(author: DiscussionParticipant?, date: Date?, isTopic: Bool) -> String {
        guard author != nil || date != nil else { return "" }
        let dateString = date.flatMap {
            DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short)
        }
        guard let author = author else {
            return """
            <div style="color:var(--color-textDark); display:flex; font-size:12px; margin:16px 0;">
                \(t(dateString))
            </div>
            """
        }
        return """
        <div style="align-items:center; display:flex; margin:16px 0;">
            <a style="display:block; text-decoration:none;" href="../users/\(author.id)" aria-label="\(t(author.displayName))">
                \(AvatarView.html(for: author.avatarURL, name: author.name, size: isTopic ? 32 : 24))
            </a>
            <div style="flex:1; -webkit-margin-start:\(isTopic ? 16 : 8)px;">
                <div style="font-size:14px; font-weight:600;" aria-hidden="true">
                    \(t(author.displayName))
                </div>
                <div style="font-size:12px; margin-top:-2px; color:var(--color-textDark);">
                    \(t(dateString))
                </div>
            </div>
        </div>
        """
    }

    static func attachmentLink(_ attachment: File?) -> String {
        guard let attachment = attachment else { return "" }
        return """
        <a style="display:flex; align-items:center; font-size:14px; font-weight:600; text-decoration:none; margin:16px 0;" href="\(
            t(attachment.url?.absoluteString)
        )">\(
            paperclipIcon
        )<span style="-webkit-margin-start:4px; flex:1;">\(
            t(attachment.displayName)
        )</span></a>
        """
    }

    var topicReplyButton: String {
        guard topic.first?.lockedForUser == false, permissions.first?.postToForum == true else { return "" }
        return """
        <div style="display:flex; margin:16px 0;">
            <a href="\(t(topicID))/reply" style="
                align-items: center;
                background: var(--brand-buttonPrimaryBackground);
                border: 0 none;
                border-radius: 4px;
                color: var(--brand-buttonPrimaryText);
                display: flex;
                padding: 10px 16px;
                text-decoration: none;
            ">
                \(Self.replyIcon)
                <span style="font-size:14px; font-weight:500; -webkit-margin-start:10px;">
                    \(t(NSLocalizedString("Reply", bundle: .core, comment: "")))
                </span>
            </a>
        </div>
        """
    }

    func entryHTML(_ entry: DiscussionEntry, depth: UInt) -> String {
        return """
        <div id="entry-\(t(entry.id))" style="position:relative; -webkit-margin-start:\(depth * 32)px;">
            \(threadLines(depth: depth))
            \(unreadDiv(entry.isRead))
            \(Self.entryHeader(author: entry.author, date: entry.updatedAt, isTopic: false))
            <div style="-webkit-margin-start:32px;">
                \(messageHTML(entry))
                \(Self.attachmentLink(entry.isRemoved ? nil : entry.attachment))
                \(entryButtonsHTML(entry))
                \(viewMoreRepliesLink(entry, depth: depth))
            </div>
        </div>
        \(repliesHTML(entry, depth: depth))
        """
    }

    func threadLines(depth: UInt) -> String {
        (0...Int(depth)).map { i in
            """
            <div style="
                position: absolute;
                -webkit-margin-start: \(i * -32 + 12)px;
                top: \(i == 0 ? 24 : -16)px;
                bottom: 0;
                border-left: 0.3px solid var(--color-borderMedium);"></div>
            """
        } .joined(separator: "\n")
    }

    func unreadDiv(_ isRead: Bool) -> String {
        return isRead ? "" : """
        <div style="
            position: absolute;
            background: var(--color-backgroundInfo);
            color: var(--color-backgroundInfo);
            border-radius: 3px;
            width: 6px;
            height: 6px;
            -webkit-margin-start: -6px;
            overflow: hidden;
        ">
            \(t(NSLocalizedString("Unread", bundle: .core, comment: "")))
        </div>
        """
    }

    func messageHTML(_ entry: DiscussionEntry) -> String {
        if !entry.isRemoved { return entry.message ?? "" }
        return """
        <p style="font-style:italic; color:var(--color-textDark);">
            \(t(NSLocalizedString("Deleted this reply.", bundle: .core, comment: "")))
        </p>
        """
    }

    func entryButtonsHTML(_ entry: DiscussionEntry) -> String {
        guard !entry.isRemoved else { return "" }
        var actions = ""
        if topic.first?.lockedForUser == false, permissions.first?.postToForum == true {
            actions = """
            <a href="\(t(topicID))/entries/\(t(entry.id))/replies" style="
                color: var(--color-textDark);
                font-weight: 600;
                text-decoration: none;
            ">
                \(t(NSLocalizedString("Reply", bundle: .core, comment: "")))
            </a>
            <div style="border-left:1px solid var(--color-borderMedium); height:16px; margin:0 16px; width:0;"></div>
            """
        }
        actions += """
        <button
            aria-label="\(t(NSLocalizedString("Show more options", bundle: .core, comment: "")))"
            style="
                background: none;
                border: 0 none;
                color: var(--color-textDark);
                display: flex;
                margin: 0;
                padding: 0;
            "
        >
            <svg xmlns="http://www.w3.org/2000/svg" height="20" width="24" aria-hidden="true">
                <circle fill="currentColor" r="2" cx="4" cy="10" />
                <circle fill="currentColor" r="2" cx="12" cy="10" />
                <circle fill="currentColor" r="2" cx="20" cy="10" />
            </svg>
        </button>
        """

        let rating: String
        if topic.first?.allowRating != true {
            rating = ""
        } else if canRate {
            let count = entry.likeCount <= 0 ? "" : String.localizedStringWithFormat(
                NSLocalizedString("(%d)", bundle: .core, comment: "number of likes next to the like button"),
                entry.likeCount
            )
            rating = """
            <div style="
                align-items: center;
                color: var(\(entry.isLikedByMe ? "--brand-linkColor" : "--color-textDark"));
                display: flex;
                margin: -2px 0;
            ">
                <span style="
                    clip-path: inset(50%);
                    height: 1px;
                    overflow: hidden;
                    width: 1px;
                ">
                    \(t(entry.likeCount > 0 ? entry.likeCountText : ""))
                </span>
                <span style="-webkit-margin-end:6px;" aria-hidden="true">
                    \(t(count))
                </span>
                <label style="display:flex; position:relative;">
                    <input
                        type="checkbox"
                        style="
                            position: absolute;
                            top: 0; left: 0;
                            width: 100%; height: 100%;
                            margin: 0;
                            opacity: 0.001;
                        "
                        aria-label="\(t(NSLocalizedString("Like", bundle: .core, comment: "like action")))"
                        \(entry.isLikedByMe ? "checked" : "")
                    />
                    \(entry.isLikedByMe ? Self.likeSolidIcon : Self.likeLineIcon)
                </label>
            </div>
            """
        } else {
            rating = """
            <div style="color:var(--color-textDark);">
                \(t(entry.likeCount > 0 ? entry.likeCountText : ""))
            </div>
            """
        }

        return """
        <div style="align-items:center; display:flex; margin:16px 0;">
            \(actions)
            <span style="flex:1;"></span>
            \(rating)
        </div>
        """
    }

    func viewMoreRepliesLink(_ entry: DiscussionEntry, depth: UInt) -> String {
        guard depth >= maxDepth, !entry.replies.isEmpty else { return "" }
        return """
        <a href="\(t(topicID))/replies/\(t(entry.id))" style="
            color: var(--color-textDark);
            background: var(--color-backgroundLight);
            border: 1px solid var(--color-borderMedium);
            border-radius: 4px;
            display: block;
            font-size: 12px;
            padding: 5px;
            margin: 16px 0;
            text-align: center;
            text-decoration: none;
        ">
            \(t(NSLocalizedString("View more replies", bundle: .core, comment: "")))
        </a>
        """
    }

    func repliesHTML(_ entry: DiscussionEntry, depth: UInt) -> String {
        guard !entry.replies.isEmpty, depth < maxDepth else { return "" }
        return entry.replies.map { entryHTML($0, depth: depth + 1) } .joined(separator: "\n")
    }

    static let paperclipIcon = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 1920" width="14" aria-hidden="true">
    <path fill-rule="evenodd" fill="currentColor" d="
        M1752.77 221.1C1532.65 1 1174.28 1 954.17 221.1l-838.6 838.6c-154.05 154.16-154.05 404.9 0 558.94
        149.54 149.42 409.98 149.31 559.06 0l758.74-758.62c87.98-88.1 87.98-231.42 0-319.51-88.32-88.21
        -231.64-87.98-319.51 0l-638.8 638.9 79.85 79.85 638.8-638.9c43.93-43.83 115.54-43.94 159.81 0
        43.93 44.04 43.93 115.87 0 159.8L594.78 1538.8c-110.23 110.12-289.35 110-399.36 0-110.12-110.11-110
        -289.24 0-399.24l838.59-838.6c175.96-175.95 462.38-176.18 638.9 0 176.08 176.2 176.08 462.84 0
        638.92l-798.6 798.72 79.85 79.85 798.6-798.72c220.02-220.13 220.02-578.49 0-798.61"/>
    </svg>
    """

    static let replyIcon = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 1920" width="18" aria-hidden="true" class="rtl-mirror-x">
    <path fill-rule="evenodd" fill="currentColor" d="
        M835.942 632.563H244.966l478.08-478.08-90.496-90.496L-.026 696.563 632.55
        1329.14l90.496-90.496-478.08-478.08h590.976c504.448 0 914.816 410.368 914.816
        914.816v109.184h128V1675.38c0-574.976-467.84-1042.816-1042.816-1042.816"/>
    </svg>
    """

    static let likeLineIcon = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 1920" width="24" height="24" aria-hidden="true">
    <path fill-rule="evenodd" fill="currentColor" d="
        M1637.176 1129.412h-112.94v112.94c62.23 0 112.94 50.599 112.94 112.942 0 62.344-50.71
        112.941-112.94 112.941h-112.942v112.941c62.23 0 112.941 50.598 112.941 112.942 0
        62.343-50.71 112.94-112.94 112.94h-960c-155.634 0-282.354-126.606-282.354-282.352
        V903.529h106.617c140.16 0 274.334-57.6 368.3-157.778C778.486 602.089 937.28 379.256
        957.385 112.94h36.367c50.484 0 98.033 22.363 130.334 61.44 32.64 39.53 45.854 91.144
        36.14 141.515-22.7 118.589-60.197 236.048-111.246 349.102-23.83 52.517-19.313 112.602
        11.746 160.94 31.397 48.566 84.706 77.591 142.644 77.591h433.807c62.231 0 112.942 50.598
        112.942 112.942 0 62.343-50.71 112.94-112.942 112.94m225.883-112.94c0-124.575-101.308
        -225.883-225.883-225.883H1203.37c-19.651 0-37.044-9.374-47.66-25.863-10.391-16.15-11.86
        -35.577-3.84-53.196 54.663-121.073 94.87-247.115 119.378-374.513 15.925-83.576-5.873
        -169.072-60.085-234.578C1157.29 37.384 1078.005 0 993.751 0H846.588v56.47c0 254.457
        -155.068 473.224-285.063 612.029-72.734 77.477-176.98 122.09-285.967 122.09H56v734.117
        C56 1742.682 233.318 1920 451.294 1920h960c124.574 0 225.882-101.308 225.882-225.882
        0-46.42-14.117-89.676-38.174-125.59 87.869-30.947 151.116-114.862 151.116-213.234 0-46.419
        -14.118-89.675-38.174-125.59 87.868-30.946 151.115-114.862 151.115-213.233"/>
    </svg>
    """

    static let likeSolidIcon = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 1920" width="24" height="24" aria-hidden="true">
    <path fill-rule="evenodd" fill="currentColor" d="
        M1863.059 1016.47c0-124.574-101.308-225.882-225.883-225.882H1203.37c-19.651 0-37.044-9.374
        -47.66-25.863-10.391-16.15-11.86-35.577-3.84-53.196 54.776-121.073 94.87-247.115 119.378
        -374.513 15.925-83.576-5.873-169.072-60.085-234.578C1157.29 37.384 1078.005 0 993.751 0
        H846.588v56.47c0 254.457-155.068 473.224-285.063 612.029-72.734 77.477-176.98 122.09
        -285.967 122.09H56v734.117C56 1742.682 233.318 1920 451.294 1920h960c124.574 0 225.882
        -101.308 225.882-225.882 0-46.42-14.117-89.676-38.174-125.59 87.869-30.947 151.116-114.862
        151.116-213.234 0-46.419-14.118-89.675-38.174-125.59 87.868-30.946 151.115-114.862 151.115
        -213.233"/>
    </svg>
    """
}
