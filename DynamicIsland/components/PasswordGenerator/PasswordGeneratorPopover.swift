/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

import AppKit
import Defaults
import SwiftUI

/// Compact popover shown by the notch's password entry: generated password,
/// its strength, and regeneration / copy controls.
struct PasswordGeneratorPopover: View {
    @ObservedObject var generator = PasswordGenerator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var justCopied = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    private var message: String? {
        generator.validationMessage(for: generator.currentRules)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            passwordCard
            strengthSection
            actions

            Text(footerText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 300)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(12)
        .onAppear {
            generator.generate()
            justCopied = Defaults[.passwordAutoCopyOnGenerate]
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)

            Text("Password Generator")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var passwordCard: some View {
        Group {
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(8)
            } else {
                Text(generator.lastPassword.isEmpty ? String(localized: "Tap Generate") : generator.lastPassword)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(generator.lastPassword.isEmpty ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        copyPassword()
                    }
            }
        }
    }

    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(generator.strength(for: generator.lastPassword).localizedName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(strengthColor)

                Spacer()

                Text("\(Int(generator.entropyBits(for: generator.lastPassword))) bits")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(strengthColor)
                        .frame(width: max(0, proxy.size.width * generator.strength(for: generator.lastPassword).progress))
                }
            }
            .frame(height: 5)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: { generator.generate(); markCopied(false) }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                    Text("Generate")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: copyPassword) {
                HStack(spacing: 6) {
                    Image(systemName: justCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                    Text(justCopied ? "Copied" : "Copy")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(generator.lastPassword.isEmpty)
        }
    }

    private var strengthColor: Color {
        generator.lastPassword.isEmpty ? .secondary : generator.strength(for: generator.lastPassword).color
    }

    private var footerText: String {
        if Defaults[.passwordAutoCopyOnGenerate] {
            return String(localized: "Passwords use your cryptographically secure system random source and are copied automatically. Adjust length and character sets in Settings › Password Generator.")
        }
        return String(localized: "Passwords use your cryptographically secure system random source. Adjust length and character sets in Settings › Password Generator.")
    }

    private func copyPassword() {
        guard !generator.lastPassword.isEmpty else { return }
        PasswordGenerator.copyToPasteboard(generator.lastPassword)
        markCopied(true)

        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        }
    }

    private func markCopied(_ copied: Bool) {
        copyFeedbackTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            justCopied = copied
        }
        guard copied else { return }
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.15)) {
                justCopied = false
            }
        }
    }
}

#Preview {
    PasswordGeneratorPopover()
        .frame(width: 300, height: 300)
}
