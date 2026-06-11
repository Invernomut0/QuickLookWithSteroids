import Foundation
import Security
import CryptoKit

/// X.509 certificate preview (PEM and DER) via the Security framework.
public struct CertificateRenderer: PreviewRenderer {
    public static let id = "certificate"
    public static let displayName = "X.509 Certificate"

    static let maxFileSize: UInt64 = 5 * 1024 * 1024
    static let maxCertificates = 25

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        switch file.kind {
        case .pemCertificate, .derCertificate, .pkcs12: return true
        default: return false
        }
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        guard file.fileSize <= Self.maxFileSize else {
            throw PreviewError.tooLarge("certificate files over \(Format.bytes(Self.maxFileSize)) are not previewed")
        }
        if file.kind == .pkcs12 {
            // PKCS#12 contents are encrypted; identify the container only.
            return PreviewDocument(
                title: file.url.lastPathComponent,
                subtitle: "PKCS#12 Identity",
                iconSystemName: "lock.shield",
                sections: [.keyValues(title: "Container", rows: [
                    KeyValueRow("Format", "PKCS#12 (PFX)"),
                    KeyValueRow("Contents", "Certificates and private keys (password protected)"),
                    KeyValueRow("File size", Format.bytes(file.fileSize)),
                ])]
            )
        }
        let data = try Data(contentsOf: file.url)

        let certificates: [SecCertificate]
        let pemBlocks: [(label: String, der: Data)]
        if file.kind == .pemCertificate {
            pemBlocks = Self.pemBlocks(in: data)
            certificates = Self.pemCertificates(from: pemBlocks)
        } else if let certificate = SecCertificateCreateWithData(nil, data as CFData) {
            pemBlocks = []
            certificates = [certificate]
        } else {
            pemBlocks = []
            certificates = []
        }
        guard !certificates.isEmpty else {
            if file.kind == .pemCertificate {
                let labels = pemBlocks.map { $0.label }.joined(separator: ", ")
                return PreviewDocument(
                    title: file.url.lastPathComponent,
                    subtitle: "PEM Container",
                    iconSystemName: "lock.shield",
                    sections: [.keyValues(title: "Summary", rows: [
                        KeyValueRow("PEM blocks", "\(pemBlocks.count)"),
                        KeyValueRow("Block types", labels.isEmpty ? "unknown" : labels),
                        KeyValueRow("File size", Format.bytes(file.fileSize)),
                        KeyValueRow("Note", "No parseable X.509 certificates found in this PEM"),
                    ])]
                )
            }
            throw PreviewError.corruptFile("no parseable certificates found")
        }

        var sections: [PreviewSection] = []
        for (index, certificate) in certificates.prefix(Self.maxCertificates).enumerated() {
            let title = certificates.count > 1 ? "Certificate \(index + 1)" : "Certificate"
            sections.append(.keyValues(title: title, rows: Self.rows(for: certificate)))
        }

        return PreviewDocument(
            title: file.url.lastPathComponent,
            subtitle: certificates.count == 1 ? "X.509 Certificate" : "\(certificates.count) X.509 Certificates",
            iconSystemName: "checkmark.seal",
            sections: sections
        )
    }

    static func pemCertificates(in data: Data) -> [SecCertificate] {
        pemCertificates(from: pemBlocks(in: data))
    }

    static func pemCertificates(from blocks: [(label: String, der: Data)]) -> [SecCertificate] {
        let certificateLabels: Set<String> = ["CERTIFICATE", "TRUSTED CERTIFICATE", "X509 CERTIFICATE"]
        return blocks.compactMap { block in
            guard certificateLabels.contains(block.label.uppercased()) else { return nil }
            return SecCertificateCreateWithData(nil, block.der as CFData)
        }
    }

    static func pemBlocks(in data: Data) -> [(label: String, der: Data)] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        guard let regex = try? NSRegularExpression(
            pattern: "-----BEGIN ([A-Z0-9 ]+)-----([\\s\\S]*?)-----END \\1-----",
            options: [.caseInsensitive]
        ) else { return [] }

        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var blocks: [(label: String, der: Data)] = []
        regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match,
                  let labelRange = Range(match.range(at: 1), in: text),
                  let bodyRange = Range(match.range(at: 2), in: text) else { return }

            let label = String(text[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let base64 = String(text[bodyRange]).components(separatedBy: .whitespacesAndNewlines).joined()
            if let der = Data(base64Encoded: base64) {
                blocks.append((label, der))
            }
        }
        return blocks
    }

    static func rows(for certificate: SecCertificate) -> [KeyValueRow] {
        var rows: [KeyValueRow] = []
        if let subject = SecCertificateCopySubjectSummary(certificate) as String? {
            rows.append(KeyValueRow("Subject", subject))
        }
        if let fingerprint = sha256Fingerprint(for: certificate) {
            rows.append(KeyValueRow("SHA-256", fingerprint))
        }
        if let serial = SecCertificateCopySerialNumberData(certificate, nil) as Data? {
            rows.append(KeyValueRow("Serial", serial.map { String(format: "%02X", $0) }.joined(separator: ":")))
        }

        let oids = [kSecOIDX509V1IssuerName, kSecOIDX509V1ValidityNotBefore, kSecOIDX509V1ValidityNotAfter]
        let values = SecCertificateCopyValues(certificate, oids as CFArray, nil) as? [String: [String: Any]] ?? [:]

        if let issuer = values[kSecOIDX509V1IssuerName as String],
           let parts = issuer[kSecPropertyKeyValue as String] as? [[String: Any]] {
            let summary = parts
                .compactMap { $0[kSecPropertyKeyValue as String] as? String }
                .joined(separator: ", ")
            if !summary.isEmpty { rows.append(KeyValueRow("Issuer", summary)) }
        }
        if let date = validityDate(values, oid: kSecOIDX509V1ValidityNotBefore) {
            rows.append(KeyValueRow("Valid from", Format.date(date)))
        }
        if let date = validityDate(values, oid: kSecOIDX509V1ValidityNotAfter) {
            let expired = date < Date()
            rows.append(KeyValueRow("Valid until", Format.date(date) + (expired ? "  (EXPIRED)" : "")))
        }
        return rows
    }

    private static func validityDate(_ values: [String: [String: Any]], oid: CFString) -> Date? {
        guard let entry = values[oid as String],
              let seconds = entry[kSecPropertyKeyValue as String] as? NSNumber else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
    }

    static func sha256Fingerprint(for certificate: SecCertificate) -> String? {
        let der = SecCertificateCopyData(certificate) as Data
        guard !der.isEmpty else { return nil }
        return sha256Hex(der)
    }

    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
