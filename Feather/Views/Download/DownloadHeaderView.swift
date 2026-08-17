//
//  DownloadHeaderView.swift
//  Feather
//
//  Created by samara on 16.05.2025.
//

import SwiftUI
import Combine
import NimbleExtensions

struct DownloadHeaderView: View {
	@ObservedObject var downloadManager: DownloadManager
	
	var body: some View {
		ZStack {
			if !downloadManager.manualDownloads.isEmpty {
				VStack {
					VStack(spacing: 12) {
						if let firstDownload = downloadManager.manualDownloads.first {
							DownloadItemView(download: firstDownload)
							
							if downloadManager.manualDownloads.count > 1 {
								HStack {
									Spacer()
									Text(verbatim: "+\(downloadManager.manualDownloads.count - 1)")
										.font(.caption)
										.foregroundColor(.secondary)
										.padding(.vertical, 4)
								}
							}
						}
					}
					.padding(.horizontal)
				}
				.transition(.move(edge: .top).combined(with: .opacity))
			}
		}
		.animation(.spring(), value: downloadManager.manualDownloads.count)
	}
}

struct DownloadItemView: View {
	/// 直接订阅 Download 的 @Published，保证进度/字节数实时驱动 UI 刷新
	/// （原用 let + @State + .onReceive 间接刷新，高频数据回调下不可靠，百分比会卡住）。
	@ObservedObject var download: Download

	/// 综合进度：普通下载直接取下载进度（0→1，进度条完整填满）；仅解包=解包进度。
	private var overallProgress: Double {
		download.onlyArchiving
			? download.unpackageProgress
			: download.progress
	}

	/// 服务器未返回总大小（分块传输 / 无 Content-Length）时为 true，
	/// 此时进度未知，改用不确定进度环 + 「下载中」，避免卡在 0%。
	private var isIndeterminate: Bool { download.totalBytes <= 0 }

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(download.fileName)
				.font(.subheadline)
				.lineLimit(1)

			if isIndeterminate {
				ProgressView()
					.progressViewStyle(.linear)
			} else {
				ProgressView(value: overallProgress)
					.progressViewStyle(.linear)
			}

			HStack {
				if download.state == .paused {
					Text(verbatim: "已暂停")
						.foregroundStyle(.secondary)
				} else if download.state == .failed {
					Text(verbatim: "导入失败")
						.foregroundStyle(.red)
				} else if isIndeterminate {
					Text(verbatim: "下载中")
				} else {
					Text(verbatim: "\(Int(overallProgress * 100))%")
						.contentTransition(.numericText())
				}
				if download.state == .downloading {
					Text(verbatim: download.downloadSpeed.formattedSpeed)
						.contentTransition(.numericText())
				}
				Spacer()
				if isIndeterminate && download.state != .failed && download.state != .paused {
					Text(verbatim: download.bytesDownloaded.formattedByteCount)
						.contentTransition(.numericText())
				} else {
					Text(verbatim: "\(download.bytesDownloaded.formattedByteCount) / \(download.totalBytes.formattedByteCount)")
						.contentTransition(.numericText())
				}
			}
			.font(.caption)
			.foregroundColor(.secondary)
		}
		.padding(.vertical, 4)
	}
}

extension Int64 {
	var formattedSpeed: String {
		let b = Double(self)
		let kb = b / 1024
		let mb = kb / 1024
		if mb >= 1 { return String(format: "%.1f MB/s", mb) }
		if kb >= 1 { return String(format: "%.0f KB/s", kb) }
		return "\(Int(b)) B/s"
	}
}
