import Foundation
import CoreFoundation

private struct TiebaWebThreadSubmissionResponseDTO: Decodable {
    private struct DataDTO: Decodable {
        let result: Int?
        let hasResult: Bool
        let errorCode: Int?
        let hasErrorCode: Bool
        let legacyErrorCode: Int?
        let hasLegacyErrorCode: Bool
        let threadIDs: [String]
        let postIDs: [String]
        let hasUnparseableIdentifier: Bool
        let message: String
        let challengePayload: TiebaWebSubmissionChallengePayload

        private enum CodingKeys: String, CodingKey {
            case result
            case errorCode = "error_code"
            case legacyErrorCode = "err_code"
            case threadID = "tid"
            case postID = "pid"
            case message = "msg"
        }

        init(from decoder: Swift.Decoder) throws {
            challengePayload = try TiebaWebSubmissionChallengePayload(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hasResult = container.contains(.result)
            result = container.submissionInt(forKey: .result)
            hasErrorCode = container.contains(.errorCode)
            errorCode = container.submissionInt(forKey: .errorCode)
            hasLegacyErrorCode = container.contains(.legacyErrorCode)
            legacyErrorCode = container.submissionInt(forKey: .legacyErrorCode)
            let threadID = container.submissionIdentifierString(forKey: .threadID)
            let postID = container.submissionIdentifierString(forKey: .postID)
            threadIDs = [threadID].compactMap { $0 }
            postIDs = [postID].compactMap { $0 }
            hasUnparseableIdentifier = [CodingKeys.threadID, .postID].contains {
                container.contains($0)
                    && container.submissionIdentifierString(forKey: $0)?
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            }
            message = container.decodeStringOrScalar(forKey: .message) ?? ""
        }
    }

    let result: Int?
    let hasResult: Bool
    let errorCode: Int?
    let hasErrorCode: Bool
    let legacyErrorCode: Int?
    let hasLegacyErrorCode: Bool
    let errorMessage: String
    let legacyErrorMessage: String
    let threadIDs: [String]
    let postIDs: [String]
    let hasUnparseableIdentifier: Bool
    private let challengePayload: TiebaWebSubmissionChallengePayload
    private let data: DataDTO?

    private enum CodingKeys: String, CodingKey {
        case result
        case errorCode = "error_code"
        case legacyErrorCode = "err_code"
        case errorMessage = "error_msg"
        case legacyErrorMessage = "err_msg"
        case threadID = "tid"
        case postID = "pid"
        case data
    }

    init(from decoder: Swift.Decoder) throws {
        challengePayload = try TiebaWebSubmissionChallengePayload(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedData = try? container.decodeIfPresent(DataDTO.self, forKey: .data)
        data = decodedData
        let topResult = container.submissionInt(forKey: .result)
        hasResult = container.contains(.result) || (decodedData?.hasResult ?? false)
        if let topResult, let nestedResult = decodedData?.result, topResult != nestedResult {
            result = nil
        } else {
            result = topResult ?? decodedData?.result
        }
        let topErrorCode = container.submissionInt(forKey: .errorCode)
        hasErrorCode = container.contains(.errorCode) || (decodedData?.hasErrorCode ?? false)
        if let topErrorCode,
           let nestedErrorCode = decodedData?.errorCode,
           topErrorCode != nestedErrorCode {
            errorCode = nil
        } else {
            errorCode = topErrorCode ?? decodedData?.errorCode
        }
        let topLegacyErrorCode = container.submissionInt(forKey: .legacyErrorCode)
        hasLegacyErrorCode = container.contains(.legacyErrorCode)
            || (decodedData?.hasLegacyErrorCode ?? false)
        if let topLegacyErrorCode,
           let nestedLegacyErrorCode = decodedData?.legacyErrorCode,
           topLegacyErrorCode != nestedLegacyErrorCode {
            legacyErrorCode = nil
        } else {
            legacyErrorCode = topLegacyErrorCode ?? decodedData?.legacyErrorCode
        }
        errorMessage = container.decodeStringOrScalar(forKey: .errorMessage) ?? ""
        legacyErrorMessage = container.decodeStringOrScalar(forKey: .legacyErrorMessage) ?? ""
        let threadID = container.submissionIdentifierString(forKey: .threadID)
        let postID = container.submissionIdentifierString(forKey: .postID)
        threadIDs = [threadID].compactMap { $0 } + (decodedData?.threadIDs ?? [])
        postIDs = [postID].compactMap { $0 } + (decodedData?.postIDs ?? [])
        hasUnparseableIdentifier = [CodingKeys.threadID, .postID].contains {
            container.contains($0)
                && container.submissionIdentifierString(forKey: $0)?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        } || (decodedData?.hasUnparseableIdentifier ?? false)
    }

    var submissionReceipt: ContentSubmissionReceipt {
        get throws {
            // A present-but-unparseable status is not a trustworthy explicit
            // success or failure response after a write has been dispatched.
            guard (hasResult == false || result != nil),
                  (hasErrorCode == false || errorCode != nil),
                  (hasLegacyErrorCode == false || legacyErrorCode != nil) else {
                throw ContentSubmissionError.outcomeUnknown
            }

            let codes = [errorCode, legacyErrorCode].compactMap { $0 }
            guard Set(codes).count <= 1 else {
                throw ContentSubmissionError.outcomeUnknown
            }
            let code = codes.first
            let resultIsSuccess = result == 1
            let resultIsFailure = hasResult && resultIsSuccess == false
            let codeIsSuccess = code == 0
            let codeIsFailure = code.map { $0 != 0 } ?? false
            guard (resultIsSuccess && codeIsFailure) == false,
                  (resultIsFailure && codeIsSuccess) == false else {
                throw ContentSubmissionError.outcomeUnknown
            }

            let messages = normalizedSubmissionMessages([
                errorMessage,
                legacyErrorMessage,
                data?.message ?? ""
            ])
            let message = messages.first ?? ""
            if let code,
               code != 0,
               TiebaAPIError.isSessionExpired(code: code, message: message) {
                throw ContentSubmissionError.sessionExpired
            }
            if let challenge = TiebaWebSubmissionChallengePayload.challenge(
                from: [challengePayload] + [data?.challengePayload].compactMap { $0 },
                messages: messages
            ) {
                throw ContentSubmissionError.verificationRequired(challenge)
            }
            if let code, code != 0 {
                throw ContentSubmissionError.business(code: code, message: message)
            }
            if resultIsFailure {
                throw ContentSubmissionError.business(code: -1, message: message)
            }
            guard resultIsSuccess || codeIsSuccess else {
                throw ContentSubmissionError.outcomeUnknown
            }

            guard hasUnparseableIdentifier == false else {
                throw ContentSubmissionError.outcomeUnknown
            }
            let returnedThreadIDs = try validatedPositiveInt64Values(threadIDs)
            guard returnedThreadIDs.count == 1,
                  let resolvedThreadID = returnedThreadIDs.first else {
                throw ContentSubmissionError.outcomeUnknown
            }
            let returnedPostIDs = try validatedPositiveUInt64Values(postIDs)
            guard returnedPostIDs.count <= 1 else {
                throw ContentSubmissionError.outcomeUnknown
            }
            return ContentSubmissionReceipt(
                threadID: resolvedThreadID,
                postID: returnedPostIDs.first
            )
        }
    }
}

struct TiebaWebUploadPictureResponseDTO: Decodable, Equatable {
    let errorCode: Int?
    private let hasErrorCode: Bool
    let errorMessage: String
    let imageInfo: String

    private enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case legacyErrorCode = "err_code"
        case errorMessage = "error_msg"
        case camelErrorMessage = "errorMsg"
        case legacyErrorMessage = "err_msg"
        case legacyCamelErrorMessage = "errMsg"
        case imageInfo = "image_info"
        case camelImageInfo = "imageInfo"
    }

    init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasPrimaryCode = container.contains(.errorCode)
        let hasLegacyCode = container.contains(.legacyErrorCode)
        hasErrorCode = hasPrimaryCode || hasLegacyCode
        let primaryCode = container.submissionInt(forKey: .errorCode)
        let legacyCode = container.submissionInt(forKey: .legacyErrorCode)
        if let primaryCode, let legacyCode, primaryCode != legacyCode {
            errorCode = nil
        } else {
            errorCode = primaryCode ?? legacyCode
        }
        errorMessage = container.decodeStringOrScalar(forKey: .errorMessage)
            ?? container.decodeStringOrScalar(forKey: .camelErrorMessage)
            ?? container.decodeStringOrScalar(forKey: .legacyErrorMessage)
            ?? container.decodeStringOrScalar(forKey: .legacyCamelErrorMessage)
            ?? ""
        imageInfo = container.decodeStringOrScalar(forKey: .imageInfo)
            ?? container.decodeStringOrScalar(forKey: .camelImageInfo)
            ?? ""
    }

    func validatedImageInfo() throws -> String {
        guard hasErrorCode == false || errorCode != nil else {
            throw ContentSubmissionError.business(code: -1, message: "图片上传响应状态无效。")
        }
        if let errorCode, errorCode != 0 {
            if TiebaAPIError.isSessionExpired(code: errorCode, message: errorMessage) {
                throw ContentSubmissionError.sessionExpired
            }
            throw ContentSubmissionError.business(
                code: errorCode,
                message: errorMessage.isEmpty ? "图片上传失败。" : errorMessage
            )
        }
        let normalized = imageInfo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false,
              normalized.utf8.count <= 16_384,
              containsASCIIControlLineBreak(normalized) == false else {
            throw ContentSubmissionError.business(code: -1, message: "贴吧没有返回有效的图片信息。")
        }
        return normalized
    }
}

struct TiebaWebReplySubmissionResponseDTO: Decodable {
    private struct DataDTO: Decodable {
        let result: Int?
        let hasResult: Bool
        let codes: [Int]
        let hasUnparseableCode: Bool
        let messages: [String]
        let threadIDs: [String]
        let postIDs: [String]
        let hasUnparseableIdentifier: Bool
        let challengePayload: TiebaWebSubmissionChallengePayload

        private enum CodingKeys: String, CodingKey {
            case result
            case errorCode = "error_code"
            case legacyErrorCode = "err_code"
            case no
            case errno
            case errorNo = "error_no"
            case errorMessage = "error_msg"
            case legacyErrorMessage = "err_msg"
            case error
            case message = "msg"
            case threadID = "tid"
            case postID = "pid"
            case alternatePostID = "post_id"
        }

        init(from decoder: Swift.Decoder) throws {
            challengePayload = try TiebaWebSubmissionChallengePayload(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hasResult = container.contains(.result)
            result = container.submissionInt(forKey: .result)
            let codeKeys: [CodingKeys] = [.errorCode, .legacyErrorCode, .no, .errno, .errorNo]
            codes = codeKeys.compactMap { container.submissionInt(forKey: $0) }
            hasUnparseableCode = codeKeys.contains {
                container.contains($0) && container.submissionInt(forKey: $0) == nil
            }
            messages = [
                container.decodeStringOrScalar(forKey: .errorMessage),
                container.decodeStringOrScalar(forKey: .legacyErrorMessage),
                container.decodeStringOrScalar(forKey: .error),
                container.decodeStringOrScalar(forKey: .message)
            ].compactMap { $0 }
            let threadID = container.submissionIdentifierString(forKey: .threadID)
            let postID = container.submissionIdentifierString(forKey: .postID)
            let alternatePostID = container.submissionIdentifierString(forKey: .alternatePostID)
            threadIDs = [threadID].compactMap { $0 }
            postIDs = [postID, alternatePostID].compactMap { $0 }
            hasUnparseableIdentifier = (
                container.contains(.threadID)
                    && validSubmissionThreadIdentifier(threadID) == false
            ) || [
                (CodingKeys.postID, postID),
                (CodingKeys.alternatePostID, alternatePostID)
            ].contains { key, value in
                container.contains(key) && validSubmissionPostIdentifier(value) == false
            }
        }
    }

    private let result: Int?
    private let hasResult: Bool
    private let codes: [Int]
    private let hasUnparseableCode: Bool
    private let messages: [String]
    private let threadIDs: [String]
    private let postIDs: [String]
    private let hasUnparseableIdentifier: Bool
    private let challengePayload: TiebaWebSubmissionChallengePayload
    private let nestedChallengePayload: TiebaWebSubmissionChallengePayload?

    private enum CodingKeys: String, CodingKey {
        case result
        case errorCode = "error_code"
        case legacyErrorCode = "err_code"
        case no
        case errno
        case errorNo = "error_no"
        case errorMessage = "error_msg"
        case legacyErrorMessage = "err_msg"
        case error
        case message = "msg"
        case threadID = "tid"
        case postID = "pid"
        case alternatePostID = "post_id"
        case data
    }

    init(from decoder: Swift.Decoder) throws {
        challengePayload = try TiebaWebSubmissionChallengePayload(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try? container.decodeIfPresent(DataDTO.self, forKey: .data)
        nestedChallengePayload = data?.challengePayload
        hasResult = container.contains(.result) || (data?.hasResult ?? false)
        let topResult = container.submissionInt(forKey: .result)
        if let topResult, let nestedResult = data?.result, topResult != nestedResult {
            result = nil
        } else {
            result = topResult ?? data?.result
        }
        let codeKeys: [CodingKeys] = [.errorCode, .legacyErrorCode, .no, .errno, .errorNo]
        codes = codeKeys.compactMap { container.submissionInt(forKey: $0) } + (data?.codes ?? [])
        hasUnparseableCode = codeKeys.contains {
            container.contains($0) && container.submissionInt(forKey: $0) == nil
        } || (data?.hasUnparseableCode ?? false)
        messages = [
            container.decodeStringOrScalar(forKey: .errorMessage),
            container.decodeStringOrScalar(forKey: .legacyErrorMessage),
            container.decodeStringOrScalar(forKey: .error),
            container.decodeStringOrScalar(forKey: .message)
        ].compactMap { $0 } + (data?.messages ?? [])
        let threadID = container.submissionIdentifierString(forKey: .threadID)
        let postID = container.submissionIdentifierString(forKey: .postID)
        let alternatePostID = container.submissionIdentifierString(forKey: .alternatePostID)
        threadIDs = [threadID].compactMap { $0 } + (data?.threadIDs ?? [])
        postIDs = [postID, alternatePostID].compactMap { $0 } + (data?.postIDs ?? [])
        hasUnparseableIdentifier = (
            container.contains(.threadID)
                && validSubmissionThreadIdentifier(threadID) == false
        ) || [
            (CodingKeys.postID, postID),
            (CodingKeys.alternatePostID, alternatePostID)
        ].contains { key, value in
            container.contains(key) && validSubmissionPostIdentifier(value) == false
        } || (data?.hasUnparseableIdentifier ?? false)
    }

    func submissionReceipt(for target: ContentSubmissionTarget) throws -> ContentSubmissionReceipt {
        guard let targetThreadID = target.threadID, targetThreadID > 0 else {
            throw ContentSubmissionError.outcomeUnknown
        }
        guard hasUnparseableCode == false,
              hasUnparseableIdentifier == false,
              (hasResult == false || result != nil) else {
            throw ContentSubmissionError.outcomeUnknown
        }
        let uniqueCodes = Set(codes)
        guard uniqueCodes.count <= 1 else {
            throw ContentSubmissionError.outcomeUnknown
        }
        let code = uniqueCodes.first
        let resultIsSuccess = result == 1
        let resultIsFailure = hasResult && resultIsSuccess == false
        let codeIsSuccess = code == 0
        let codeIsFailure = code.map { $0 != 0 } ?? false
        guard (resultIsSuccess && codeIsFailure) == false,
              (resultIsFailure && codeIsSuccess) == false else {
            throw ContentSubmissionError.outcomeUnknown
        }

        let normalizedMessages = normalizedSubmissionMessages(messages)
        let message = normalizedMessages.first ?? ""
        if let code, TiebaAPIError.isSessionExpired(code: code, message: message) {
            throw ContentSubmissionError.sessionExpired
        }
        if let challenge = TiebaWebSubmissionChallengePayload.challenge(
            from: [challengePayload] + [nestedChallengePayload].compactMap { $0 },
            messages: normalizedMessages
        ) {
            throw ContentSubmissionError.verificationRequired(challenge)
        }
        if let code, code != 0 {
            throw ContentSubmissionError.business(code: code, message: message)
        }
        if resultIsFailure {
            throw ContentSubmissionError.business(code: -1, message: message)
        }
        guard resultIsSuccess || codeIsSuccess else {
            throw ContentSubmissionError.outcomeUnknown
        }

        let returnedThreadIDs = try validatedPositiveInt64Values(threadIDs)
        guard returnedThreadIDs.isEmpty || returnedThreadIDs == [targetThreadID] else {
            throw ContentSubmissionError.outcomeUnknown
        }
        let returnedPostIDs = try validatedPositiveUInt64Values(postIDs)
        guard returnedPostIDs.count <= 1 else {
            throw ContentSubmissionError.outcomeUnknown
        }
        return ContentSubmissionReceipt(
            threadID: targetThreadID,
            postID: returnedPostIDs.first
        )
    }
}

enum TiebaContentSubmissionRequestFactory {
    static let postingLoginClientVersion = "22.5.1.0"

    private static let webUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func webThreadFields(
        account: Account,
        tbs: String,
        request: ContentSubmissionRequest,
        now: Date = Date()
    ) throws -> [String: String] {
        guard request.target.kind == .newThread else {
            throw ContentSubmissionError.unsupported(message: "回复不能使用网页发帖协议。")
        }
        guard request.images.isEmpty else {
            throw ContentSubmissionValidationError.imagesUnsupportedForNewThread
        }
        guard tbs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw TiebaMutationError.missingTBS
        }
        return [
            "ie": "utf-8",
            "fid": String(request.target.forumID),
            "kw": request.target.forumName,
            "tbs": tbs,
            "title": request.title,
            "content": request.body,
            "nick_name": account.displayName.isEmpty ? account.name : account.displayName,
            "bsk": String(Int64(now.timeIntervalSince1970 * 1_000))
        ]
    }

    static func webReplyFields(
        account: Account,
        tbs: String,
        request: ContentSubmissionRequest,
        uploadedImageInfo: String,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) throws -> [String: String] {
        guard request.target.kind != .newThread,
              let threadID = request.target.threadID,
              threadID > 0 else {
            throw ContentSubmissionValidationError.invalidThread
        }
        let resolvedTBS = tbs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard resolvedTBS.isEmpty == false else {
            throw TiebaMutationError.missingTBS
        }
        let imageInfo = uploadedImageInfo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard imageInfo.utf8.count <= ContentSubmissionPolicy.maximumImages * 16_384,
              containsASCIIControlLineBreak(imageInfo) == false else {
            throw ContentSubmissionValidationError.invalidImage
        }

        var fields = [
            "co": webReplyBody(request.body, target: request.target),
            "_t": String(timestamp),
            "tag": "11",
            "upload_img_info": imageInfo,
            "fid": String(request.target.forumID),
            "src": "1",
            "word": request.target.forumName,
            "tbs": resolvedTBS,
            "z": String(threadID),
            "lp": "6026",
            "nick_name": account.displayName.isEmpty ? account.name : account.displayName,
            "_BSK": String(timestamp)
        ]

        switch request.target.kind {
        case .threadReply:
            break
        case .postReply, .subpostReply:
            guard let parentPostID = request.target.parentPostID, parentPostID > 0 else {
                throw ContentSubmissionValidationError.invalidThread
            }
            fields["pid"] = String(parentPostID)
            fields["floor"] = String(max(1, request.target.parentFloor ?? 1))
            if request.target.kind == .subpostReply {
                guard let subpostID = request.target.subpostID, subpostID > 0 else {
                    throw ContentSubmissionValidationError.invalidThread
                }
                fields["lzl_id"] = String(subpostID)
            }
        case .newThread:
            throw ContentSubmissionError.unsupported(message: "新主题不能使用网页回帖协议。")
        }
        return fields
    }

    static func webThreadHeaders(
        account: Account,
        forumName: String
    ) throws -> [String: String] {
        var referer = URLComponents(url: TiebaEndpoint.base.appending(path: "/f"), resolvingAgainstBaseURL: false)
        referer?.queryItems = [.init(name: "kw", value: forumName)]
        return try webMutationHeaders(
            account: account,
            referer: referer?.url?.absoluteString ?? TiebaEndpoint.base.absoluteString
        )
    }

    static func webReplyHeaders(
        account: Account,
        threadID: Int64
    ) throws -> [String: String] {
        guard threadID > 0 else {
            throw ContentSubmissionValidationError.invalidThread
        }
        return try webMutationHeaders(
            account: account,
            referer: "https://tieba.baidu.com/p/\(threadID)?lp=5028&mo_device=1&is_jingpost=0&pn=1&"
        )
    }

    static func webUploadHeaders(
        account: Account,
        threadID: Int64
    ) throws -> [String: String] {
        try webReplyHeaders(account: account, threadID: threadID)
    }

    private static func webMutationHeaders(
        account: Account,
        referer: String?
    ) throws -> [String: String] {
        var headers = try webBaseHeaders(account: account)
        headers["Origin"] = TiebaEndpoint.base.absoluteString
        headers["X-Requested-With"] = "XMLHttpRequest"
        if let referer {
            headers["Referer"] = referer
        }
        return headers
    }

    private static func webBaseHeaders(account: Account) throws -> [String: String] {
        guard BaiduCredentialPolicy.isValid(account) else {
            throw ContentSubmissionError.sessionExpired
        }
        return [
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
            "User-Agent": webUserAgent,
            // The web publishing endpoints need only these validated credentials.
            // Keep BAIDUID out of write requests to minimize disclosure.
            "Cookie": "BDUSS=\(account.bduss); STOKEN=\(account.stoken)"
        ]
    }

    private static func subpostReplyBody(
        _ body: String,
        target: ContentSubmissionTarget
    ) -> String {
        guard let displayName = protocolReplyComponent(target.replyUserDisplayName) else {
            return body
        }
        // Drafts written before reply portraits were persisted still carry the
        // target UID and display name. Keep the three-component protocol shape;
        // reply_uid lets the server restore ownership when portrait is absent.
        let portrait = protocolReplyComponent(target.replyUserPortrait) ?? ""
        return "回复 #(reply, \(portrait), \(displayName)) :\(body)"
    }

    private static func webReplyBody(
        _ body: String,
        target: ContentSubmissionTarget
    ) -> String {
        guard target.kind == .subpostReply,
              let displayName = protocolReplyComponent(target.replyUserDisplayName) else {
            return body
        }
        return "回复 \(displayName) : \(body)"
    }

    private static func protocolReplyComponent(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false,
              normalized.utf8.count <= 512,
              normalized.contains(",") == false,
              normalized.contains(")") == false,
              containsASCIIControlLineBreak(normalized) == false else {
            return nil
        }
        return normalized
    }
}

private func containsASCIIControlLineBreak(_ value: String) -> Bool {
    value.unicodeScalars.contains { scalar in
        scalar.value == 0x0A || scalar.value == 0x0D
    }
}

extension TiebaAPI {
    func submitContent(
        account: Account,
        request: ContentSubmissionRequest
    ) async throws -> ContentSubmissionReceipt {
        try ContentSubmissionPolicy.validateForNetwork(request)
        try Task.checkCancellation()

        if request.target.kind == .newThread {
            return try await submitWebThread(account: account, request: request)
        }
        return try await submitWebReply(account: account, request: request)
    }

    func strictlyRefreshedPostingTBS(for account: Account) async throws -> String {
        guard BaiduCredentialPolicy.isValid(account) else {
            throw ContentSubmissionError.sessionExpired
        }
        let response: LoginResponseDTO
        do {
            response = try await client.postForm(
                .postingLogin,
                fields: [
                    "_client_version": TiebaContentSubmissionRequestFactory.postingLoginClientVersion,
                    "bdusstoken": account.bduss
                ],
                headers: [
                    "User-Agent": "tieba/\(TiebaContentSubmissionRequestFactory.postingLoginClientVersion) skin/default"
                ],
                signingSecret: "tiebaclient!!!",
                as: LoginResponseDTO.self
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch where Task.isCancelled {
            throw CancellationError()
        } catch {
            throw error
        }

        try Task.checkCancellation()
        let code = Int(response.errorCode ?? "0") ?? -1
        guard code == 0 else {
            do {
                try TiebaResponseValidator.validate(
                    code: code,
                    message: response.errorMessage ?? ""
                )
            } catch let error as TiebaAPIError {
                if case .sessionExpired = error {
                    throw ContentSubmissionError.sessionExpired
                }
                throw ContentSubmissionError.business(
                    code: code,
                    message: "发布登录校验失败（\(code)）：\(response.errorMessage ?? "")"
                )
            }
            throw ContentSubmissionError.business(
                code: code,
                message: response.errorMessage ?? ""
            )
        }
        let tbs = response.anti?.tbs.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard tbs.isEmpty == false else {
            throw TiebaMutationError.missingTBS
        }
        return tbs
    }

    private func submitWebThread(
        account: Account,
        request: ContentSubmissionRequest
    ) async throws -> ContentSubmissionReceipt {
        let refreshedTBS = try await strictlyRefreshedPostingTBS(for: account)
        try Task.checkCancellation()
        let fields = try TiebaContentSubmissionRequestFactory.webThreadFields(
            account: account,
            tbs: refreshedTBS,
            request: request
        )
        let headers = try TiebaContentSubmissionRequestFactory.webThreadHeaders(
            account: account,
            forumName: request.target.forumName
        )

        // Once this POST starts, losing or failing to decode the response does
        // not prove the server rejected the thread. Never retry or fall back to
        // the app Protobuf endpoint after this point.
        try Task.checkCancellation()
        let response: TiebaWebThreadSubmissionResponseDTO
        do {
            let data = try await client.postFormData(
                .webAddThread,
                fields: fields,
                headers: headers
            )
            try validateStrictSubmissionIntegerTypes(in: data, kind: .thread)
            response = try JSONDecoder().decode(
                TiebaWebThreadSubmissionResponseDTO.self,
                from: data
            )
        } catch {
            throw ContentSubmissionError.outcomeUnknown
        }
        return try response.submissionReceipt
    }

    private func submitWebReply(
        account: Account,
        request: ContentSubmissionRequest
    ) async throws -> ContentSubmissionReceipt {
        let threadID = request.target.threadID ?? 0
        let uploadedImageInfo = try await uploadWebImages(
            request.images,
            account: account,
            threadID: threadID
        )
        try Task.checkCancellation()

        let refreshedTBS: String
        do {
            refreshedTBS = try await strictlyRefreshedPostingTBS(for: account)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as TiebaAPIError {
            if case .sessionExpired = error {
                throw ContentSubmissionError.sessionExpired
            }
            throw error
        }
        try Task.checkCancellation()

        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let fields = try TiebaContentSubmissionRequestFactory.webReplyFields(
            account: account,
            tbs: refreshedTBS,
            request: request,
            uploadedImageInfo: uploadedImageInfo,
            timestamp: timestamp
        )
        let headers = try TiebaContentSubmissionRequestFactory.webReplyHeaders(
            account: account,
            threadID: threadID
        )

        // From this point the server may have accepted the reply even if the
        // connection or local task ends before a response is decoded.
        try Task.checkCancellation()
        let response: TiebaWebReplySubmissionResponseDTO
        do {
            let data = try await client.postFormData(
                .webAddPost(timestamp: timestamp),
                fields: fields,
                headers: headers
            )
            try validateStrictSubmissionIntegerTypes(in: data, kind: .reply)
            response = try JSONDecoder().decode(
                TiebaWebReplySubmissionResponseDTO.self,
                from: data
            )
        } catch {
            throw ContentSubmissionError.outcomeUnknown
        }
        return try response.submissionReceipt(for: request.target)
    }

    private func uploadWebImages(
        _ images: [ContentSubmissionImage],
        account: Account,
        threadID: Int64
    ) async throws -> String {
        guard images.isEmpty == false else { return "" }
        let headers = try TiebaContentSubmissionRequestFactory.webUploadHeaders(
            account: account,
            threadID: threadID
        )
        var imageInfo: [String] = []
        imageInfo.reserveCapacity(images.count)
        for (index, image) in images.enumerated() {
            try Task.checkCancellation()
            _ = try ContentSubmissionImageInspector.inspect(image.data)
            let nonce = "\(Int64(Date().timeIntervalSince1970 * 1_000))_\(index)"
            do {
                let response = try await client.postForm(
                    .webUploadPicture(nonce: nonce),
                    fields: ["pic": image.data.base64EncodedString()],
                    headers: headers,
                    as: TiebaWebUploadPictureResponseDTO.self
                )
                imageInfo.append(try response.validatedImageInfo())
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ContentSubmissionError {
                throw error
            } catch where Task.isCancelled {
                throw CancellationError()
            } catch {
                throw ContentSubmissionError.business(
                    code: -1,
                    message: "图片上传失败，请检查网络后重试。"
                )
            }
        }
        return imageInfo.joined(separator: "|")
    }
}

private enum SubmissionStatusResponseKind {
    case thread
    case reply

    var integerKeys: Set<String> {
        switch self {
        case .thread:
            return ["result", "error_code", "err_code", "tid", "pid"]
        case .reply:
            return [
                "result", "error_code", "err_code", "no", "errno", "error_no",
                "tid", "pid", "post_id"
            ]
        }
    }
}

/// JSONDecoder accepts integral floating-point tokens such as `1.0` when
/// decoding an Int. Mutation statuses and identifiers determine whether a
/// dispatched write is considered successful, so inspect their raw JSON types
/// before decoding and accept only integer JSON numbers or integer strings.
private func validateStrictSubmissionIntegerTypes(
    in data: Data,
    kind: SubmissionStatusResponseKind
) throws {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ContentSubmissionError.outcomeUnknown
    }
    var containers = [object]
    if let nestedValue = object["data"], nestedValue is NSNull == false {
        guard let nested = nestedValue as? [String: Any] else {
            throw ContentSubmissionError.outcomeUnknown
        }
        containers.append(nested)
    }
    for container in containers {
        for key in kind.integerKeys {
            guard let value = container[key] else { continue }
            guard isStrictSubmissionInteger(value) else {
                throw ContentSubmissionError.outcomeUnknown
            }
        }
    }
}

private func isStrictSubmissionInteger(_ value: Any) -> Bool {
    if let value = value as? String {
        return Int(value) != nil
    }
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else {
        return false
    }
    switch String(cString: number.objCType) {
    case "c", "s", "i", "l", "q", "C", "S", "I", "L", "Q":
        return true
    default:
        return false
    }
}

private extension String {
    var requiresSubmissionVerification: Bool {
        let value = lowercased()
        return value.contains("验证码")
            || value.contains("安全验证")
            || value.contains("captcha")
            || value.contains("verify")
    }
}

private func normalizedSubmissionMessages(_ values: [String]) -> [String] {
    values
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.isEmpty == false }
}

private func validatedPositiveInt64Values(_ values: [String]) throws -> Set<Int64> {
    var result = Set<Int64>()
    for value in values {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { continue }
        guard let parsed = positiveInt64(normalized) else {
            throw ContentSubmissionError.outcomeUnknown
        }
        result.insert(parsed)
    }
    return result
}

private func validatedPositiveUInt64Values(_ values: [String]) throws -> Set<UInt64> {
    var result = Set<UInt64>()
    for value in values {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { continue }
        guard let parsed = positiveUInt64(normalized) else {
            throw ContentSubmissionError.outcomeUnknown
        }
        result.insert(parsed)
    }
    return result
}

private func positiveInt64(_ value: String) -> Int64? {
    guard let number = Int64(value), number > 0 else { return nil }
    return number
}

private func positiveUInt64(_ value: String) -> UInt64? {
    guard let number = UInt64(value), number > 0 else { return nil }
    return number
}

private func validSubmissionThreadIdentifier(_ value: String?) -> Bool {
    guard let value else { return false }
    return positiveInt64(value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
}

private func validSubmissionPostIdentifier(_ value: String?) -> Bool {
    guard let value else { return false }
    return positiveUInt64(value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
}

private extension KeyedDecodingContainer {
    func submissionIdentifierString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(UInt64.self, forKey: key) {
            return String(value)
        }
        return nil
    }


    func submissionInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return Int(exactly: value)
        }
        if let value = try? decodeIfPresent(UInt64.self, forKey: key) {
            return Int(exactly: value)
        }
        return nil
    }
}
