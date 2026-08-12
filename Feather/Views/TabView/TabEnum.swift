//
//  TabEnum.swift
//  feather
//
//  Created by samara on 22.03.2025.
//

import SwiftUI
import NimbleViews

enum TabEnum: String, CaseIterable, Hashable {
	case sources
	case library
	case settings
	
	var title: String {
		switch self {
		case .sources:     	return .localized("Sources")
		case .library: 		return .localized("Library")
		case .settings: 	return .localized("Settings")
		}
	}
	
	var icon: String {
		switch self {
		case .sources: 		return "globe.desk"
		case .library: 		return "square.grid.2x2"
		case .settings: 	return "gearshape.2"
		}
	}
	
	@ViewBuilder
	static func view(for tab: TabEnum) -> some View {
		switch tab {
		case .sources: SourcesView()
		case .library: LibraryView()
		case .settings: SettingsView()
		}
	}
	
	static var defaultTabs: [TabEnum] {
		return [
			.sources,
			.library,
			.settings
		]
	}
	
	static var customizableTabs: [TabEnum] {
		return []
	}
}
