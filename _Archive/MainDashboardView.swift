import SwiftUI

/// Main dashboard showing two side-by-side instance cards plus a header and launch-all button.
struct MainDashboardView: View {
    @ObservedObject var store: ProfileStore
    @Environment(\.openSettings) private var openSettings

    @State private var editingSlot: Slot?
    @State private var isLaunchingAll = false

    private var needsSetup: Bool {
        store.profileA.targetAppURL == nil && store.profileB.targetAppURL == nil
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(store.profileA.nsColor).opacity(0.05),
                    Color(store.profileB.nsColor).opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                if needsSetup {
                    onboardingBanner
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                }

                // Cards
                HStack(alignment: .top, spacing: 16) {
                    cardWithEditButton(slot: .a)
                    cardWithEditButton(slot: .b)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                // Bottom bar
                bottomBar
            }
        }
        .sheet(item: $editingSlot) { slot in
            ProfileSetupView(profile: bindingForSlot(slot))
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "bubbles.and.sparkles.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
                        )
                    Text("Double Bubble")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                Text("Run any app twice, simultaneously")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var onboardingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.yellow)
            Text("Get started — choose an app for each profile below.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func cardWithEditButton(slot: Slot) -> some View {
        VStack(spacing: 8) {
            InstanceCardView(slot: slot, store: store)

            Button {
                editingSlot = slot
            } label: {
                Label("Edit Profile", systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Launch both
            Button {
                Task { await launchBoth() }
            } label: {
                HStack(spacing: 6) {
                    if isLaunchingAll {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.circle.fill")
                    }
                    Text("Launch Both")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color(store.profileA.nsColor), Color(store.profileB.nsColor)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isLaunchingAll
                      || store.profileA.targetAppURL == nil
                      || store.profileB.targetAppURL == nil)

            // Stop both
            Button {
                stopBoth()
            } label: {
                Label("Stop All", systemImage: "stop.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Actions

    @MainActor
    private func launchBoth() async {
        isLaunchingAll = true
        defer { isLaunchingAll = false }

        // Launch both slots TRULY in parallel — each in its own Task
        await withTaskGroup(of: Void.self) { group in
            for slot in Slot.allCases {
                let profile = store.profile(for: slot)
                guard profile.targetAppURL != nil,
                      store.instance(for: slot) == nil else { continue }
                group.addTask {
                    do {
                        let inst = try await LaunchEngine.shared.launch(profile: profile, slot: slot)
                        await MainActor.run { self.store.setInstance(inst, for: slot) }
                    } catch {
                        // Errors shown per-card
                    }
                }
            }
        }
    }

    private func stopBoth() {
        for slot in Slot.allCases {
            if let inst = store.instance(for: slot) {
                LaunchEngine.shared.terminate(instance: inst)
                store.setInstance(nil, for: slot)
            }
        }
    }

    // MARK: - Helpers

    private func bindingForSlot(_ slot: Slot) -> Binding<Profile> {
        slot == .a ? Binding(
            get: { self.store.profileA },
            set: { self.store.profileA = $0 }
        ) : Binding(
            get: { self.store.profileB },
            set: { self.store.profileB = $0 }
        )
    }
}

// Slot is Identifiable via ProfileStore.swift
