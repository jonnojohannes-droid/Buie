import Foundation
import llama

enum InferenceError: LocalizedError {
    case load, context, template, tokenize, promptTooLong, decode, incomplete, encoding

    var errorDescription: String? {
        switch self {
        case .load: return "Het model kon niet worden geladen. Gebruik een ondersteund GGUF-model dat op dit apparaat past."
        case .context: return "De modelcontext kon niet worden gemaakt. Mogelijk is er onvoldoende geheugen."
        case .template: return "De instructietemplate van dit model wordt niet ondersteund."
        case .tokenize: return "De opdracht kon niet worden verwerkt."
        case .promptTooLong: return "De opdracht is te lang voor de modelcontext."
        case .decode: return "Het model kon de opdracht niet uitvoeren."
        case .incomplete: return "De uitvoer is afgebroken omdat de modelcontext vol is. Probeer een kleinere opdracht."
        case .encoding: return "Het model gaf ongeldige tekst terug."
        }
    }
}

enum Inference {
    static func generate(modelURL: URL, instruction: String) throws -> String {
        llama_backend_init()
        defer { llama_backend_free() }
        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #endif
        guard let model = llama_model_load_from_file(modelURL.path, modelParams) else { throw InferenceError.load }
        defer { llama_model_free(model) }
        guard let template = llama_model_chat_template(model, nil) else { throw InferenceError.template }
        let prompt = """
        Maak de gevraagde broncode. Antwoord uitsluitend met één geldig JSON-object in dit formaat:
        {"files":[{"path":"relatief/pad","content":"volledige bestandsinhoud"}]}
        Gebruik JSON-escaping voor alle tekst. Geef uitsluitend bestanden, geen uitleg of markdown.
        Maak geen absolute paden of paden met .. aan.

        Opdracht:
        \(instruction)
        """
        let formatted: String = try prompt.withCString { content in
            try "user".withCString { role in
                var message = llama_chat_message(role: role, content: content)
                let needed = llama_chat_apply_template(template, &message, 1, true, nil, 0)
                guard needed > 0 else { throw InferenceError.template }
                var buffer = [CChar](repeating: 0, count: Int(needed) + 1)
                let written = llama_chat_apply_template(template, &message, 1, true, &buffer, Int32(buffer.count))
                guard written == needed else { throw InferenceError.template }
                return String(decoding: buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        guard let vocab = llama_model_get_vocab(model), formatted.utf8.count < 1_000_000 else { throw InferenceError.tokenize }
        var tokens = [llama_token](repeating: 0, count: formatted.utf8.count + 8)
        let count = llama_tokenize(vocab, formatted, Int32(formatted.utf8.count), &tokens, Int32(tokens.count), true, true)
        guard count > 0 else { throw InferenceError.tokenize }
        tokens.removeSubrange(Int(count)..<tokens.count)
        let contextSize: UInt32 = 4096
        guard tokens.count < Int(contextSize) - 128 else { throw InferenceError.promptTooLong }
        var params = llama_context_default_params()
        params.n_ctx = contextSize
        params.n_batch = 512
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
        params.n_threads_batch = params.n_threads
        guard let context = llama_init_from_model(model, params) else { throw InferenceError.context }
        defer { llama_free(context) }
        guard let sampler = llama_sampler_init_greedy() else { throw InferenceError.context }
        defer { llama_sampler_free(sampler) }

        for start in stride(from: 0, to: tokens.count, by: 512) {
            try Task.checkCancellation()
            let end = min(start + 512, tokens.count)
            let status = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress!.advanced(by: start), Int32(end - start)))
            }
            guard status == 0 else { throw InferenceError.decode }
        }
        var output = [UInt8]()
        for _ in tokens.count..<Int(contextSize) {
            try Task.checkCancellation()
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) {
                guard let text = String(bytes: output, encoding: .utf8) else { throw InferenceError.encoding }
                return text
            }
            var piece = [CChar](repeating: 0, count: 256)
            var length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if length < 0 {
                piece = [CChar](repeating: 0, count: Int(-length))
                length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            }
            guard length >= 0 else { throw InferenceError.decode }
            output.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) })
            guard llama_decode(context, llama_batch_get_one(&token, 1)) == 0 else { throw InferenceError.decode }
        }
        throw InferenceError.incomplete
    }
}
