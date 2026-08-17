//
//  DownloadManagerView.swift
//  Feather
//
//  真·下载管理器：默认进入即浏览器（地址栏 + WKWebView），
//  网页里点击 .ipa/.tipa/.zip/.rar 链接自动交给 DownloadManager 下载；
//  可切到「下载列表」查看进行中 / 已下载（点按安装）。
//

import SwiftUI
import WebKit
import CoreData
import UniformTypeIdentifiers
import NimbleViews
import os

// MARK: - 视图模式
private enum _DownloadMode: String, CaseIterable {
	case browser
	case list
}

// MARK: - 浏览器视图模型
final class BrowserViewModel: ObservableObject {
	weak var webView: WKWebView?

	@Published var addressText: String = ""
	@Published var currentURL: URL?
	@Published var isLoading: Bool = false
	@Published var estimatedProgress: Double = 0
	@Published var canGoBack: Bool = false
	@Published var canGoForward: Bool = false

	func load(_ string: String) {
		var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !s.isEmpty else { return }
		if !s.contains("://") { s = "https://" + s }
		guard let url = URL(string: s) else { return }
		addressText = s
		webView?.load(URLRequest(url: url))
	}

	func goBack() { webView?.goBack() }
	func goForward() { webView?.goForward() }
	func reload() { webView?.reload() }
}

// MARK: - View
struct DownloadManagerView: View {
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject private var _browser = BrowserViewModel()

	@State private var _mode: _DownloadMode = .browser
	@State private var _selectedInfoAppPresenting: AnyApp?
	@State private var _selectedInstallAppPresenting: AnyApp?
	@State private var _isImportingPresenting = false
	@State private var _isDownloadingPresenting = false
	@State private var _alertDownloadString: String = ""
	@State private var _bannerDownloadURL: URL?

	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _importedApps: FetchedResults<Imported>

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("下载")) {
			VStack(spacing: 0) {
				Picker("视图", selection: $_mode) {
					Text("浏览器").tag(_DownloadMode.browser)
					Text("下载列表").tag(_DownloadMode.list)
				}
				.pickerStyle(.segmented)
				.padding(.horizontal, 12)
				.padding(.vertical, 8)

				Divider()

				ZStack {
					_listView
						.opacity(_mode == .list ? 1 : 0)
						.allowsHitTesting(_mode == .list)

					_browserView
						.opacity(_mode == .browser ? 1 : 0)
						.allowsHitTesting(_mode == .browser)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			.toolbar {
				NBToolbarMenu(
					systemImage: "plus",
					style: .icon,
					placement: .topBarTrailing
				) {
					_importActions()
				}
			}
			.sheet(item: $_selectedInfoAppPresenting) { app in
				LibraryInfoView(app: app.base)
			}
			.sheet(item: $_selectedInstallAppPresenting) { app in
				InstallPreviewView(app: app.base, isSharing: app.archive)
					.presentationDetents([.height(200)])
					.presentationDragIndicator(.visible)
			}
			.sheet(isPresented: $_isImportingPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes: [.ipa, .tipa],
					allowsMultipleSelection: true
				) { urls in
					guard !urls.isEmpty else { return }

					for url in urls {
						let id = "FeatherManualDownload_\(UUID().uuidString)"
						_ = downloadManager.importFile(from: url, id: id)
					}
				}
				.ignoresSafeArea()
			}
			.alert(Text("添加下载"), isPresented: $_isDownloadingPresenting) {
				TextField("IPA 链接", text: $_alertDownloadString)
					.textInputAutocapitalization(.never)
				Button("取消", role: .cancel) {
					_alertDownloadString = ""
				}
				Button("确定") {
					if let url = URL(string: _alertDownloadString) {
						_ = downloadManager.startDownload(
							from: url,
							id: "FeatherManualDownload_\(UUID().uuidString)"
						)
					}
				}
			}
			.onReceive(NotificationCenter.default.publisher(for: .zDownloadStarted)) { notification in
				if let url = notification.object as? URL {
					_bannerDownloadURL = url
				}
			}
		}
	}
}

// MARK: - 下载列表视图
private extension DownloadManagerView {
	@ViewBuilder
	var _listView: some View {
		NBListAdaptable {
			if !downloadManager.downloads.isEmpty {
				NBSection(
					"进行中",
					secondary: downloadManager.downloads.count.description
				) {
					ForEach(downloadManager.downloads) { dl in
						_DownloadRow(download: dl)
					}
				}
			}

			if !_importedApps.isEmpty {
				NBSection(
					"已下载",
					secondary: _importedApps.count.description
				) {
					ForEach(_importedApps, id: \.uuid) { app in
						LibraryCellView(
							app: app,
							selectedInfoAppPresenting: $_selectedInfoAppPresenting,
							selectedInstallAppPresenting: $_selectedInstallAppPresenting,
							selectedAppUUIDs: .constant([])
						)
					}
				}
			}
		}
		.overlay {
			if downloadManager.downloads.isEmpty && _importedApps.isEmpty {
				if #available(iOS 17, *) {
					ContentUnavailableView {
						Label("暂无下载", systemImage: "square.and.arrow.down")
					} description: {
						Text("在浏览器里打开网址，点击安装包链接即可下载。")
					} actions: {
						Menu {
							_importActions()
						} label: {
							NBButton("添加下载", style: .text)
						}
					}
				}
			}
		}
	}
}

// MARK: - 浏览器视图
private extension DownloadManagerView {
	@ViewBuilder
	var _browserView: some View {
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				Button { _browser.goBack() } label: {
					Image(systemName: "chevron.left")
				}
				.disabled(!_browser.canGoBack)

				Button { _browser.goForward() } label: {
					Image(systemName: "chevron.right")
				}
				.disabled(!_browser.canGoForward)

				TextField("输入网址，如 example.com", text: $_browser.addressText)
					.textFieldStyle(.roundedBorder)
					.textInputAutocapitalization(.never)
					.keyboardType(.URL)
					.onSubmit { _browser.load(_browser.addressText) }

				Button { _browser.reload() } label: {
					Image(systemName: "arrow.clockwise")
				}
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 8)

			Divider()

			ZStack {
				BrowserView(model: _browser)

				if _browser.currentURL == nil {
					VStack(spacing: 12) {
						Image(systemName: "globe")
							.font(.largeTitle)
							.foregroundStyle(.secondary)
						Text("在上方输入网址开始浏览，\n点击 .ipa / .tipa / .zip / .rar 链接即可下载")
							.multilineTextAlignment(.center)
							.foregroundStyle(.secondary)
							.font(.callout)
					}
				}

				if _browser.isLoading {
					VStack {
						ProgressView(value: _browser.estimatedProgress)
							.progressViewStyle(.linear)
							.padding(.horizontal, 12)
						Spacer()
					}
				}
			}
			.overlay(alignment: .bottom) {
				if let url = _bannerDownloadURL {
					HStack(spacing: 10) {
						Image(systemName: "arrow.down.circle.fill")
							.foregroundStyle(.tint)
						VStack(alignment: .leading, spacing: 2) {
							Text("已开始下载")
								.font(.subheadline.bold())
							Text(url.lastPathComponent)
								.font(.caption)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
						Spacer()
						Button("查看") {
							_mode = .list
							_bannerDownloadURL = nil
						}
						Button("继续") {
							_bannerDownloadURL = nil
						}
						.frame(minWidth: 44)
						.foregroundStyle(.secondary)
					}
					.padding(.horizontal, 14)
					.padding(.vertical, 10)
					.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
					.padding(.horizontal, 12)
					.padding(.bottom, 12)
				}
			}
		}
	}

}

// MARK: - Extension: Import Actions
extension DownloadManagerView {
	@ViewBuilder
	private func _importActions() -> some View {
		Button("从文件导入", systemImage: "folder") {
			_isImportingPresenting = true
		}
		Button("从链接下载", systemImage: "globe") {
			_isDownloadingPresenting = true
		}
	}
}

// MARK: - Download Row
// 复用已验证的 DownloadItemView（内部用 .onReceive 订阅 @Published）。
// 本行用 @ObservedObject 订阅 download.state，失败态下显示「继续」按钮以断点续传。
private struct _DownloadRow: View {
	@ObservedObject var download: Download

	var body: some View {
		HStack(spacing: 12) {
			DownloadItemView(download: download)

			if download.state == .failed {
				Button {
					DownloadManager.shared.resumeDownload(download)
				} label: {
					Image(systemName: "arrow.clockwise.circle.fill")
						.font(.title3)
						.foregroundStyle(.tint)
				}
				.buttonStyle(.borderless)
			}

			Button {
				DownloadManager.shared.cancelDownload(download)
			} label: {
				Image(systemName: "xmark.circle.fill")
					.font(.title3)
					.foregroundStyle(.secondary)
			}
			.buttonStyle(.borderless)
		}
	}
}

// MARK: - WKWebView 包装器
private struct BrowserView: UIViewRepresentable {
	@ObservedObject var model: BrowserViewModel

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeUIView(context: Context) -> WKWebView {
		let config = WKWebViewConfiguration()
		let webView = WKWebView(frame: .zero, configuration: config)
		webView.allowsBackForwardNavigationGestures = true
		webView.navigationDelegate = context.coordinator
		context.coordinator.model = model
		context.coordinator.observeProgress(webView)
		model.webView = webView
		return webView
	}

	func updateUIView(_ uiView: WKWebView, context: Context) {
		context.coordinator.model = model
		model.webView = uiView
	}

	// MARK: Coordinator
	final class Coordinator: NSObject, WKNavigationDelegate {
		var model: BrowserViewModel?
		var progressObservation: NSKeyValueObservation?

		static let downloadableExtensions: Set<String> = ["ipa", "tipa", "zip", "rar", "deb"]

		static func isDownloadable(_ url: URL) -> Bool {
			downloadableExtensions.contains(url.pathExtension.lowercased())
		}

		func observeProgress(_ webView: WKWebView) {
			progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
				self?.model?.estimatedProgress = change.newValue ?? 0
			}
		}

		func syncState(_ webView: WKWebView) {
			model?.canGoBack = webView.canGoBack
			model?.canGoForward = webView.canGoForward
			model?.currentURL = webView.url
			if let url = webView.url {
				model?.addressText = url.absoluteString
			}
		}

		func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
			model?.isLoading = true
		}

		func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
			syncState(webView)
		}

		func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
			model?.isLoading = false
			model?.estimatedProgress = 0
			syncState(webView)
		}

		func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
			model?.isLoading = false
			model?.estimatedProgress = 0
		}

		func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
			model?.isLoading = false
			model?.estimatedProgress = 0
		}

		func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
			webView.reload()
		}

		func webView(_ webView: WKWebView,
					 didReceive challenge: URLAuthenticationChallenge,
					 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
			guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
				  let trust = challenge.protectionSpace.serverTrust else {
				completionHandler(.performDefaultHandling, nil); return
			}
			completionHandler(.useCredential, URLCredential(trust: trust))
		}

		func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
					 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
			guard let url = navigationAction.request.url else { decisionHandler(.allow); return }

			// 新窗口（target="_blank"）：若是下载链接则转下载，否则在当前视图打开
			if navigationAction.targetFrame == nil {
				let isDl: Bool
				if #available(iOS 14.5, *) {
					isDl = Self.isDownloadable(url) || navigationAction.shouldPerformDownload
				} else {
					isDl = Self.isDownloadable(url)
				}
				if isDl {
					DownloadManager.shared.startDownload(from: navigationAction.request)
					NotificationCenter.default.post(name: .zDownloadStarted, object: url)
					decisionHandler(.cancel)
				} else {
					webView.load(navigationAction.request)
					decisionHandler(.cancel)
				}
				return
			}

			let shouldDownload: Bool
			if #available(iOS 14.5, *) {
				shouldDownload = Self.isDownloadable(url) || navigationAction.shouldPerformDownload
			} else {
				shouldDownload = Self.isDownloadable(url)
			}
		os_log(.info, log: .zBrowserDownload, "navAction url=%{public}@ ext=%{public}@ download=%d",
			   url.absoluteString, Self.isDownloadable(url) ? "yes" : "no", shouldDownload ? 1 : 0)

		if shouldDownload {
			DownloadManager.shared.startDownload(from: navigationAction.request)
			NotificationCenter.default.post(name: .zDownloadStarted, object: url)
			decisionHandler(.cancel)
		} else {
			decisionHandler(.allow)
		}
		}

		func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
					 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
			// 触发下载的判定（覆盖「带扩展名 / 服务器建议 / Content-Disposition / 二进制 Content-Type / 不可渲染且非 HTML」）：
			// 既让不带扩展名的脚本下载、JS 触发、302 重定向后无扩展名的下载也能触发，
			// 又避免把自签服务器返回的 HTML 错误页误当下载白屏。
			let response = navigationResponse.response
			let http = response as? HTTPURLResponse
			let responseURL = response.url
			let extDownloadable = responseURL.map(Self.isDownloadable) ?? false
			let mime = ((http?.mimeType) ?? response.mimeType)?.lowercased() ?? ""

			// 1) 明显是文件的 MIME 类型（无论 WebKit 能否渲染，一律当下载）
			let fileMimes: Set<String> = [
				"application/octet-stream", "binary/octet-stream",
				"application/zip", "application/x-zip-compressed",
				"application/x-rar-compressed", "application/rar", "application/vnd.rar",
				"application/java-archive", "application/gzip", "application/x-gzip",
				"application/x-7z-compressed", "application/x-tar",
				"application/x-apple-appstore", "application/vnd.android.package-archive",
				"application/x-msdownload", "application/force-download", "application/x-download",
				"application/vnd.apple.mobileprovision", "application/x-ipa",
				"application/x-debian-package"
			]
			var shouldDownload = extDownloadable || fileMimes.contains(mime)

			// 2) Content-Disposition: attachment / filename=（大小写不敏感取值）
			if let cd = http?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased(),
			   cd.contains("attachment") || cd.contains("filename=") {
				shouldDownload = true
			}

			// 3) 兜底：WebKit 无法渲染 且 响应非 HTML → 视为二进制文件下载。
			// 排除 HTML（自签服务器错误页恒可渲染，避免误当下载白屏）。
			let notRenderable = !navigationResponse.canShowMIMEType && mime != "text/html"
			shouldDownload = shouldDownload || notRenderable

		os_log(.info, log: .zBrowserDownload,
			   "navResponse ext=%{public}@ mime=%{public}@ canShow=%d download=%d",
			   extDownloadable ? "yes" : "no", mime, navigationResponse.canShowMIMEType ? 1 : 0, shouldDownload ? 1 : 0)

		let dlURL = response.url ?? URL(string: "about:blank")!
		if shouldDownload {
			DownloadManager.shared.startDownload(from: URLRequest(url: dlURL))
			NotificationCenter.default.post(name: .zDownloadStarted, object: dlURL)
			decisionHandler(.cancel)
		} else {
			decisionHandler(.allow)
		}
		}

		// 浏览器下载已统一走 DownloadManager.startDownload → URLSessionDataTask，不再使用 WKDownload。
	}
}
