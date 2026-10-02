/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AtollExtensionKit
import SwiftUI
import Defaults
import AppKit

/// What tapping a tab entry does.
enum TabDestination {
    /// Switches the notch content view, participating in tab selection.
    case view(NotchViews)
    /// Runs an action (typically opening a standalone panel) without selecting.
    case panel(() -> Void)
    /// Reveals a popover owned by the entry button itself.
    case popover(TabPopoverKind)
}

enum TabPopoverKind {
    case passwordGenerator
}

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let destination: TabDestination
    let experienceID: String?
    let accentColor: Color?

    init(
        label: String,
        icon: String,
        destination: TabDestination,
        experienceID: String? = nil,
        accentColor: Color? = nil
    ) {
        self.id = experienceID.map { "extension-\($0)" } ?? "system-\(label)"
        self.label = label
        self.icon = icon
        self.destination = destination
        self.experienceID = experienceID
        self.accentColor = accentColor
    }

    /// A tab that swaps the notch content when tapped.
    init(label: String, icon: String, view: NotchViews, experienceID: String? = nil, accentColor: Color? = nil) {
        self.init(
            label: label,
            icon: icon,
            destination: .view(view),
            experienceID: experienceID,
            accentColor: accentColor
        )
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.enableThirdPartyExtensions) private var enableThirdPartyExtensions
    @Default(.enableExtensionNotchExperiences) private var enableExtensionNotchExperiences
    @Default(.enableExtensionNotchTabs) private var enableExtensionNotchTabs
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Namespace var animation
    
    private var tabs: [TabModel] {
        var tabsArray: [TabModel] = []

        if homeTabVisible {
            tabsArray.append(TabModel(label: "Home", icon: "house.fill", view: .home))
        }

        if Defaults[.dynamicShelf] && !NotchEntry.shelf.isHidden {
            tabsArray.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        
        if enableTimerFeature && timerDisplayMode == .tab && !NotchEntry.timer.isHidden {
            tabsArray.append(TabModel(label: "Timer", icon: "timer", view: .timer))
        }

        // Stats tab only shown when stats feature is enabled
        if Defaults[.enableStatsFeature] && !NotchEntry.stats.isHidden {
            tabsArray.append(TabModel(label: "Stats", icon: "chart.xyaxis.line", view: .stats))
        }

        // Usage tab only shown when LLM usage feature is enabled
        if Defaults[.enableLLMUsageFeature] && !NotchEntry.llmUsage.isHidden {
            tabsArray.append(TabModel(label: "Usage", icon: "chart.bar.doc.horizontal", view: .llmUsage))
        }

        if (Defaults[.enableNotes] || (Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .separateTab))
            && !NotchEntry.notes.isHidden {
            let label = Defaults[.enableNotes] ? "Notes" : "Clipboard"
            let icon = Defaults[.enableNotes] ? "note.text" : "doc.on.clipboard"
            tabsArray.append(TabModel(label: label, icon: icon, view: .notes))
        }
        if Defaults[.enableTerminalFeature] && !NotchEntry.terminal.isHidden {
            tabsArray.append(TabModel(label: "Terminal", icon: "apple.terminal", view: .terminal))
        }

        // Utility entries sit beside Terminal: they open a window instead of
        // swapping the notch contents, so they never participate in selection.
        if NotchEntry.codeFormatter.isVisibleInTabBar {
            tabsArray.append(
                TabModel(
                    label: "Code Formatter",
                    icon: "curlybraces",
                    destination: .panel { CodeFormatterPanelManager.shared.togglePanel() }
                )
            )
        }
        if NotchEntry.passwordGenerator.isVisibleInTabBar {
            tabsArray.append(
                TabModel(
                    label: "Password Generator",
                    icon: "key.fill",
                    destination: .popover(.passwordGenerator)
                )
            )
        }

        if extensionTabsEnabled {
            for payload in extensionTabPayloads {
                guard let tab = payload.descriptor.tab else { continue }
                let accent = payload.descriptor.accentColor.swiftUIColor
                let iconName = tab.iconSymbolName ?? "puzzlepiece.extension"
                tabsArray.append(
                    TabModel(
                        label: tab.title,
                        icon: iconName,
                        view: .extensionExperience,
                        experienceID: payload.descriptor.id,
                        accentColor: accent
                    )
                )
            }
        }
        return tabsArray
    }
    var body: some View {
        HStack(spacing: 24) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { _, tab in
                let isSelected = isSelected(tab)
                let activeAccent = tab.accentColor ?? .white

                entryButton(for: tab)
                    .frame(height: 26)
                    .foregroundStyle(isSelected ? activeAccent : .gray)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill((tab.accentColor ?? Color(nsColor: .secondarySystemFill)).opacity(0.25))
                                .shadow(color: (tab.accentColor ?? .clear).opacity(0.4), radius: 8)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
        .onAppear {
            ensureValidSelection(with: tabs)
        }
    }

    @ViewBuilder
    private func entryButton(for tab: TabModel) -> some View {
        switch tab.destination {
        case .view:
            TabButton(label: tab.label, icon: tab.icon, selected: isSelected(tab)) {
                select(tab)
            }
        case .panel(let action):
            // Never renders as selected: the action owns what happens next.
            TabButton(label: tab.label, icon: tab.icon, selected: false) {
                action()
            }
        case .popover(let kind):
            PopoverTabButton(label: tab.label, icon: tab.icon, kind: kind)
        }
    }

    private func select(_ tab: TabModel) {
        guard case .view(let target) = tab.destination else { return }
        if target == .extensionExperience {
            coordinator.selectedExtensionExperienceID = tab.experienceID
        }
        coordinator.currentView = target
    }

    private var extensionTabsEnabled: Bool {
        enableThirdPartyExtensions && enableExtensionNotchExperiences && enableExtensionNotchTabs
    }

    private var extensionTabPayloads: [ExtensionNotchExperiencePayload] {
        extensionNotchExperienceManager.activeExperiences.filter { $0.descriptor.tab != nil }
    }

    private var homeTabVisible: Bool {
        guard !NotchEntry.home.isHidden else { return false }
        if enableMinimalisticUI {
            return true
        }
        return showStandardMediaControls || showCalendar || showMirror
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        guard case .view(let target) = tab.destination else { return false }
        if target == .extensionExperience {
            return coordinator.currentView == .extensionExperience
                && coordinator.selectedExtensionExperienceID == tab.experienceID
        }
        return coordinator.currentView == target
    }

    /// Falls back to the first selectable tab when the current one disappears.
    /// Action entries are skipped: they own nothing to select.
    private func ensureValidSelection(with tabs: [TabModel]) {
        let selectable = tabs.filter {
            if case .view = $0.destination { return true }
            return false
        }
        guard !selectable.isEmpty else { return }
        if selectable.contains(where: isSelected) {
            return
        }
        guard let first = selectable.first else { return }
        select(first)
    }
}

/// A tab-bar entry that reveals its own popover.
///
/// Each entry owns its presentation state, so several can live in the same
/// `ForEach` without sharing a binding. It also keeps the notch open while the
/// popover is up, matching how the other header popovers behave.
private struct PopoverTabButton: View {
    let label: String
    let icon: String
    let kind: TabPopoverKind

    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var isPresented = false

    var body: some View {
        TabButton(label: label, icon: icon, selected: false) {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverContent
        }
        .onChange(of: isPresented) { _, isActive in
            switch kind {
            case .passwordGenerator:
                vm.isPasswordGeneratorPopoverActive = isActive
            }
            if !isActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    vm.shouldRecheckHover.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private var popoverContent: some View {
        switch kind {
        case .passwordGenerator:
            PasswordGeneratorPopover()
        }
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
