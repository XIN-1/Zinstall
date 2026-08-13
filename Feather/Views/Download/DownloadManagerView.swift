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
						let dl = downloadManager.startArchive(from: url, id: id)
						try? downloadManager.handlePachageFile(url: url, dl: dl)
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
				BrowserView(model: _browser) { url in
					_startBrowserDownload(url)
				}

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

	private func _startBrowserDownload(_ url: URL) {
		_ = downloadManager.startDownload(
			from: url,
			id: "FeatherManualDownload_\(UUID().uuidString)"
		)
		_bannerDownloadURL = url
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
// 复用已验证的 DownloadItemView（内部用 .onReceive 订阅 @Published，
// 因为 Download 只遵循 Identifiable/Sendable，并非 ObservableObject）
private struct _DownloadRow: View {
	let download: Download

	var body: some View {
		HStack(spacing: 12) {
			DownloadItemView(download: download)

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
	var onDownload: (URL) -> Void

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeUIView(context: Context) -> WKWebView {
		let config = WKWebViewConfiguration()
		let webView = WKWebView(frame: .zero, configuration: config)
		webView.allowsBackForwardNavigationGestures = true
		webView.navigationDelegate = context.coordinator
		context.coordinator.model = model
		context.coordinator.onDownload = onDownload
		context.coordinator.observeProgress(webView)
		model.webView = webView
		return webView
	}

	func updateUIView(_ uiView: WKWebView, context: Context) {
		context.coordinator.model = model
		context.coordinator.onDownload = onDownload
		model.webView = uiView
	}

	// MARK: Coordinator
	final class Coordinator: NSObject, WKNavigationDelegate {
		var model: BrowserViewModel?
		var onDownload: ((URL) -> Void)?
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

		func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
			guard let url = navigationAction.request.url else {
				decisionHandler(.allow)
				return
			}

			// 新窗口（target="_blank"）→ 在当前视图打开
			if navigationAction.targetFrame == nil {
				webView.load(navigationAction.request)
				decisionHandler(.cancel)
				return
			}

			let shouldDownload: Bool
			if #available(iOS 14.5, *) {
				shouldDownload = Self.isDownloadable(url) || navigationAction.shouldPerformDownload
			} else {
				shouldDownload = Self.isDownloadable(url)
			}

			if shouldDownload {
				onDownload?(url)
				decisionHandler(.cancel)
				return
			}

			decisionHandler(.allow)
		}

		func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
			if let url = navigationResponse.response.url, Self.isDownloadable(url) {
				onDownload?(url)
				decisionHandler(.cancel)
				return
			}
			decisionHandler(.allow)
		}

		func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
			if let url = webView.url, Self.isDownloadable(url) {
				onDownload?(url)
				webView.stopLoading()
			}
		}
	}
}
