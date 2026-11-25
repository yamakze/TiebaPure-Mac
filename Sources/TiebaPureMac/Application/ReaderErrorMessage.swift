import Foundation

enum ReaderErrorMessage {
    static func message(for error: Error, fallback: String = "无法加载内容。") -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "请求超时。"
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                return "网络不可用。"
            case .cancelled:
                return "请求已取消。"
            default:
                return "网络请求失败。"
            }
        }

        if error is DecodingError {
            return "无法读取贴吧返回的数据。"
        }

        if let authError = error as? AuthSessionError {
            switch authError {
            case .missingRequiredCookies:
                return "登录凭证不完整。"
            case .untrustedCookie:
                return "无法验证登录凭证。"
            case .disallowedNavigation:
                return "已阻止不安全的登录页面跳转。"
            }
        }

        if let loginError = error as? LoginValidationError {
            return loginError.description
        }

        if let sessionError = error as? ReaderSessionError {
            return sessionError.localizedDescription
        }

        if let socialError = error as? SocialMutationCoordinatorError {
            return socialError.localizedDescription
        }

        if let writeError = error as? AccountWriteError {
            return writeError.localizedDescription
        }

        if let submissionError = error as? ContentSubmissionCoordinatorError {
            return submissionError.localizedDescription
        }

        if let profileError = error as? UserProfileAPIError {
            return profileError.description
        }

        if let resolutionError = error as? UserNameResolutionError {
            return resolutionError.description
        }

        if let mutationError = error as? TiebaMutationError {
            return mutationError.description
        }

        if case .invalidCredentialCleanupFailed = error as? AccountStoreError {
            return "无法清除本机无效的登录凭据。"
        }

        if error is KeychainError || error is AccountStoreError {
            return "无法访问本机的账号数据。"
        }

        if error is TiebaRequestValidationError {
            return "请求参数无效，无法继续加载。"
        }

        if case let TiebaHTTPError.badStatus(code) = error {
            return code == 401 || code == 403
                ? "贴吧拒绝了当前请求。"
                : "贴吧服务器暂时不可用。"
        }

        if case .responseTooLarge = error as? TiebaHTTPError {
            return "响应内容超过安全大小限制。"
        }

        if case .sessionExpired = error as? TiebaAPIError {
            return "登录已失效。"
        }

        if case .missingMainPost = error as? TiebaAPIError {
            return "无法加载帖子主楼。"
        }

        if let apiError = error as? TiebaAPIError,
           case let .response(_, message) = apiError,
           message.isEmpty == false {
            return message
        }

        return fallback
    }
}
