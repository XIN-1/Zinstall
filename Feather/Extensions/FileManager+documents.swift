//
//  FileManager+documents.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import Foundation.NSFileManager

extension FileManager {
	/// Gives apps Signed directory
	var archives: URL {
		URL.documentsDirectory.appendingPathComponent("Archives")
	}
	
	/// Gives apps Signed directory
	var signed: URL {
		URL.documentsDirectory.appendingPathComponent("Signed")
	}
	
	/// Gives apps Signed directory with a UUID appending path
	func signed(_ uuid: String) -> URL {
		signed.appendingPathComponent(uuid)
	}
	
	/// Gives apps Staging (import temp) directory
	var staging: URL {
		URL.documentsDirectory.appendingPathComponent("Staging")
	}
	
	/// Gives apps Staging (import temp) directory with a UUID appending path
	func staging(_ uuid: String) -> URL {
		staging.appendingPathComponent(uuid)
	}
	
	/// Gives apps Certificates directory
	var certificates: URL {
		URL.documentsDirectory.appendingPathComponent("Certificates")
	}
	/// Gives apps Certificates directory with a UUID appending path
	func certificates(_ uuid: String) -> URL {
		certificates.appendingPathComponent(uuid)
	}
}

extension FileManager {
	/// zinstall 应用目录 = App 的 Documents 沙盒，在「文件」App 中显示为 "Z install"
	var appDirectory: URL { URL.documentsDirectory }

	/// 下载/导入的最终文件直接平铺在应用目录根（即 Documents/<name>），用户可见
	var downloadsDir: URL { URL.documentsDirectory }

	func downloads(_ name: String) -> URL { URL.documentsDirectory.appendingPathComponent(name) }

	/// 临时工作目录：直接建在应用目录根，命名带 `Feather` 前缀，便于「清理缓存」按前缀识别
	func temporaryWork(_ name: String) -> URL {
		URL.documentsDirectory.appendingPathComponent(name, isDirectory: true)
	}

	/// 对单个文件/目录排除 iCloud 备份（大 IPA 不占备份配额；逐文件打标，不影响 Archives/Signed 等）
	func excludeFromBackup(_ url: URL) {
		var u = url
		try? (u as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
	}
}

extension FileManager {
	/// 启动时调用：确保已知大目录存在并排除 iCloud 备份。
	/// 下载文件 / 临时工作目录在创建时各自调用 `excludeFromBackup(_:)`，故此处无需再处理。
	func ensureZInstallDirs() {
		for dir in [archives, signed, staging, certificates] {
			try? createDirectoryIfNeeded(at: dir)
			excludeFromBackup(dir)
		}
		
		// 迁移：旧版命名 "Unsigned" → "Staging"，保留任何进行中的导入内容
		let oldUnsigned = URL.documentsDirectory.appendingPathComponent("Unsigned")
		let newStaging = staging
		if FileManager.default.fileExists(atPath: oldUnsigned.path),
		   !FileManager.default.fileExists(atPath: newStaging.path) {
			try? FileManager.default.moveItem(at: oldUnsigned, to: newStaging)
		}
	}
}
