import XCTest
@testable import TiebaPureMac

final class TiebaURLTests: XCTestCase {
    func testTiebaURLUpgradesHTTPImageURLToHTTPS() {
        let url = TiebaURL.make("http://tiebapic.baidu.com/forum/pic/item/a.jpg?tbpicau=test")

        XCTAssertEqual(url?.absoluteString, "https://tiebapic.baidu.com/forum/pic/item/a.jpg?tbpicau=test")
    }

    func testTiebaURLHandlesProtocolRelativeURL() {
        let url = TiebaURL.make("//tb.himg.baidu.com/sys/portrait/item/user")

        XCTAssertEqual(url?.absoluteString, "https://tb.himg.baidu.com/sys/portrait/item/user")
    }

    func testTiebaURLRejectsDangerousSchemesUserInfoAndLocalTargets() {
        XCTAssertNil(TiebaURL.webpage("javascript:alert(1)"))
        XCTAssertNil(TiebaURL.image("file:///tmp/private"))
        XCTAssertNil(TiebaURL.video("data:video/mp4;base64,AAAA"))
        XCTAssertNil(TiebaURL.webpage("https://user:pass@example.com/path"))
        XCTAssertNil(TiebaURL.webpage("https://localhost/path"))
        XCTAssertNil(TiebaURL.webpage("https://127.0.0.1/path"))
        XCTAssertNil(TiebaURL.webpage("https://10.0.0.8/path"))
        XCTAssertNil(TiebaURL.webpage("https://172.20.0.1/path"))
        XCTAssertNil(TiebaURL.webpage("https://192.168.1.1/path"))
        XCTAssertNil(TiebaURL.webpage("https://[::1]/path"))
        XCTAssertNil(TiebaURL.webpage("https://2130706433/path"))
        XCTAssertNil(TiebaURL.webpage("https://0x7f000001/path"))
        XCTAssertNil(TiebaURL.webpage("https://0177.0.0.1/path"))
        XCTAssertNil(TiebaURL.webpage("https://127.1/path"))
        XCTAssertNil(TiebaURL.webpage("https://localhost./path"))
        XCTAssertNil(TiebaURL.webpage("https://printer.local/path"))
        XCTAssertNil(TiebaURL.webpage("https://[0:0:0:0:0:0:0:1]/path"))
        XCTAssertNil(TiebaURL.webpage("https://[::ffff:127.0.0.1]/path"))
        XCTAssertNil(TiebaURL.webpage("https://[fc00::1]/path"))
        XCTAssertNil(TiebaURL.webpage("https://[fe80::1]/path"))
        XCTAssertNil(TiebaURL.webpage("http://user:pass@example.com/path"))
        XCTAssertNil(TiebaURL.webpage("http://localhost/path"))
        XCTAssertNil(TiebaURL.webpage("http://127.0.0.1/path"))
        XCTAssertNil(TiebaURL.webpage("http://192.168.1.1/path"))
    }

    func testTiebaURLAcceptsOnlyPublicHTTPSAndUpgradesHTTP() {
        XCTAssertEqual(TiebaURL.webpage("https://tieba.baidu.com/p/1")?.scheme, "https")
        XCTAssertEqual(TiebaURL.image("http://tiebapic.baidu.com/a.jpg")?.absoluteString, "https://tiebapic.baidu.com/a.jpg")
    }

    func testRedirectPolicyRevalidatesEveryDestination() {
        XCTAssertTrue(SecureRemoteRedirectScope.publicHTTPS.allows(URL(string: "https://tiebapic.baidu.com/a.jpg")))
        XCTAssertFalse(SecureRemoteRedirectScope.publicHTTPS.allows(URL(string: "http://tiebapic.baidu.com/a.jpg")))
        XCTAssertFalse(SecureRemoteRedirectScope.publicHTTPS.allows(URL(string: "https://2130706433/private")))
        XCTAssertFalse(SecureRemoteRedirectScope.publicHTTPS.allows(URL(string: "https://[::ffff:127.0.0.1]/private")))
        XCTAssertTrue(SecureRemoteRedirectScope.tiebaMediaHTTPS.allows(URL(
            string: "https://tiebapic.baidu.com/forum/pic/item/a.jpg"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.tiebaMediaHTTPS.allows(URL(
            string: "https://image.example/a.jpg"
        )))
        XCTAssertTrue(SecureRemoteRedirectScope.tiebaVideoHTTPS.allows(URL(
            string: "https://tb-video.bdstatic.com/tieba-smallvideo/demo.mp4"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.tiebaVideoHTTPS.allows(URL(
            string: "https://tb-video.bdstatic.com/tieba-smallvideo/demo.m3u8"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.tiebaVideoHTTPS.allows(URL(
            string: "https://video.example/demo.mp4"
        )))
    }

    func testAPIRedirectPolicyNeverForwardsSensitiveRequestsOutsideBaidu() {
        XCTAssertTrue(SecureRemoteRedirectScope.baiduHTTPS.allows(URL(string: "https://c.tieba.baidu.com/c/f/frs/page")))
        XCTAssertFalse(SecureRemoteRedirectScope.baiduHTTPS.allows(URL(string: "https://attacker.example/collect")))
        XCTAssertFalse(SecureRemoteRedirectScope.baiduHTTPS.allows(URL(string: "https://baidu.com.attacker.example/collect")))
    }

    func testMutationRedirectPolicyNeverReplaysPost() {
        let destination = URL(string: "https://tiebac.baidu.com/c/c/post/add?cmd=309731")
        XCTAssertFalse(SecureRemoteRedirectPolicy.allows(
            originalMethod: "POST",
            destination: destination,
            scope: .baiduHTTPS
        ))
        XCTAssertFalse(SecureRemoteRedirectPolicy.allows(
            originalMethod: "PATCH",
            destination: destination,
            scope: .baiduHTTPS
        ))
        XCTAssertTrue(SecureRemoteRedirectPolicy.allows(
            originalMethod: "GET",
            destination: destination,
            scope: .baiduHTTPS
        ))
    }

    func testEmoticonRedirectPolicyAllowsOnlyExactCDNAndValidArtworkPath() {
        XCTAssertTrue(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "https://tb2.bdstatic.com/tb/editor/images/client/image_emoticon125.png"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "https://tb1.bdstatic.com/tb/editor/images/client/image_emoticon125.png"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "https://bdstatic.com/tb/editor/images/client/image_emoticon125.png"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "https://tb2.bdstatic.com/tb/editor/images/client/not-an-emoticon.png"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "https://tb2.bdstatic.com/tb/editor/images/client/image_emoticon1000.png"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "https://tb2.bdstatic.com/tb/editor/images/client/nested/image_emoticon1.png"
        )))
        XCTAssertFalse(SecureRemoteRedirectScope.bdStaticHTTPS.allows(URL(
            string: "http://tb2.bdstatic.com/tb/editor/images/client/image_emoticon1.png"
        )))
    }


}
