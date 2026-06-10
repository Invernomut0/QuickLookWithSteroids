import SwiftUI
import OmniPreviewCore

struct LicenseSettingsView: View {
    @State private var keyInput: String = ""
    @State private var status: ActivationStatus = .idle
    @State private var isProUnlocked = LicenseManager.shared.isProUnlocked
    @State private var currentKey = LicenseManager.shared.licenseKey

    enum ActivationStatus: Equatable {
        case idle, verifying, success, failure(String)
    }

    var body: some View {
        Form {
            statusSection
            if isProUnlocked {
                deactivateSection
            } else {
                activateSection
            }
            proFeaturesSection
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear {
            isProUnlocked = LicenseManager.shared.isProUnlocked
            currentKey = LicenseManager.shared.licenseKey
        }
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isProUnlocked ? Color.green : Color.secondary.opacity(0.6))
                        .frame(width: 8, height: 8)
                    Text(isProUnlocked ? "Pro — Active" : "Free")
                        .fontWeight(isProUnlocked ? .medium : .regular)
                        .foregroundStyle(isProUnlocked ? .primary : .secondary)
                }
            }
            if let key = currentKey, isProUnlocked {
                LabeledContent("License key") {
                    Text(maskedKey(key))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Activate

    private var activateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                TextField("XXXX-XXXX-XXXX-XXXX", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .disableAutocorrection(true)

                HStack {
                    Button {
                        activate()
                    } label: {
                        if case .verifying = status {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Verifying…")
                            }
                        } else {
                            Text("Activate Pro")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty
                              || status == .verifying)

                    Spacer()

                    if case .success = status {
                        Label("Activated", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    }
                    if case .failure(let msg) = status {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Activate License")
        } footer: {
            HStack {
                Text("Don't have a license?")
                    .foregroundStyle(.secondary)
                Link("Buy OmniPreview Pro →", destination: URL(string: "https://invernomuto2.gumroad.com/l/lghiqc")!)
                    .foregroundStyle(Color.accentColor)
            }
            .font(.caption)
        }
    }

    // MARK: Deactivate

    private var deactivateSection: some View {
        Section {
            Button("Deactivate license on this Mac", role: .destructive) {
                LicenseManager.shared.deactivate()
                isProUnlocked = false
                currentKey = nil
                status = .idle
            }
        } footer: {
            Text("Your license can be reactivated at any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Pro features list

    private var proFeaturesSection: some View {
        Section {
            ForEach(ProTier.proFeatureDescriptions, id: \.id) { feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(isProUnlocked ? Color.accentColor : .secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.name)
                            .font(.callout.weight(.medium))
                        Text(feature.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isProUnlocked ? "checkmark.circle.fill" : "lock.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(isProUnlocked ? Color.green : Color.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Pro Features (\(ProTier.proRendererIDs.count) renderer plugins)")
        }
    }

    // MARK: Actions

    private func activate() {
        status = .verifying
        let key = keyInput.trimmingCharacters(in: .whitespaces)
        Task { @MainActor in
            do {
                let ok = try await LicenseManager.shared.activate(key: key)
                if ok {
                    status = .success
                    isProUnlocked = true
                    currentKey = key
                    keyInput = ""
                } else {
                    status = .failure("Invalid license key.")
                }
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }

    private func maskedKey(_ key: String) -> String {
        let parts = key.components(separatedBy: "-")
        guard parts.count >= 2 else {
            return String(key.prefix(4)) + String(repeating: "•", count: max(0, key.count - 4))
        }
        return parts.dropLast().map { String(repeating: "•", count: $0.count) }
            .joined(separator: "-") + "-" + (parts.last ?? "")
    }
}
