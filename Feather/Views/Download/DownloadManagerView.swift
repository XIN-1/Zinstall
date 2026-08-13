//
//  DownloadManagerView.swift
//  Feather
//
//  真·下载管理器：进行中任务 + 已下载文件（点按安装）
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import NimbleViews

// MARK: - View
struct DownloadManagerView: View {
	@StateObject var downloadManager = DownloadManager.shared
	@State private var _selectedInfoAppPresenting: AnyApp?
	@State private var _selectedInstallAppPresenting: AnyApp?
	@State private var _isImportingPresenting = false
	@State private var _isDownloadingPresenting = false
	@State private var _alertDownloadString: String = ""

	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _importedApps: FetchedResults<Imported>

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("下载")) {
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
							Text("粘贴 IPA 链接，或从文件 App 导入开始下载。")
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
