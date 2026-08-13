//
//  AppearanceView.swift
//  Feather
//
//  Created by samara on 7.05.2025.
//

import SwiftUI
import NimbleViews
import UIKit

// MARK: - View
// dear god help me
struct AppearanceView: View {
	@AppStorage("Feather.userInterfaceStyle")
	private var _userIntefacerStyle: Int = UIUserInterfaceStyle.unspecified.rawValue
	
	@AppStorage("Feather.shouldTintIcons")
	private var _shouldTintIcons: Bool = false
	
	@AppStorage("Feather.shouldChangeIconsBasedOffStyle")
	private var _shouldChangeIconsBasedOffStyle: Bool = false
	
	@AppStorage("Feather.userTintColor")
	private var _selectedColorHex: String = "#848ef9"
	
	private var _tintColorBinding: Binding<Color> {
		Binding(
			get: { Color(hex: _selectedColorHex) },
			set: { _selectedColorHex = $0.toHex() }
		)
	}
	
	// MARK: Body
	var body: some View {
		NBList(.localized("Appearance")) {
			Section {
				Picker(.localized("Appearance"), selection: $_userIntefacerStyle) {
					ForEach(UIUserInterfaceStyle.allCases.sorted(by: { $0.rawValue < $1.rawValue }), id: \.rawValue) { style in
						Text(style.label).tag(style.rawValue)
					}
				}
				.pickerStyle(.segmented)
			}
			
			NBSection(.localized("Theme")) {
				AppearanceTintColorView()
					.listRowInsets(EdgeInsets())
					.listRowBackground(EmptyView())
			}
			
			Section {
				ColorPicker(
					.localized("Custom Theme Color"),
					selection: _tintColorBinding,
					supportsOpacity: false
				)
			}
			
			if #available(iOS 18.0, *) {
				NBSection(.localized("Library")) {
					Toggle(.localized("Dynamic Icons"), isOn: $_shouldChangeIconsBasedOffStyle)
					if #available(iOS 18.2, *) {
						Toggle(.localized("Tinted Icons"), isOn: $_shouldTintIcons)
					}
				}
			}
		}
		.onChange(of: _userIntefacerStyle) { value in
			if let style = UIUserInterfaceStyle(rawValue: value) {
				UIApplication.topViewController()?.view.window?.overrideUserInterfaceStyle = style
			}
		}
	}
}
