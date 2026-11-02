// kleantalk-adserver: 카카오톡 광고 요청(serv.ds.kakao.com/sdk/banner)에 '빈 광고'를 돌려주는 작은 로컬 HTTPS 서버.
//
// hosts에서 serv.ds.kakao.com을 이 서버 전용 주소(127.84.11.1)로 돌리면 카카오톡의 광고 요청이 여기로 온다.
// 개발 도구들이 흔히 쓰는 127.0.0.1:443과 부딪치지 않도록, 시작할 때 루프백(lo0)에 전용 주소를 하나 더 붙여 거기서만 받는다.
// 응답 형식은 진짜 광고 서버와 같고, 광고 HTML만 카카오톡 창과 같은 색으로 칠한 빈 화면이다.
// 카카오톡은 이를 정상 광고로 받아들이므로, 광고를 못 받았을 때 나오는 카카오 홍보 배너도 뜨지 않는다.
// 진짜 광고 서버에는 연결하지 않는다.
//
// 인증서는 serv.ds.kakao.com 한 이름에만 쓰는 일반 인증서(인증 기관 아님)이고, 시스템에는 그 이름의 HTTPS에만
// 신뢰하도록 등록한다. 키는 root만 읽을 수 있다. 443 포트를 연 뒤에는 nobody 권한으로 내려간다.
//
// 사용법: kleantalk-adserver <cert.der> <key.der>   (RSA 키, PKCS#1 DER)

import Foundation
import Network
import Security
import os

let log = Logger(subsystem: "com.myungchul.kleantalk.adserver", category: "server")

// MARK: - 빈 광고 응답

/// 광고 대신 넣는 HTML. 원래 광고 HTML처럼 앱이 ReadyToListen을 보내면 AdLoaded(result: true)로 답해서
/// 카카오톡이 정상 광고로 받아들이게 한다. 화면은 카카오톡 메인 창과 같은 색으로 칠한다.
/// (다크 모드 실측: 사이드바 77px #2D2D2D, 구분선 1px #383838, 목록 #222222 / 라이트 모드는 아직 실측 전)
let blankAdHTML = """
<!DOCTYPE html>
<html lang="ko"><head><meta charset="utf-8">
<style>
html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#222222}
.side{position:fixed;left:0;top:0;bottom:0;width:77px;background:#2D2D2D;border-right:1px solid #383838}
@media (prefers-color-scheme: light){html,body{background:#FFFFFF}.side{background:#FFFFFF;border-right-color:#FFFFFF}}
</style>
</head><body><div class="side"></div>
<script>
if (window.chrome && window.chrome.webview) {
  window.chrome.webview.addEventListener('message', function (arg) {
    try {
      if ("ReadyToListen" === arg.data.event.name) {
        window.chrome.webview.postMessage({"event":{"name":"AdLoaded","data":{"result":true}}});
      }
    } catch (e) {}
  });
}
</script>
</body></html>
"""

/// 진짜 광고 서버 응답(JSON)과 같은 구조. 실험에서 카카오톡은 광고 HTML만 바꾸고 나머지 값(피드백 링크·광고 ID 등)은
/// 진짜처럼 채워 둔 응답만 정상 광고로 받아들였다. 비워 두면 실패로 보고 한 번 다시 요청한 뒤 광고 자리를 비워 둔다.
/// 그래서 값의 형식과 모양을 진짜 응답에 맞춘다. 피드백 링크는 이 서버를 가리켜 카카오로 아무것도 보내지 않는다.
func blankAdResponse() -> Data {
    func hex(_ n: Int) -> String { (0..<n).map { _ in String(format: "%x", Int.random(in: 0..<16)) }.joined() }
    let body: [String: Any] = [
        "status": "OK",
        "id": UUID().uuidString.lowercased(),
        "ads": [[
            "content": blankAdHTML,
            "mimeType": "text/html",
            "width": 400,
            "height": 100,
            "feedback": [
                "feedbacklinks": ["https://serv.ds.kakao.com/kleantalk/feedback?wa=\(hex(16))"],
                "optoutpage": "https://info.ds.kakao.com/optout.do",
                "reportpage": "https://t1.kakaocdn.net/kas/static/user-feedback.html",
            ],
            "dspId": "MOMENT",
            "bidId": hex(32),
            "etxId": "MOMENT:conversion_id:\(hex(24))",
            "cid": String(Int.random(in: 100000...999999)),
            "crid": String(Int.random(in: 10000000...99999999)),
            "adid": String(Int.random(in: 1000000...9999999)),
            "type": "banner",
        ]],
        "options": ["ext": ["refreshInterval": "60", "guaranteed": "N"], "allowFpc": "Y"],
    ]
    return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
}

// MARK: - HTTP (요청 한 번에 응답 한 번, 응답 뒤 연결을 닫는다)

func httpResponse(status: String, contentType: String?, body: Data) -> Data {
    var head = "HTTP/1.1 \(status)\r\n"
    if let contentType { head += "Content-Type: \(contentType)\r\n" }
    // X-KleanTalk: 앱이 '빈 광고 서버가 응답했는지' 확인하는 표시
    head += "Content-Length: \(body.count)\r\nCache-Control: no-cache, no-store, must-revalidate\r\nX-KleanTalk: 1\r\nConnection: close\r\n\r\n"
    return Data(head.utf8) + body
}

// MARK: - 새로고침에는 광고 없음

// 카카오톡은 창이 다시 앞으로 올 때 광고를 새로 받는데, 새 광고 화면이 그려지기 전 잠깐 흰 바탕이 비쳐 깜빡인다.
// 새로고침에 '광고 없음'(204)으로 답하면 카카오톡은 지금 보여 주는 빈 광고를 그대로 둔다.
// 다만 카카오톡이 막 켜졌을 때 광고 없음을 받으면 홍보 배너를 띄우므로, 카카오톡이 새로 실행된 뒤 첫 요청에는 빈 광고를 준다.
// 요청만으로는 둘을 구분할 수 없어(주소가 같다) 카카오톡 프로세스의 시작 시각으로 가린다.

/// 실행 중인 카카오톡 중 가장 늦게 시작한 것의 시작 시각(초). 찾지 못하면 nil.
func newestKakaoTalkStart() -> Double? {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return nil }
    let stride = MemoryLayout<kinfo_proc>.stride
    var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
    size = procs.count * stride
    guard sysctl(&mib, 3, &procs, &size, nil, 0) == 0 else { return nil }
    var newest: Double?
    for p in procs.prefix(size / stride) {
        let name = withUnsafeBytes(of: p.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        guard name == "KakaoTalk" else { continue }
        let t = p.kp_proc.p_starttime
        let start = Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000
        newest = max(newest ?? start, start)
    }
    return newest
}

var blankServedForStart: Double?
var blankServedAt = Date.distantPast

/// 빈 광고를 줄지(true) 광고 없음으로 답할지(false).
/// 카카오톡이 새로 켜졌거나, 시작 시각을 알 수 없거나, 마지막 빈 광고가 6시간을 넘었으면 빈 광고를 준다.
/// (6시간: 어떤 이유로든 홍보 배너가 떠 있다면 다음 새로고침 때 빈 광고로 돌아오게 하는 안전장치. 그때 한 번 깜빡일 수 있다)
func shouldServeBlank() -> Bool {
    guard let start = newestKakaoTalkStart() else { return true }
    if start != blankServedForStart || Date().timeIntervalSince(blankServedAt) > 6 * 3600 {
        blankServedForStart = start
        blankServedAt = Date()
        return true
    }
    return false
}

func handle(_ connection: NWConnection) {
    connection.start(queue: .main)
    var buffer = Data()
    func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, error in
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                let requestLine = head.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
                let parts = requestLine.split(separator: " ")
                let path = parts.count > 1 ? String(parts[1]) : ""
                let reply: Data
                if parts.first == "GET" && path.hasPrefix("/sdk/banner") && !path.contains("kleantalk=check") && !shouldServeBlank() {
                    reply = httpResponse(status: "204 No Content", contentType: nil, body: Data())
                    log.info("새로고침이라 광고 없음(204): 지금 빈 광고를 그대로 둔다")
                } else if parts.first == "GET" && path.hasPrefix("/sdk/banner") {
                    reply = httpResponse(status: "200 OK", contentType: "application/json", body: blankAdResponse())
                    log.info("빈 광고 응답")
                } else {
                    reply = httpResponse(status: "204 No Content", contentType: nil, body: Data())
                    log.info("그 밖의 요청에 204: \(path, privacy: .public)")
                }
                connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            // 머리가 너무 길거나 연결이 끝나면 닫는다
            if done || error != nil || buffer.count > 65536 { connection.cancel(); return }
            receive()
        }
    }
    receive()
}

// MARK: - 인증서·키

func loadIdentity(certPath: String, keyPath: String) -> SecIdentity? {
    guard let certData = FileManager.default.contents(atPath: certPath),
          let keyData = FileManager.default.contents(atPath: keyPath),
          let cert = SecCertificateCreateWithData(nil, certData as CFData) else { return nil }
    let attrs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, &error) else {
        log.error("키를 읽지 못함: \(String(describing: error?.takeRetainedValue()), privacy: .public)")
        return nil
    }
    // 키체인에 넣지 않고 메모리에서만 인증서와 키를 묶는다
    return SecIdentityCreate(nil, cert, key)
}

// MARK: - 시작

/// 서버 동작이 바뀔 때만 올린다. 앱은 설치된 서버와 앱 안의 서버의 이 번호를 비교해 '다시 설치'를 안내한다.
/// (실행 파일을 그대로 비교하면 Xcode만 바뀌어도 다시 설치하라고 나온다)
let serverVersion = 1
let args = CommandLine.arguments
if args.count == 2 && args[1] == "--version" { print(serverVersion); exit(0) }
guard args.count == 3, let identity = loadIdentity(certPath: args[1], keyPath: args[2]),
      let secIdentity = sec_identity_create(identity) else {
    FileHandle.standardError.write(Data("usage: kleantalk-adserver <cert.der> <key.der> (인증서·키를 읽지 못함)\n".utf8))
    exit(1)
}

/// 서버 전용 주소와 포트. 시험할 때만 바꿀 수 있다 (KLEANTALK_ADSERVER_HOST, KLEANTALK_ADSERVER_PORT).
let env = ProcessInfo.processInfo.environment
let listenHost = env["KLEANTALK_ADSERVER_HOST"] ?? "127.84.11.1"
let port = NWEndpoint.Port(env["KLEANTALK_ADSERVER_PORT"] ?? "443") ?? 443

/// 루프백에 전용 주소를 붙인다 (이미 있으면 그대로). root로 실행될 때만 필요하다.
func addLoopbackAlias(_ address: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
    p.arguments = ["lo0", "alias", address, "netmask", "255.255.255.255", "up"]
    try? p.run()
    p.waitUntilExit()
}
if getuid() == 0 && listenHost.hasPrefix("127.") && listenHost != "127.0.0.1" { addLoopbackAlias(listenHost) }

func makeListener(host: String) -> NWListener {
    let tls = NWProtocolTLS.Options()
    sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
    sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
    sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
    let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: port)
    params.allowLocalEndpointReuse = true
    guard let listener = try? NWListener(using: params) else {
        FileHandle.standardError.write(Data("\(host):\(port)을 열지 못함\n".utf8))
        exit(1)
    }
    listener.newConnectionHandler = handle
    return listener
}

let listeners = [makeListener(host: listenHost)]
var ready = 0
for listener in listeners {
    listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
            ready += 1
            // 두 포트를 모두 연 뒤에는 root 권한이 필요 없다. nobody로 내려간다.
            if ready == listeners.count && getuid() == 0 {
                guard setgid(UInt32(bitPattern: -2)) == 0, setuid(UInt32(bitPattern: -2)) == 0 else {
                    log.error("권한을 낮추지 못해 종료")
                    exit(1)
                }
            }
            if ready == listeners.count { log.notice("준비됨: 포트 \(port.rawValue) (uid \(getuid()))") }
        case .failed(let error):
            log.error("리스너 실패: \(error.localizedDescription, privacy: .public)")
            exit(1)   // launchd가 다시 띄운다
        default:
            break
        }
    }
    listener.start(queue: .main)
}
dispatchMain()
