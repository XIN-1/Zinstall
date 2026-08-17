//
//  enum.swift
//  Feather
//
//  Created by samara on 3.05.2025.
//

import Foundation
import Combine
import UIKit.UIImpactFeedbackGenerator
import BackgroundTasks
import os

/// 下载状态：用于列表展示「继续」按钮与断点续传。
enum DownloadState: Int, Codable {
	case downloading = 0
	case failed = 1
	case completed = 2
}

class Download: Identifiable, ObservableObject, @unchecked Sendable {
	@Published var progress: Double = 0.0
	@Published var bytesDownloaded: Int64 = 0
	@Published var totalBytes: Int64 = 0
	@Published var downloadSpeed: Int64 = 0   // 字节/秒
	@Published var unpackageProgress: Double = 0.0
	@Published var state: DownloadState = .downloading
	
	var overallProgress: Double {
		onlyArchiving
		? unpackageProgress
		: (0.3 * unpackageProgress) + (0.7 * progress)
	}
	
	var task: URLSessionDataTask?
	
	var destinationURL: URL?
	var bytesReceived: Int64 = 0
	
	let id: String
	let url: URL
	let fileName: String
	let onlyArchiving: Bool
	var sourceProvenance: SourceAppProvenance?
	/// 入口标记：manual / browser-navAction / browser-navResponse，便于诊断两条路为何表现不同。
	var entryPoint: String = "manual"
	
	init(
		id: String,
		url: URL,
		onlyArchiving: Bool = false,
		sourceProvenance: SourceAppProvenance? = nil
	) {
		self.id = id
		self.url = url
		self.onlyArchiving = onlyArchiving
		self.sourceProvenance = sourceProvenance
		self.fileName = url.lastPathComponent
	}
}

class DownloadManager: NSObject, ObservableObject {
	static let shared = DownloadManager()
	
	@Published var downloads: [Download] = []
	
	var manualDownloads: [Download] {
		downloads.filter { isManualDownload($0.id) }
	}
	
	private var _session: URLSession!
	/// 进度采样定时器：每 0.2s 读取各进行中下载的目标文件实际大小，
	/// 直接驱动 bytesDownloaded / progress，保证 UI 实时刷新（不依赖回调频率）。
	private var _progressTimer: Timer?
	/// 速度采样状态（EMA 平滑用）
	private var _lastSampledSize: [String: Int64] = [:]
	private var _lastSampleTime: [String: CFAbsoluteTime] = [:]
	private var _smoothedSpeed: [String: Int64] = [:]
	
	#if !targetEnvironment(macCatalyst)
	private func _updateBackgroundAudioState() {
		if #unavailable(iOS 26.0){
			if !downloads.isEmpty {
				BackgroundAudioManager.shared.start()
			} else  {
				BackgroundAudioManager.shared.stop()
			}
		}
	}
	#endif
	
	override init() {
		super.init()
		FileManager.default.ensureZInstallDirs()
		let configuration = URLSessionConfiguration.default
		_session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
	}
	
	func startDownload(
		from url: URL,
		id: String = UUID().uuidString,
		sourceProvenance: SourceAppProvenance? = nil,
		entryPoint: String = "manual"
	) -> Download {
		startDownload(from: URLRequest(url: url), id: id, sourceProvenance: sourceProvenance, entryPoint: entryPoint)
	}
	
	func startDownload(
		from request: URLRequest,
		id: String = UUID().uuidString,
		sourceProvenance: SourceAppProvenance? = nil,
		entryPoint: String = "manual"
	) -> Download {
		let url = request.url ?? URL(string: "about:blank")!
		let requestHasSourceProvenance = sourceProvenance != nil
		os_log(.info, log: .zBrowserDownload, "startDownload entry=%{public}@ url=%{public}@", entryPoint, url.absoluteString)
		if let existingDownload = downloads.first(where: {
			$0.url == url && ($0.sourceProvenance != nil) == requestHasSourceProvenance
		}) {
			resumeDownload(existingDownload)
			return existingDownload
		}
		
		let download = Download(id: id, url: url, sourceProvenance: sourceProvenance)
		download.entryPoint = entryPoint
		let destination = _uniqueDownloadURL(for: download.fileName)
		download.destinationURL = destination
		
		try? FileManager.default.createDirectoryIfNeeded(at: FileManager.default.downloadsDir)
		FileManager.default.createFile(atPath: destination.path, contents: nil) // 立即可见（0 字节）
		FileManager.default.excludeFromBackup(destination)
		
		let task = _session.dataTask(with: request)
		download.task = task
		task.resume()
		downloads.append(download)
		_ensureProgressTimer()
		#if !targetEnvironment(macCatalyst)
		_updateBackgroundAudioState()
		#endif
		
		return download
	}
	
	func startArchive(
		from url: URL,
		id: String = UUID().uuidString
	) -> Download {
		let download = Download(id: id, url: url, onlyArchiving: true)
		downloads.append(download)
		
		#if !targetEnvironment(macCatalyst)
		_updateBackgroundAudioState()
		#endif
		
		return download
	}
	
	func resumeDownload(_ download: Download) {
		_closeHandle(for: download.id)
		download.task?.cancel()
		// 重置速度采样基线，避免用旧文件大小算出负速度
		_lastSampledSize[download.id] = nil
		_lastSampleTime[download.id] = nil
		_smoothedSpeed[download.id] = nil
		
		// 断点续传：已下载部分且目标文件仍存在 → 带 Range 头从断点续写。
		var request = URLRequest(url: download.url)
		if download.bytesReceived > 0,
		   let dest = download.destinationURL,
		   FileManager.default.fileExists(atPath: dest.path) {
			request.setValue("bytes=\(download.bytesReceived)-", forHTTPHeaderField: "Range")
			os_log(.info, log: .zBrowserDownload, "resumeDownload: Range bytes=%lld url=%{public}@", download.bytesReceived, download.url.absoluteString)
		} else {
			// 无断点可续 → 从头来（重置偏移）
			download.bytesReceived = 0
		}
		
		let task = _session.dataTask(with: request)
		download.task = task
		download.state = .downloading
		task.resume()
		_ensureProgressTimer()
		#if !targetEnvironment(macCatalyst)
		_updateBackgroundAudioState()
		#endif
	}
	
	func cancelDownload(_ download: Download) {
		_closeHandle(for: download.id)
		download.task?.cancel()
		_clearSpeedSamples(for: download.id)
		if let dest = download.destinationURL { try? FileManager.default.removeFileIfNeeded(at: dest) } // 删半成品
		_removeDownload(download)
	}
	
	func isManualDownload(_ string: String) -> Bool {
		return string.contains("FeatherManualDownload")
	}
	
	func getDownload(by id: String) -> Download? {
		return downloads.first(where: { $0.id == id })
	}
	
	func getDownloadIndex(by id: String) -> Int? {
		return downloads.firstIndex(where: { $0.id == id })
	}
	
	func getDownload(by task: URLSessionTask) -> Download? {
		downloads.first { $0.task?.taskIdentifier == task.taskIdentifier }
	}
	
	// MARK: - 流式下载私有状态 / 工具
	
	private let _handleLock = NSLock()
	private var _fileHandles: [String: FileHandle] = [:]
	
	private func _uniqueDownloadURL(for baseName: String) -> URL {
		let dir = FileManager.default.downloadsDir
		var candidate = dir.appendingPathComponent(baseName)
		var count = 1
		while FileManager.default.fileExists(atPath: candidate.path) {
			let ext = (baseName as NSString).pathExtension
			let stem = (baseName as NSString).deletingPathExtension
			candidate = dir.appendingPathComponent(ext.isEmpty ? "\(stem) (\(count))" : "\(stem) (\(count)).\(ext)")
			count += 1
		}
		return candidate
	}
	
	private func _setHandle(_ h: FileHandle?, for id: String) {
		_handleLock.lock(); defer { _handleLock.unlock() }
		_fileHandles[id] = h
	}
	private func _handle(for id: String) -> FileHandle? {
		_handleLock.lock(); defer { _handleLock.unlock() }
		return _fileHandles[id]
	}
	private func _closeHandle(for id: String) {
		_handleLock.lock()
		if let h = _fileHandles[id] { h.closeFile(); _fileHandles[id] = nil }
		_handleLock.unlock()
	}

	// MARK: - 进度实时采样
	/// 启动进度采样定时器（主线程运行，避免后台线程改 @Published 不刷新 UI）。
	private func _ensureProgressTimer() {
		if _progressTimer != nil { return }
		DispatchQueue.main.async { [weak self] in
			guard let self, self._progressTimer == nil else { return }
			let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
				self?._sampleActiveDownloads()
			}
			RunLoop.main.add(timer, forMode: .common)
			self._progressTimer = timer
		}
	}

	/// 读取进行中下载的目标文件真实大小，更新进度与速度；
	/// 若总大小已知则算出百分比，否则仅更新已下载字节数（视图显示「下载中」+ 已下载字节）。
	private func _sampleActiveDownloads() {
		var anyActive = false
		var changed = false
		let now = CFAbsoluteTimeGetCurrent()
		for dl in downloads where dl.state == .downloading {
			anyActive = true
			guard let dest = dl.destinationURL else { continue }
			let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? 0
			if size != dl.bytesDownloaded {
				dl.bytesDownloaded = size
				dl.bytesReceived = size
				if dl.totalBytes > 0 {
					dl.progress = min(1.0, Double(size) / Double(dl.totalBytes))
				}
				changed = true
			}
			// 速度：文件大小增量 / 时间差，EMA 平滑抑制跳变
			let prevSize = _lastSampledSize[dl.id] ?? size
			let prevT = _lastSampleTime[dl.id] ?? now
			let dt = max(0.001, now - prevT)
			let raw = Int64(Double(size - prevSize) / dt)
			let prevEMA = _smoothedSpeed[dl.id] ?? 0
			let ema = Int64(Double(prevEMA) * 0.7 + Double(max(0, raw)) * 0.3)
			if ema != dl.downloadSpeed { dl.downloadSpeed = ema }
			_lastSampledSize[dl.id] = size
			_lastSampleTime[dl.id] = now
			_smoothedSpeed[dl.id] = ema
		}
		// 强制列表整体重渲染（兜底第三方列表组件不响应子项 @ObservedObject）；
		// 即便字节未变也重绘，使速度在停滞时平滑衰减到 0。
		if changed || anyActive { self.objectWillChange.send() }
		if !anyActive {
			_progressTimer?.invalidate()
			_progressTimer = nil
		}
	}
	
	private func _clearSpeedSamples(for id: String) {
		_lastSampledSize[id] = nil
		_lastSampleTime[id] = nil
		_smoothedSpeed[id] = nil
	}

	private func _removeDownload(_ download: Download) {
		_clearSpeedSamples(for: download.id)
		DispatchQueue.main.async {
			if let index = self.getDownloadIndex(by: download.id) {
				self.downloads.remove(at: index)
			}
			#if !targetEnvironment(macCatalyst)
			self._updateBackgroundAudioState()
			if #available(iOS 26.0, *) {
				BackgroundTaskManager.shared.stopTask(for: download.id, success: false)
			}
			#endif
		}
	}
	
	private func _isImportable(_ fileName: String) -> Bool {
		let ext = (fileName as NSString).pathExtension.lowercased()
		return ext == "ipa" || ext == "tipa" || ext == "zip"
	}
	
	func importFile(from url: URL, id: String = "FeatherManualDownload_\(UUID().uuidString)") -> Download {
		let download = Download(id: id, url: url, onlyArchiving: true)
		downloads.append(download)
		#if !targetEnvironment(macCatalyst)
		_updateBackgroundAudioState()
		#endif
		
		let fm = FileManager.default
		let dir = fm.downloadsDir
		try? fm.createDirectoryIfNeeded(at: dir)
		
		let visibleURL: URL
		if url.path.hasPrefix(dir.path) {
			visibleURL = url
		} else {
			let dest = _uniqueDownloadURL(for: url.lastPathComponent)
			try? fm.removeFileIfNeeded(at: dest)
			try? fm.copyItem(at: url, to: dest)
			visibleURL = dest
		}
		fm.excludeFromBackup(visibleURL)
		download.destinationURL = visibleURL
		try? handlePachageFile(url: visibleURL, dl: download)
		return download
	}
}

extension DownloadManager: URLSessionDataDelegate {
	
	func handlePachageFile(url: URL, dl: Download) throws {
		FR.handlePackageFile(url, download: dl) { err in
			if err != nil {
				let generator = UINotificationFeedbackGenerator()
				generator.notificationOccurred(.error)
			}
			
			DispatchQueue.main.async {
				if let index = DownloadManager.shared.getDownloadIndex(by: dl.id) {
					DownloadManager.shared.downloads.remove(at: index)
					
					#if !targetEnvironment(macCatalyst)
					if #available(iOS 26.0, *) {
						BackgroundTaskManager.shared.updateProgress(for: dl.id, progress: 1.0)
					}
					
					self._updateBackgroundAudioState()
					#endif
				}
			}
		}
	}
	
	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
					didReceive response: URLResponse,
					completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
		guard let download = getDownload(by: dataTask) else {
			completionHandler(.cancel); return
		}
		let http = response as? HTTPURLResponse
		let isResume = (http?.statusCode == 206) && download.bytesReceived > 0
		os_log(.info, log: .zBrowserDownload, "didReceiveResponse entry=%{public}@ status=%d resume=%{public}@ expected=%lld",
			   download.entryPoint, http?.statusCode ?? -1, isResume ? "yes" : "no", response.expectedContentLength)

		// 总大小来源优先级：expectedContentLength → Content-Length 头 → Content-Range 的总大小。
		// 某些服务器对带浏览器头的请求走分块/压缩而不给 Content-Length，这里尽量从响应头兜底取到总大小。
		var total: Int64 = 0
		let raw = response.expectedContentLength
		if raw > 0 {
			total = raw
		} else if let http {
			if let cl = (http.allHeaderFields["Content-Length"] as? String)?.trimmingCharacters(in: .whitespaces),
			   let v = Int64(cl), v > 0 {
				total = v
			} else if let cr = (http.allHeaderFields["Content-Range"] as? String)?.trimmingCharacters(in: .whitespaces) {
				let parts = cr.components(separatedBy: "/")
				if parts.count == 2, let v = Int64(parts[1].trimmingCharacters(in: .whitespaces)), v > 0 {
					total = v
				}
			}
		}
		DispatchQueue.main.async {
			if isResume {
				// 206：total 为剩余字节，总大小 = 已下 + 剩余
				if total > 0 { download.totalBytes = download.bytesReceived + total }
				download.bytesDownloaded = download.bytesReceived
			} else {
				download.totalBytes = max(0, total)
				download.bytesDownloaded = 0
				download.bytesReceived = 0
			}
		}
		// 兜底：GET 未给总大小（分块/压缩）时，发 HEAD 探测 Content-Length。
		// 对浏览器与 +链接 两条路一视同仁，能补回「总大小/进度百分比」。
		if total <= 0 {
			var headReq = URLRequest(url: download.url)
			headReq.httpMethod = "HEAD"
			_session.dataTask(with: headReq) { _, resp, _ in
				guard let h = resp as? HTTPURLResponse,
					  let cl = (h.allHeaderFields["Content-Length"] as? String)?.trimmingCharacters(in: .whitespaces),
					  let v = Int64(cl), v > 0 else { return }
				DispatchQueue.main.async {
					if download.state == .downloading && download.totalBytes <= 0 {
						download.totalBytes = v
						os_log(.info, log: .zBrowserDownload, "headProbe entry=%{public}@ total=%lld", download.entryPoint, v)
					}
				}
			}.resume()
		}
		if let url = download.destinationURL,
		   let handle = try? FileHandle(forWritingTo: url) {
			if isResume {
				handle.seekToEndOfFile()      // 续写：从已下载末尾追加
			} else {
				handle.truncateFile(atOffset: 0)
			}
			_setHandle(handle, for: download.id)
		}
		completionHandler(.allow)
	}
	
	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		guard let download = getDownload(by: dataTask) else { return }
		_handle(for: download.id)?.write(data)
		DispatchQueue.main.async {
			download.bytesReceived += Int64(data.count)
			download.bytesDownloaded = download.bytesReceived
			if download.totalBytes > 0 {
				download.progress = Double(download.bytesReceived) / Double(download.totalBytes)
			}
			#if !targetEnvironment(macCatalyst)
			if #available(iOS 26.0, *) {
				BackgroundTaskManager.shared.updateProgress(for: download.id, progress: download.overallProgress)
			}
			#endif
		}
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard let download = getDownload(by: task) else { return }
		_closeHandle(for: download.id)
		
		if let urlError = error as? URLError, urlError.code == .cancelled {
			// 用户取消：cancelDownload 已删条目的话此处 download 不存在；若仍在则保留为可续传
			DispatchQueue.main.async { self._clearSpeedSamples(for: download.id) }
			return
		}
		if let error {
			os_log(.error, log: .zBrowserDownload, "download failed: %{public}@", error.localizedDescription)
			// 保留条目与已下载的部分文件，标记失败，便于「继续」断点续传
			DispatchQueue.main.async {
				download.downloadSpeed = 0
				download.state = .failed
				self._clearSpeedSamples(for: download.id)
			}
			return
		}
		
		guard let url = download.destinationURL else { return }
		DispatchQueue.main.async {
			download.downloadSpeed = 0
			download.state = .completed
			self._clearSpeedSamples(for: download.id)
			if self._isImportable(download.fileName) {
				try? self.handlePachageFile(url: url, dl: download)
			} else {
				self._removeDownload(download)
			}
		}
	}
}

// MARK: - 下载触发诊断日志
extension Notification.Name {
	static let zDownloadStarted = Notification.Name("ZDownloadStarted")
}

extension OSLog {
	/// 浏览器下载诊断日志：真机 Console.app 过滤 "Zinstall.BrowserDownload" 即可查看。
	static let zBrowserDownload = OSLog(subsystem: "Zinstall.BrowserDownload", category: "BrowserDownload")
}

extension DownloadManager {
	/// 常见下载型 MIME → 扩展名（落点无扩展名时兜底）。
	private static let _mimeToExt: [String: String] = [
		"application/octet-stream": "bin",
		"application/zip": "zip",
		"application/x-zip": "zip",
		"application/x-zip-compressed": "zip",
		"application/java-archive": "jar",
		"application/vnd.android.package-archive": "apk",
		"application/x-apple-appstore": "ipa",
		"application/vnd.rar": "rar",
		"application/x-rar-compressed": "rar",
		"application/x-tipa": "tipa",
		"application/x-debian-package": "deb",
		"application/gzip": "gz",
		"application/x-7z-compressed": "7z",
		"application/pdf": "pdf",
		"image/ipa": "ipa"
	]

	static func _extension(forMIME mime: String) -> String {
		let m = mime.lowercased().trimmingCharacters(in: .whitespaces)
		if let ext = _mimeToExt[m] { return ext }
		if m.contains("zip") { return "zip" }
		if m.contains("tipa") { return "tipa" }
		if m.contains("ipa") || m.contains("ios") { return "ipa" }
		if m.contains("apk") { return "apk" }
		if m.contains("rar") { return "rar" }
		if m.contains("deb") || m.contains("tweak") { return "deb" }
		return ""
	}
}
