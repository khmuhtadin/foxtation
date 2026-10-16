import AppKit
import SwiftUI

struct LicenseSettings: View {
    @ObservedObject var model: AppModel

    @StateObject private var form = LicenseForm()

    private var cloud: CloudStatus { model.cloud }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if cloud.isActivated { activatedCard } else { entryCard }
            if let error = form.error {
                Text(error).font(FXFont.detail).foregroundStyle(Color.fxBad)
            } else if cloud.isActivated, let licenseError = cloud.licenseError {
                Label(licenseError, systemImage: "exclamationmark.circle")
                    .font(FXFont.caption).foregroundStyle(Color.fxSecondary)
            }
        }
        .task {
            if !model.isSnapshot { await cloud.refresh() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Foxtation Cloud").font(.system(size: 15, weight: .semibold))
                    StatusBadge(text: cloud.isActivated ? "Active" : "Not activated", good: cloud.isActivated)
                }
                Text(cloud.isActivated ? "Subscription via Polar" : "Clean, punctuated text in your style. Subscription via Polar.")
                    .font(FXFont.detail).opacity(0.75)
            }
            .foregroundStyle(Color.fxCard)
            Spacer()
            if cloud.isActivated {
                Button("Manage subscription ↗") {
                    NSWorkspace.shared.open(cloud.license.flatMap { URL(string: $0.portalUrl) } ?? CloudCleanup.portalURL)
                }
                .fxButton(.secondary, compact: true)
            } else {
                Button("Get a license ↗") { NSWorkspace.shared.open(CloudCleanup.buyURL) }
                    .fxButton(.secondary, compact: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.fxInk))
    }

    // MARK: - Not activated

    private var entryCard: some View {
        FXCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("License key").font(FXFont.body.weight(.medium))
                HStack(spacing: 8) {
                    TextField("FOXTATION-…", text: $form.keyField)
                        .textFieldStyle(.plain)
                        .font(FXFont.mono)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.fxWash))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.fxSeparator))
                        .onSubmit(activate)
                    Button(form.busy ? "Checking…" : "Activate", action: activate)
                        .fxButton(.primary)
                        .disabled(form.busy || trimmedKey.isEmpty)
                        .opacity(form.busy || trimmedKey.isEmpty ? 0.5 : 1)
                }
                Text("Paste the key from your Polar receipt. This Mac is then activated against it.")
                    .font(FXFont.detail).foregroundStyle(Color.fxSecondary)
            }
        }
    }

    private var trimmedKey: String { form.keyField.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func activate() {
        let key = trimmedKey
        guard !key.isEmpty, !form.busy, !model.isSnapshot else { return }
        form.busy = true
        form.error = nil
        Task { @MainActor in
            defer { form.busy = false }
            do {
                let activationID = try await CloudCleanup.activate(key)
                model.settings.licenseKey = key
                model.settings.activationID = activationID
                model.settings.cloudCleanup = true
                form.keyField = ""
                await cloud.refresh()
            } catch {
                form.error = error.localizedDescription
            }
        }
    }

    // MARK: - Activated

    private var activatedCard: some View {
        RowsCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("License key").font(FXFont.body.weight(.medium))
                HStack(spacing: 8) {
                    Text(form.showKey ? model.settings.licenseKey : maskedKey)
                        .font(FXFont.mono)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.fxWash))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.fxSeparator))
                    Button(form.showKey ? "Hide" : "Show") { form.showKey.toggle() }.fxButton(.secondary, compact: true)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.settings.licenseKey, forType: .string)
                    }
                    .fxButton(.secondary, compact: true)
                    Button("Use another key") { useAnotherKey() }.fxButton(.secondary, compact: true)
                }
            }
            .padding(14)

            RowDivider()

            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fxSecondary)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.fxWash))
                VStack(alignment: .leading, spacing: 2) {
                    Text("This Mac · \(deviceName)").font(FXFont.body.weight(.medium))
                    if !deviceDetail.isEmpty {
                        Text(deviceDetail).font(FXFont.detail).foregroundStyle(Color.fxSecondary)
                    }
                }
                Spacer()
                Button("Deactivate") { deactivate() }.fxButton(.destructive, compact: true).disabled(form.busy)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            RowDivider()

            usage.padding(14)
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cloud cleanups today").font(FXFont.body.weight(.medium))
                Spacer()
                if let usage = cloud.usage {
                    (Text("\(Format.number(usage.used))").foregroundColor(.fxInk).fontWeight(.semibold)
                     + Text(" / \(Format.number(usage.limit))")
                     + Text(usage.resetDate.map { " · resets \(Format.time($0))" } ?? ""))
                        .font(FXFont.detail).monospacedDigit().foregroundStyle(Color.fxSecondary)
                } else {
                    Text("—").font(FXFont.detail).foregroundStyle(Color.fxSecondary)
                }
            }
            UsageBar(fraction: cloud.usage.map { Double($0.used) / Double(max(1, $0.limit)) } ?? 0)
            Text("Past the limit, dictation keeps working and pastes the raw transcript.")
                .font(FXFont.detail).foregroundStyle(Color.fxSecondary)
        }
    }

    /// "FOXT-••••-••••-••••-A59C": only the first and last four characters.
    private var maskedKey: String {
        let key = model.settings.licenseKey
        guard key.count > 8 else { return cloud.license?.displayKey ?? String(repeating: "•", count: key.count) }
        return "\(key.prefix(4))-••••-••••-••••-\(key.suffix(4))"
    }

    private var deviceName: String {
        cloud.license?.thisDevice.label ?? (Host.current().localizedName ?? "Mac")
    }

    /// "Activated 12 Oct 2026 · 3 activations allowed", leaving out what the server didn't send.
    private var deviceDetail: String {
        var parts: [String] = []
        if let date = parseISODate(cloud.license?.thisDevice.createdAt) {
            parts.append("Activated \(Format.day(date))")
        }
        if let activations = cloud.license?.activations {
            switch (activations.used, activations.limit) {
            case let (used?, limit?): parts.append("\(used) of \(limit) activations used")
            case let (nil, limit?): parts.append("\(limit) activations allowed")
            case let (used?, nil): parts.append("\(used) activations used")
            case (nil, nil): break
            }
        }
        return parts.joined(separator: " · ")
    }

    private func deactivate() {
        guard confirm("Deactivate this Mac?",
                      "Cloud cleanup stops on this Mac and frees one activation. You can activate again with the same key.",
                      action: "Deactivate") else { return }
        runDeactivate()
    }

    private func useAnotherKey() {
        guard confirm("Use another license key?",
                      "This Mac is deactivated from the current license first.",
                      action: "Deactivate") else { return }
        runDeactivate()
    }

    private func runDeactivate() {
        guard !model.isSnapshot else { return }
        form.busy = true
        form.error = nil
        form.showKey = false
        Task { @MainActor in
            defer { form.busy = false }
            do {
                try await cloud.deactivate()
            } catch {
                form.error = "Forgot the activation on this Mac, but the server didn’t confirm: \(error.localizedDescription)"
            }
        }
    }
}

final class LicenseForm: ObservableObject {
    @Published var keyField = ""
    @Published var busy = false
    @Published var error: String?
    @Published var showKey = false
}
