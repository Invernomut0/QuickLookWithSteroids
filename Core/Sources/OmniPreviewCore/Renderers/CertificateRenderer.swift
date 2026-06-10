import Foundation
import Security

/// X.509 certificate preview (PEM and DER) via the Security framework.
public struct CertificateRenderer: PreviewRenderer {
    public static let id = "certificate"
    public static let displayName = "X.509 Certificate"

    static let maxFileSize: UInt64 = 5 * 1024 * 1024
    static let maxCertificates = 25

    public init() {}

    public func canRender(_ file: DetectedFile) -> Bool {
        file.kind == .pemCertificate || file.kind == .derCertificate
    }

    public func render(_ file: DetectedFile) throws -> PreviewDocument {
        guard file.fileSize <= Self.maxFileSize else {
            throw PreviewError.tooLarge("certificate files over \(Format.bytes(Self.maxFileSize)) are not previewed")
        }
        let data = try Data(contentsOf: file.url)

        let certificates: [SecCertificate]
        if file.kind == .pemCertificate {
            certificates = Self.pemCertificates(in: data)
        } else if let certificate = SecCertificateCreateWithData(nil, data as CFData) {
            certificates = [certificate]
        } else {
            certificates = []
        }
        guard !certificates.isEmpty else {
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
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var certificates: [SecCertificate] = []
        var scanning = text[...]
        while let begin = scanning.range(of: "-----BEGIN CERTIFICATE-----"),
              let end = scanning.range(of: "-----END CERTIFICATE-----") {
            let base64 = scanning[begin.upperBound..<end.lowerBound]
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
            if let der = Data(base64Encoded: base64),
               let certificate = SecCertificateCreateWithData(nil, der as CFData) {
                certificates.append(certificate)
            }
            scanning = scanning[end.upperBound...]
        }
        return certificates
    }

    static func rows(for certificate: SecCertificate) -> [KeyValueRow] {
        var rows: [KeyValueRow] = []
        if let subject = SecCertificateCopySubjectSummary(certificate) as String? {
            rows.append(KeyValueRow("Subject", subject))
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
}
