//
//  ResetView.swift
//  Feather
//
//  Created by samara on 19.06.2025.
//

import SwiftUI
import NimbleViews
import Nuke
import CoreData

// MARK: - View
struct ResetView: View {
	// MARK: Body
	var body: some View {
		NBList("重置") {
			_cache()
			_data()
			_all()
		}
	}
	
	private func _cacheSize() -> String {
		var totalCacheSize = URLCache.shared.currentDiskUsage
		if let nukeCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
			totalCacheSize += nukeCache.totalSize
		}
		return "\(ByteCountFormatter.string(fromByteCount: Int64(totalCacheSize), countStyle: .file))"
	}
	
	static func resetAlert(
		title: String,
		message: String = "",
		action: @escaping () -> Void
	) {
		let action = UIAlertAction(
			title: "继续",
			style: .destructive
		) { _ in
			action()
			UIApplication.shared.suspendAndReopen()
		}
		
		let style: UIAlertController.Style = UIDevice.current.userInterfaceIdiom == .pad
			? .alert
			: .actionSheet
		
		var msg = ""
		if !message.isEmpty { msg = message + "\n" }
		msg.append("此操作不可撤销，确定继续吗？")

		UIAlertController.showAlertWithCancel(
			title: title,
			message: msg,
			style: style,
			actions: [action]
		)
	}
}

// MARK: - View extension
extension ResetView {
	@ViewBuilder
	private func _cache() -> some View {
		Section("缓存清理") {
			Button("清除工作缓存", systemImage: "xmark.rectangle.portrait") {
				Self.resetAlert(title: "清除工作缓存") {
					Self.clearWorkCache()
				}
			}
			
			Button("清除网络缓存", systemImage: "xmark.rectangle.portrait") {
				Self.resetAlert(
					title: "清除网络缓存",
					message: _cacheSize()
				) {
					Self.clearNetworkCache()
				}
			}
			
			Button("清除下载缓存", systemImage: "tray.circle") {
				Self.resetAlert(title: "清除下载缓存") {
					Self.clearDownloadCache()
				}
			}
		}
	}
	
	@ViewBuilder
	private func _data() -> some View {
		Section("数据清理") {
			Button("清除资源库", systemImage: "xmark.circle") {
				Self.resetAlert(
					title: "清除资源库",
					message: Storage.shared.countContent(for: Imported.self)
				) {
					Self.deleteImportedApps()
				}
			}
			
			Button("清除源", systemImage: "xmark.circle") {
				Self.resetAlert(
					title: "清除源",
					message: Storage.shared.countContent(for: AltSource.self)
				) {
					Self.resetSources()
				}
			}
		}
	}
	
	@ViewBuilder
	private func _all() -> some View {
		Section("全部重置") {
			Button("重置设置", systemImage: "xmark.octagon") {
				Self.resetAlert(title: "重置设置") {
					Self.resetUserDefaults()
				}
			}
			
			Button("重置全部", systemImage: "xmark.octagon") {
				Self.resetAlert(title: "重置全部") {
					Self.resetAll()
				}
			}
		}
		.foregroundStyle(.red)
	}
}

// MARK: - View extension: reset
extension ResetView {
	static func clearWorkCache() {
		let fileManager = FileManager.default
		// 系统 tmp（原有）
		let tmpDirectory = fileManager.temporaryDirectory
		if let files = try? fileManager.contentsOfDirectory(atPath: tmpDirectory.path()) {
			for file in files {
				try? fileManager.removeItem(atPath: tmpDirectory.appendingPathComponent(file).path())
			}
		}
		// 清理应用目录根里的临时工作目录（Documents/FeatherImport_*、FeatherInstall_*、FeatherTweak_*）
		// 只删带 `Feather` 前缀的项，绝不误删用户下载的 IPA/zip 与 Archives/Staging/Certificates
		let prefixes = ["FeatherImport_", "FeatherInstall_", "FeatherTweak_"]
		let root = URL.documentsDirectory
		if let files = try? fileManager.contentsOfDirectory(atPath: root.path()) {
			for f in files where prefixes.contains(where: { f.hasPrefix($0) }) {
				try? fileManager.removeItem(atPath: root.appendingPathComponent(f).path())
			}
		}
	}
	
	static func clearNetworkCache() {
		URLCache.shared.removeAllCachedResponses()
		HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
		
		if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
			dataCache.removeAll()
		}
		
		if let imageCache = ImagePipeline.shared.configuration.imageCache as? Nuke.ImageCache {
			imageCache.removeAll()
		}
	}
	
	static func clearDownloadCache() {
		let dm = DownloadManager.shared
		// 1) 先取消所有未完成的下载任务（清理 Downloads/ 下的半成品）
		for d in dm.downloads where d.state != .completed {
			dm.cancelDownload(d)
		}
		// 2) 清空内存下载列表
		dm.downloads.removeAll()
		// 3) 删除 Downloads/ 子目录下所有文件（App 自管区，绝不碰 Documents 根的用户文件）
		let dir = FileManager.default.downloadsDir
		if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path()) {
			for f in files {
				try? FileManager.default.removeItem(atPath: dir.appendingPathComponent(f).path())
			}
		}
	}
	
	static func resetSources() {
		Storage.shared.clearContext(request: AltSource.fetchRequest())
	}
	
	static func deleteImportedApps() {
		Storage.shared.deleteSourceMetadata(kind: .imported)
		Storage.shared.clearContext(request: Imported.fetchRequest())
		try? FileManager.default.removeFileIfNeeded(at: FileManager.default.staging)
	}
	
	static func resetUserDefaults() {
		UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
	}
	
	static func resetAll() {
		clearWorkCache()
		clearNetworkCache()
		clearDownloadCache()
		resetSources()
		deleteImportedApps()
		resetUserDefaults()
	}
}
