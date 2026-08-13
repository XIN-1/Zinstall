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
import WebKit

class Download: Identifiable, @unchecked Sendable {
	@Published var progress: Double = 0.0
	@Published var bytesDownloaded: Int64 = 0
	@Published var totalBytes: Int64 = 0
	@Published var unpackageProgress: Double = 0.0
	
	var overallProgress: Double {
		onlyArchiving
		? unpackageProgress
		: (0.3 * unpackageProgress) + (0.7 * progress)
	}
	
	var task: URLSessionDataTask?
	// 不再使用 resumeData（dataTask 无原生断点续传，按需求接受此代价）
	
	var destinationURL: URL?
	var bytesReceived: Int64 = 0
	
	let id: String
	let url: URL
	let fileName: String
	let onlyArchiving: Bool
	var sourceProvenance: SourceAppProvenance?
	
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
		sourceProvenance: SourceAppProvenance? = nil
	) -> Download {
		let requestHasSourceProvenance = sourceProvenance != nil
		if let existingDownload = downloads.first(where: {
			$0.url == url && ($0.sourceProvenance != nil) == requestHasSourceProvenance
		}) {
			resumeDownload(existingDownload)
			return existingDownload
		}
		
		let download = Download(id: id, url: url, sourceProvenance: sourceProvenance)
		let destination = _uniqueDownloadURL(for: download.fileName)
		download.destinationURL = destination
		
		try? FileManager.default.createDirectoryIfNeeded(at: FileManager.default.downloadsDir)
		FileManager.default.createFile(atPath: destination.path, contents: nil) // ✅ 立即可见（0 字节）
		FileManager.default.excludeFromBackup(destination)                       // 大 IPA 排除 iCloud 备份
		
		let task = _session.dataTask(with: url)
		download.task = task
		task.resume()
		downloads.append(download)
		
		#if !targetEnvironment(macCatalyst)
		if #available(iOS 26.0, *) {
			BackgroundTaskManager.shared.startTask(for: id, filename: download.fileName)
		} else {
			_updateBackgroundAudioState()
		}
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
		let task = _session.dataTask(with: download.url)
		download.task = task
		task.resume()
		#if !targetEnvironment(macCatalyst)
		_updateBackgroundAudioState()
		#endif
	}
	
	func cancelDownload(_ download: Download) {
		_closeHandle(for: download.id)
		download.task?.cancel()
		try? FileManager.default.removeFileIfNeeded(at: download.destinationURL) // 删半成品
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
	
	private func _removeDownload(_ download: Download) {
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
		let total = response.expectedContentLength
		DispatchQueue.main.async {
			download.totalBytes = total
			download.bytesDownloaded = 0
			download.bytesReceived = 0
		}
		if let url = download.destinationURL,
		   let handle = try? FileHandle(forWritingTo: url) {
			handle.truncateFile(atOffset: 0)
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
			return
		}
		if let error {
			try? FileManager.default.removeFileIfNeeded(at: download.destinationURL)
			_removeDownload(download)
			return
		}
		
		guard let url = download.destinationURL else { return }
		DispatchQueue.main.async {
			if self._isImportable(download.fileName) {
				try? self.handlePachageFile(url: url, dl: download)
			} else {
				self._removeDownload(download)
			}
		}
	}
}

extension DownloadManager: WKDownloadDelegate {
	func download(_ download: WKDownload,
				  decideDestinationUsing response: URLResponse,
				  suggestedFilename: String,
				  completionHandler: @escaping (URL?) -> Void) {
		let originalURL = _wkOriginalURL(for: download)
		let baseName: String
		if !(suggestedFilename as NSString).deletingPathExtension.isEmpty {
			baseName = suggestedFilename
		} else {
			baseName = originalURL?.lastPathComponent ?? "download"
		}
		let destination = _uniqueDownloadURL(for: baseName)
		try? FileManager.default.createDirectoryIfNeeded(at: FileManager.default.downloadsDir)
		FileManager.default.excludeFromBackup(destination)
		
		let dl = Download(id: UUID().uuidString, url: destination)
		dl.destinationURL = destination
		_setWKDownload(dl, for: download)
		
		DispatchQueue.main.async {
			self.downloads.append(dl)
			#if !targetEnvironment(macCatalyst)
			if #available(iOS 26.0, *) {
				BackgroundTaskManager.shared.startTask(for: dl.id, filename: dl.fileName)
			} else {
				self._updateBackgroundAudioState()
			}
			#endif
			NotificationCenter.default.post(name: .zDownloadStarted, object: dl.url)
		}
		completionHandler(destination)
	}
	
	func download(_ download: WKDownload, didReceive progress: Double,
				  totalBytesExpected: Int64, totalBytesWritten: Int64) {
		guard let dl = _wkDownload(for: download) else { return }
		DispatchQueue.main.async {
			dl.bytesDownloaded = totalBytesWritten
			dl.totalBytes = totalBytesExpected
			dl.progress = totalBytesExpected > 0 ? Double(totalBytesWritten) / Double(totalBytesExpected) : progress
			#if !targetEnvironment(macCatalyst)
			if #available(iOS 26.0, *) {
				BackgroundTaskManager.shared.updateProgress(for: dl.id, progress: dl.overallProgress)
			}
			#endif
		}
	}
	
	func downloadDidFinish(_ download: WKDownload) {
		guard let dl = _wkDownload(for: download), let url = dl.destinationURL else { return }
		if _isImportable(dl.fileName) {
			try? handlePachageFile(url: url, dl: dl)
		} else {
			_removeDownload(dl)
		}
	}
	
	func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
		guard let dl = _wkDownload(for: download) else { return }
		try? FileManager.default.removeFileIfNeeded(at: dl.destinationURL)
		_removeDownload(dl)
	}
}

// MARK: - WKDownload ↔ Download 关联
private var _wkDownloadKey: UInt8 = 0
private var _wkOriginalURLKey: UInt8 = 0
extension DownloadManager {
	func _setWKDownload(_ dl: Download, for wk: WKDownload) {
		objc_setAssociatedObject(wk, &_wkDownloadKey, dl, .OBJC_ASSOCIATION_RETAIN)
	}
	func _wkDownload(for wk: WKDownload) -> Download? {
		objc_getAssociatedObject(wk, &_wkDownloadKey) as? Download
	}
	func _setWKOriginalURL(_ url: URL, for wk: WKDownload) {
		objc_setAssociatedObject(wk, &_wkOriginalURLKey, url, .OBJC_ASSOCIATION_RETAIN)
	}
	func _wkOriginalURL(for wk: WKDownload) -> URL? {
		objc_getAssociatedObject(wk, &_wkOriginalURLKey) as? URL
	}
}

extension Notification.Name {
	static let zDownloadStarted = Notification.Name("ZDownloadStarted")
}
