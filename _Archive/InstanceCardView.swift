import SwiftUI
import AppKit

/// Card showing profile name, icon, color badge, running status and launch/stop controls.
struct InstanceCardView: View {
    let slot: Slot
    @ObservedObject var store: ProfileStore
    @ObservedObject private var monitor = ProcessMonitor.shared

    @State private var isHovering = false
    @State private var isLaunching = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var detectedStrategy: LaunchStrategy?

    private var profile: Profile { store.profile(for: slot) }
    private var instance: AppInstance? { store.instance(for: slot) }
    private var isRunning: Bool {
        guard let inst = instance else { return false }
        return monitor.isRunning(pid: inst.pid)
    }
    private var accentColor: Color { Color(profile.nsColor) }

    var body: some View {
        VStack(spacing: 14) {
            // Identity
            VStack(spacing: 10) {
                iconChip
                Text(profile.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                statusBadge
            }
            .padding(.top, 18)

            Divider().opacity(0.6)

            VStack(spacing: 12) {
                // App name + detected strategy preview
                if let url = profile.targetAppURL {
                    HStack(spacing: 6) {
                        Image(systemName: "app.dashed")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(url.deletingPathExtension().lastPathComponent)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if instance == nil, let strat = detectedStrategy {
                            strategyBadge(for: strat)
                        }
                    }
                } else {
                    Label("No app selected", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }

                // Running instance info
                if let inst = instance {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text("PID \(inst.pid)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            strategyBadge(for: inst.strategy)
                        }
                        HStack {
                            if case .bundleCopy = inst.strategy {} else {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(inst.bundleCopyURL.lastPathComponent)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(inst.launchedAt, style: .relative)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }

                actionButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(accentColor.opacity(isHovering ? 0.55 : 0.2), lineWidth: 1.5)
        )
        .shadow(color: accentColor.opacity(isHovering ? 0.22 : 0.08), radius: isHovering ? 18 : 9, y: 5)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovering)
        .onHover { isHovering = $0 }
        .onChange(of: profile.targetAppURL?.path) { _, _ in detectStrategy() }
        .onAppear { detectStrategy() }
        .alert("Launch Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Card chrome

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color(NSColor.controlBackgroundColor))
    }

    private var iconChip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [accentColor, accentColor.opacity(0.72)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            appIconView
                .padding(profile.targetAppURL != nil || profile.customIconData != nil ? 6 : 14)
        }
        .frame(width: 60, height: 60)
        .shadow(color: accentColor.opacity(0.35), radius: 8, y: 4)
    }

    // MARK: - Strategy Badge

    @ViewBuilder
    func strategyBadge(for strategy: LaunchStrategy) -> some View {
        let (label, icon, color): (String, String, Color) = {
            switch strategy {
            case .electronFlag:  return ("Direct",   "bolt.fill",          .purple)
            case .jetbrains:     return ("JetBrains", "brain.head.profile", .orange)
            case .configDir:     return ("Config",   "folder.badge.gear",  .teal)
            case .bundleCopy:    return ("Copy",     "doc.on.doc.fill",    .blue)
            }
        }()

        Label(label, systemImage: icon)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var appIconView: some View {
        if let iconData = profile.customIconData, let img = NSImage(data: iconData) {
            Image(nsImage: img).resizable().scaledToFit()
        } else if let url = profile.targetAppURL {
            let img = NSWorkspace.shared.icon(forFile: url.path)
            Image(nsImage: img).resizable().scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(isRunning ? "Running" : "Stopped")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }

    private var actionButton: some View {
        Button {
            Task { await handleAction() }
        } label: {
            HStack(spacing: 6) {
                if isLaunching {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                }
                Text(isRunning ? "Stop" : "Launch")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isRunning ? Color.red.opacity(0.15) : accentColor.opacity(0.15))
            .foregroundStyle(isRunning ? .red : accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isRunning ? Color.red.opacity(0.3) : accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLaunching || profile.targetAppURL == nil)
    }

    // MARK: - Actions

    private func detectStrategy() {
        guard let url = profile.targetAppURL else {
            detectedStrategy = nil; return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let strat = LaunchEngine.shared.detectStrategy(for: url)
            DispatchQueue.main.async { self.detectedStrategy = strat }
        }
    }

    @MainActor
    private func handleAction() async {
        if isRunning, let inst = instance {
            LaunchEngine.shared.terminate(instance: inst)
            store.setInstance(nil, for: slot)
        } else {
            isLaunching = true
            defer { isLaunching = false }
            do {
                let inst = try await LaunchEngine.shared.launch(
                    profile: profile, slot: slot
                )
                store.setInstance(inst, for: slot)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
