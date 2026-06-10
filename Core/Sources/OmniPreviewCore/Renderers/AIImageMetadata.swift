import Foundation

/// Extracts AI-generation metadata embedded in PNG text chunks:
/// Automatic1111/Forge write a "parameters" tEXt chunk; ComfyUI writes
/// "prompt" (the executed node graph) and "workflow" (the editor graph).
enum AIImageMetadata {

    static let maxScanBytes = 8 * 1024 * 1024
    static let maxChunkText = 2 * 1024 * 1024

    static func sections(pngFileURL url: URL) -> [PreviewSection] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxScanBytes) else { return [] }
        let chunks = textChunks(in: data)
        guard !chunks.isEmpty else { return [] }

        var sections: [PreviewSection] = []
        if let parameters = chunks["parameters"] {
            sections.append(.keyValues(title: "AI Generation (Automatic1111 / Forge)",
                                       rows: automatic1111Rows(parameters)))
        }
        if let prompt = chunks["prompt"] {
            let rows = comfyUIRows(promptJSON: prompt, workflowJSON: chunks["workflow"])
            if !rows.isEmpty {
                sections.append(.keyValues(title: "AI Generation (ComfyUI)", rows: rows))
            }
        }
        return sections
    }

    /// Keyword → text for all tEXt and uncompressed iTXt chunks.
    static func textChunks(in data: Data) -> [String: String] {
        var chunks: [String: String] = [:]
        var reader = DataReader(data)
        guard let signature = try? reader.read(8),
              signature == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] else { return [:] }

        while reader.remaining >= 12 {
            guard let length = try? reader.readU32BE(),
                  let type = try? reader.readString(4) else { break }
            guard length <= UInt32(maxChunkText) else { break }
            guard let body = try? reader.read(Int(length)), (try? reader.skip(4)) != nil else { break }

            if type == "IEND" { break }
            if type == "tEXt", let separator = body.firstIndex(of: 0) {
                let keyword = String(decoding: body[..<separator], as: UTF8.self)
                let text = String(decoding: body[(separator + 1)...], as: UTF8.self)
                chunks[keyword] = text
            } else if type == "iTXt", let separator = body.firstIndex(of: 0) {
                let keyword = String(decoding: body[..<separator], as: UTF8.self)
                // keyword \0 compressionFlag compressionMethod langTag \0 translated \0 text
                var rest = Array(body[(separator + 1)...])
                guard rest.count >= 2 else { continue }
                let compressed = rest[0] != 0
                rest.removeFirst(2)
                guard !compressed else { continue } // compressed iTXt: skip
                let parts = rest.split(separator: 0, maxSplits: 2, omittingEmptySubsequences: false)
                if parts.count == 3 {
                    chunks[keyword] = String(decoding: parts[2], as: UTF8.self)
                }
            }
        }
        return chunks
    }

    /// A1111 "parameters" format: positive prompt, optional "Negative prompt:"
    /// line, then a comma-separated settings line (Steps, Sampler, Seed, …).
    static func automatic1111Rows(_ parameters: String) -> [KeyValueRow] {
        var rows: [KeyValueRow] = []
        var positive: [String] = []
        var negative: String?
        var settingsLine: String?

        for line in parameters.components(separatedBy: "\n") {
            if line.hasPrefix("Negative prompt:") {
                negative = String(line.dropFirst("Negative prompt:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.contains("Steps:") {
                settingsLine = line
            } else if settingsLine == nil, negative == nil {
                positive.append(line)
            }
        }

        let prompt = positive.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty { rows.append(KeyValueRow("Prompt", prompt)) }
        if let negative, !negative.isEmpty { rows.append(KeyValueRow("Negative prompt", negative)) }
        if let settingsLine {
            for setting in settingsLine.components(separatedBy: ", ") {
                let pair = setting.split(separator: ":", maxSplits: 1)
                if pair.count == 2 {
                    rows.append(KeyValueRow(
                        pair[0].trimmingCharacters(in: .whitespaces),
                        pair[1].trimmingCharacters(in: .whitespaces)
                    ))
                }
            }
        }
        return rows
    }

    /// ComfyUI "prompt" is a JSON object of node-id → {class_type, inputs}.
    static func comfyUIRows(promptJSON: String, workflowJSON: String?) -> [KeyValueRow] {
        guard let data = promptJSON.data(using: .utf8),
              let graph = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }

        var rows: [KeyValueRow] = []
        var models: [String] = []
        var loras: [String] = []
        var prompts: [String] = []
        var samplerRows: [KeyValueRow] = []

        for nodeID in graph.keys.sorted() {
            guard let node = graph[nodeID] as? [String: Any],
                  let classType = node["class_type"] as? String,
                  let inputs = node["inputs"] as? [String: Any] else { continue }

            if let checkpoint = inputs["ckpt_name"] as? String { models.append(checkpoint) }
            if let lora = inputs["lora_name"] as? String { loras.append(lora) }
            if classType.contains("CLIPTextEncode"), let text = inputs["text"] as? String, !text.isEmpty {
                prompts.append(text)
            }
            if classType.contains("Sampler"), samplerRows.isEmpty {
                if let sampler = inputs["sampler_name"] as? String {
                    samplerRows.append(KeyValueRow("Sampler", sampler))
                }
                let seed = inputs["seed"] ?? inputs["noise_seed"]
                if let seed { samplerRows.append(KeyValueRow("Seed", "\(seed)")) }
                if let steps = inputs["steps"] { samplerRows.append(KeyValueRow("Steps", "\(steps)")) }
                if let cfg = inputs["cfg"] { samplerRows.append(KeyValueRow("CFG", "\(cfg)")) }
                if let scheduler = inputs["scheduler"] as? String {
                    samplerRows.append(KeyValueRow("Scheduler", scheduler))
                }
            }
        }

        if !models.isEmpty { rows.append(KeyValueRow("Model", models.joined(separator: ", "))) }
        if !loras.isEmpty { rows.append(KeyValueRow("LoRA", loras.joined(separator: ", "))) }
        for (index, prompt) in prompts.prefix(2).enumerated() {
            rows.append(KeyValueRow(index == 0 ? "Prompt" : "Prompt (2)", String(prompt.prefix(2000))))
        }
        rows.append(contentsOf: samplerRows)
        rows.append(KeyValueRow("Nodes", "\(graph.count)"))
        if workflowJSON != nil { rows.append(KeyValueRow("Workflow", "embedded (ComfyUI editor graph)")) }
        return rows
    }
}
