import Foundation

enum ReaderErrorMessage {
    static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "请求超时，请稍后重试。"
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                return "网络不可用，请检查网络连接。"
            case .cancelled:
                return "请求已取消。"
            default:
                return "网络请求失败，请稍后重试。"
            }
        }

        if error is DecodingError {
            return "数据解析失败，请刷新后重试。"
        }

        if let authError = error as? AuthSessionError {
            switch authError {
            case .missingRequiredCookies:
                return "登录凭证不完整，请返回登录页重试。"
            case .untrustedCookie:
                return "登录凭证未通过安全校验，请重新登录。"
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
            return "本机账号数据处理失败，请重新登录或稍后重试。"
        }

        if error is TiebaRequestValidationError {
            return "请求参数无效，无法继续加载。"
        }

        if case let TiebaHTTPError.badStatus(code) = error {
            return code == 401 || code == 403
                ? "当前请求未获授权，请重新登录或稍后重试。"
                : "服务器暂时不可用（\(code)），请稍后重试。"
        }

        if case .responseTooLarge = error as? TiebaHTTPError {
            return "响应内容超过安全大小限制。"
        }

        if case .sessionExpired = error as? TiebaAPIError {
            return "登录已失效，请重新登录。"
        }

        if case .missingMainPost = error as? TiebaAPIError {
            return "未能加载帖子主楼，请刷新后重试。"
        }

        if let apiError = error as? TiebaAPIError,
           case let .response(_, message) = apiError,
           message.isEmpty == false {
            return message
        }

        return "加载失败，请稍后重试。"
    }
}
