import Foundation
import SwiftProtobuf

enum TiebaClientVersion: String {
    case v12 = "12.52.1.0"
    case v22 = "22.5.1.0"
    case mini = "7.2.0.0"
}

struct TiebaRequestBuilder {
    private static let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    static let boundary = "--------7da3d81520810*"

    var screenScale: Double
    var screenWidth: Int
    var screenHeight: Int
    var clientID: String

    static func live(screenScale: Double = 1, screenWidth: Int = 1440, screenHeight: Int = 900) -> TiebaRequestBuilder {
        TiebaRequestBuilder(
            screenScale: screenScale,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            clientID: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        )
    }

    func common(account: Account?) -> Tieba_CommonRequest {
        var request = Tieba_CommonRequest()
        request.bduss = account?.bduss ?? ""
        request.clientID = clientID
        request.clientType = 2
        request.clientVersion = TiebaClientVersion.v12.rawValue
        request.osVersion = Self.osVersion
        request.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        request.brand = "Apple"
        request.cuid = clientID
        request.cuidGalaxy2 = clientID
        request.cuidGid = ""
        request.from = "1020031h"
        request.isTeenager = 0
        request.model = "Mac"
        request.netType = 1
        request.pversion = "1.0.3"
        request.personalizedRecSwitch = 1
        request.qType = 0
        request.scrDip = screenScale
        request.scrW = Int32(screenWidth)
        request.scrH = Int32(screenHeight)
        request.stoken = account?.stoken ?? ""
        request.userAgent = "tieba/\(TiebaClientVersion.v12.rawValue)"
        return request
    }

    func miniCommonFields(timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> [String: String] {
        let cuid = miniCUID
        return [
            "_client_id": clientID,
            "_client_type": "2",
            "_client_version": TiebaClientVersion.mini.rawValue,
            "_os_version": Self.osVersion,
            "_phone_imei": "000000000000000",
            "cuid": cuid,
            "cuid_galaxy2": cuid,
            "from": "1021636m",
            "model": "Mac",
            "net_type": "1",
            "subapp_type": "mini",
            "timestamp": "\(timestamp)"
        ]
    }

    func officialCommonFields(
        bduss: String? = nil,
        baiduID: String? = nil,
        clientVersion: String = "11.10.8.6",
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) -> [String: String] {
        let cuid = miniCUID
        var fields = [
            "_client_id": clientID,
            "_client_type": "2",
            "_client_version": clientVersion,
            "_os_version": Self.osVersion,
            "_phone_imei": "000000000000000",
            "active_timestamp": "\(timestamp)",
            "brand": "Apple",
            "cmode": "1",
            "cuid": cuid,
            "cuid_galaxy2": cuid,
            "cuid_gid": "",
            "from": "tieba",
            "is_teenager": "0",
            "mac": "02:00:00:00:00:00",
            "model": "Mac",
            "net_type": "1",
            "start_scheme": "",
            "start_type": "1",
            "timestamp": "\(timestamp)"
        ]
        if let bduss, bduss.isEmpty == false {
            fields["BDUSS"] = bduss
        }
        if let baiduID, baiduID.isEmpty == false {
            fields["baiduid"] = baiduID
        }
        return fields
    }

    func officialHeaders(
        baiduID: String? = nil,
        clientVersion: String = "11.10.8.6",
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) -> [String: String] {
        let cuid = miniCUID
        var cookieParts = [
            "CUID=\(cuid)",
            "ka=open",
            "TBBRAND=Apple"
        ]
        if let baiduID, baiduID.isEmpty == false {
            cookieParts.append("BAIDUID=\(baiduID)")
        }
        return [
            "Charset": "UTF-8",
            "Cookie": cookieParts.joined(separator: "; "),
            "Pragma": "no-cache",
            "User-Agent": "bdtb for Android \(clientVersion)",
            "client_logid": "\(timestamp)",
            "client_type": "2",
            "cuid": cuid,
            "cuid_galaxy2": cuid,
            "cuid_gid": ""
        ]
    }

    var miniCUID: String {
        "\(clientID.uppercased())|000000000000000"
    }

    func multipart<Message: SwiftProtobuf.Message>(
        protobuf: Message,
        account: Account?,
        includeSToken: Bool,
        fileContentType: String? = "application/octet-stream"
    ) throws -> (body: Data, contentType: String) {
        let form = MultipartFormData(boundary: Self.boundary)
        if includeSToken, let stoken = account?.stoken {
            form.addField(name: "stoken", value: stoken)
        }
        form.addFile(
            name: "data",
            filename: "file",
            contentType: fileContentType,
            data: try protobuf.serializedData()
        )
        return (form.finalize(), "multipart/form-data; boundary=\(Self.boundary)")
    }
}
