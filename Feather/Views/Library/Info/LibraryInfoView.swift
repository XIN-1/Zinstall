//
//  LibraryInfoView.swift
//  Feather
//

import SwiftUI
import NimbleViews

// MARK: - View
struct LibraryInfoView: View {
	var app: AppInfoPresentable
	
	// MARK: Body
	var body: some View {
		NBNavigationView(app.name ?? "", displayMode: .inline) {
			List {
				Section {} header: {
					FRAppIconView(app: app)
						.frame(maxWidth: .infinity, alignment: .center)
				}
				
				_infoSection(for: app)
				
				Section {
					Button(.localized("Open in Files"), systemImage: "folder") {
						UIApplication.open(Storage.shared.getUuidDirectory(for: app)!.toSharedDocumentsURL()!)
					}
				}
			}
			.toolbar {
				NBToolbarButton(role: .close)
			}
		}
	}
}

// MARK: - Extension: View
extension LibraryInfoView {
	@ViewBuilder
	private func _infoSection(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Info")) {
			if let name = app.name {
				_infoCell(.localized("Name"), desc: name)
			}
			
			if let ver = app.version {
				_infoCell(.localized("Version"), desc: ver)
			}
			
			if let id = app.identifier {
				_infoCell(.localized("Identifier"), desc: id)
			}
			
			if let date = app.date {
				_infoCell(.localized("Date Added"), desc: date.formatted())
			}
		}
	}
	
	@ViewBuilder
	private func _infoCell(_ title: String, desc: String) -> some View {
		LabeledContent(title) {
			Text(desc)
		}
		.copyableText(desc)
	}
}
