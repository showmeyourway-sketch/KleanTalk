import AppKit
import Sparkle
import SwiftUI

// KleanTalk: 맥 카카오톡의 광고 자리를 카카오톡과 같은 색의 빈 공간으로 바꾼다.
// 설치하면 (1) /etc/hosts로 카카오 광고 주소를 막고 (2) 광고 요청에 빈 광고를 돌려주는 작은 서버(AdServer/)를
// 이 맥에 띄운다. 켜고 끄는 설정은 없고, 설치하면 작동하고 제거하면 모두 원래대로 돌아간다.
// 로그인 시 --background 인자로 창 없이 실행돼, 설정이 풀렸을 때(macOS 업데이트로 hosts 초기화 등)만 창을 띄운다.
// 새 버전은 Sparkle로 받는다(하루 한 번 확인, EdDSA 서명 확인). 업데이트에 새 서버가 들어 있으면 '다시 설치'로 마무리한다.

let isBackgroundLaunch = CommandLine.arguments.contains("--background")

// MARK: - 언어

enum Language: String { case ko, en }

struct Strings {
    let `continue`: String
    let installTitle: String, installItems: [String], adminNote: String, cancel: String, install: String
    let working: String, notWorking: String, checking: String, notWorkingNote: String, reinstall: String, restarted: String
    let language: String, uninstallButton: String, uninstallTitle: String, uninstallBody: String, uninstall: String
    let adminPrompt: String, missingFiles: String, trustCanceled: String, trustFailed: String
    let checkUpdates: String, serverOutdated: String, version: String, upToDate: String, updateTo: String
    let reportBug: String, bugTitle: String, bugBody: String, copyInfo: String, copiedInfo: String, infoTitle: String
    let quit: String, edit: String, cut: String, copy: String, paste: String, selectAll: String, window: String, close: String

    static let ko = Strings(
        continue: "계속",
        installTitle: "KleanTalk 설치",
        installItems: ["카카오톡 광고 주소 차단", "빈 광고를 돌려주는 작은 서버 설치", "serv.ds.kakao.com 전용 인증서 등록"],
        adminNote: "관리자 암호를 두 번 입력합니다", cancel: "취소", install: "설치",
        working: "작동 중", notWorking: "작동하지 않음", checking: "확인 중…",
        notWorkingNote: "설정이 풀렸을 수 있습니다. 다시 설치해 주세요.", reinstall: "다시 설치",
        restarted: "카카오톡을 다시 시작했습니다.",
        language: "언어", uninstallButton: "제거…", uninstallTitle: "KleanTalk을 제거할까요?",
        uninstallBody: "광고 차단과 빈 광고 서버를 모두 지웁니다.", uninstall: "제거",
        adminPrompt: "KleanTalk을 설치하거나 제거하려면 암호가 필요합니다.",
        missingFiles: "앱 안에서 설치 파일을 찾지 못했습니다.",
        trustCanceled: "인증서 등록을 취소했습니다. 다시 설치를 누르세요.",
        trustFailed: "인증서를 등록하지 못했습니다. 다시 설치를 누르세요.",
        checkUpdates: "업데이트 확인…", serverOutdated: "업데이트를 마치려면 다시 설치를 누르세요.",
        version: "버전", upToDate: "최신 버전", updateTo: "%@로 업데이트",
        reportBug: "버그 신고", bugTitle: "[버그] ",
        bugBody: "### 무슨 일이 있었나요?\n\n\n### 어떻게 하면 다시 생기나요?\n1. \n\n### 환경 (자동으로 채움)\n",
        copyInfo: "정보 복사", copiedInfo: "복사했습니다", infoTitle: "KleanTalk 진단 정보",
        quit: "KleanTalk 종료", edit: "편집", cut: "잘라내기", copy: "복사", paste: "붙여넣기", selectAll: "모두 선택",
        window: "윈도우", close: "닫기")

    static let en = Strings(
        continue: "Continue",
        installTitle: "Install KleanTalk",
        installItems: ["Block KakaoTalk ad addresses", "Install a small server that returns blank ads",
                       "Register a certificate for serv.ds.kakao.com only"],
        adminNote: "You’ll enter your password twice", cancel: "Cancel", install: "Install",
        working: "Working", notWorking: "Not working", checking: "Checking…",
        notWorkingNote: "A setting may have been reset. Reinstall to fix it.", reinstall: "Reinstall",
        restarted: "KakaoTalk was restarted.",
        language: "Language", uninstallButton: "Uninstall…", uninstallTitle: "Uninstall KleanTalk?",
        uninstallBody: "Removes ad blocking and the blank ad server.", uninstall: "Uninstall",
        adminPrompt: "KleanTalk needs your password to install or uninstall.",
        missingFiles: "Couldn’t find the installer files inside the app.",
        trustCanceled: "Certificate registration was canceled. Click Reinstall.",
        trustFailed: "Couldn’t register the certificate. Click Reinstall.",
        checkUpdates: "Check for Updates…", serverOutdated: "Click Reinstall to finish the update.",
        version: "Version", upToDate: "Up to date", updateTo: "Update to %@",
        reportBug: "Report a Bug", bugTitle: "[Bug] ",
        bugBody: "### What happened?\n\n\n### How can we reproduce it?\n1. \n\n### Environment (filled in automatically)\n",
        copyInfo: "Copy Info", copiedInfo: "Copied", infoTitle: "KleanTalk diagnostic info",
        quit: "Quit KleanTalk", edit: "Edit", cut: "Cut", copy: "Copy", paste: "Paste", selectAll: "Select All",
        window: "Window", close: "Close")
}

// MARK: - 빈 광고 서버 설치·제거·확인

enum AdServer {
    enum State { case checking, working, notWorking }
    enum Result { case ok, canceled, failed(String) }

    static let host = "serv.ds.kakao.com"
    static var installed: Bool {
        FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/com.myungchul.kleantalk.adserver.plist")
    }

    /// 카카오톡과 같은 경로로 광고를 요청해 본다. hosts·인증서 신뢰·서버가 모두 맞아야 KleanTalk의 빈 광고가 돌아온다.
    static func isWorking() async -> Bool { await probe().ok }

    /// isWorking과 같은 확인. 실패하면 어디서 막혔는지(오류 코드 등)도 돌려준다.
    static func probe() async -> (ok: Bool, detail: String) {
        guard let url = URL(string: "https://\(host)/sdk/banner?kleantalk=check") else { return (false, "bad url") }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        do {
            let (_, response) = try await URLSession(configuration: config).data(from: url)
            guard let http = response as? HTTPURLResponse else { return (false, "no http response") }
            let marked = http.value(forHTTPHeaderField: "X-KleanTalk") == "1"   // 빈 광고 서버가 붙이는 표시
            return (http.statusCode == 200 && marked, "HTTP \(http.statusCode)\(marked ? "" : ", not KleanTalk server")")
        } catch let error as NSError {
            let underlying = (error.userInfo[NSUnderlyingErrorKey] as? NSError).map { " / \($0.domain) \($0.code)" } ?? ""
            return (false, "\(error.domain) \(error.code)\(underlying): \(error.localizedDescription)")
        }
    }

    /// 작동하지 않을 때 어느 단계에서 막혔는지 모은다 (버그 신고 본문에 넣는다).
    /// hosts → 서버 실행 → 인증서 신뢰 → 실제 요청 순서로 보면 원인을 좁힐 수 있다.
    static func diagnose() async -> [String] {
        var addresses: [String] = []
        var info: UnsafeMutablePointer<addrinfo>?
        if getaddrinfo(host, "443", nil, &info) == 0 {
            var p = info
            while let ai = p {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ai.pointee.ai_addr, ai.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let a = String(cString: buf)
                    if !addresses.contains(a) { addresses.append(a) }
                }
                p = ai.pointee.ai_next
            }
            freeaddrinfo(info)
        }
        let probe = await probe()
        return [
            "hosts: \(addresses.isEmpty ? "unresolved" : addresses.joined(separator: ", "))",
            "server: \(FileManager.default.fileExists(atPath: installedBinaryPath) ? "installed" : "missing"), \(run("/usr/bin/pgrep", "-f", installedBinaryPath).isEmpty ? "not running" : "running")",
            "trust: \(isTrusted() ? "yes" : "no")",
            "check: \(probe.detail)",
        ] + serverLog().map { "log: \($0)" }
    }

    /// 빈 광고 서버의 최근 기록 몇 줄 (시작 실패·인증서 오류가 여기 남는다)
    private static func serverLog() -> [String] {
        let out = run("/usr/bin/log", "show", "--last", "30m", "--style", "compact",
                      "--predicate", "subsystem == \"com.myungchul.kleantalk.adserver\"")
        return out.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("Timestamp") }.suffix(8)
    }

    private static func run(_ path: String, _ args: String...) -> String {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let certPath = "/Library/Application Support/KleanTalk/AdServer/cert.der"
    static let installedBinaryPath = "/Library/Application Support/KleanTalk/AdServer/kleantalk-adserver"

    /// 앱이 업데이트되면서 앱 안의 서버가 설치된 서버보다 새 버전이 됐는지. (설치된 서버는 관리자 폴더에 있어 '다시 설치'로 바꾼다)
    /// 실행 파일을 그대로 비교하지 않고 서버가 알려 주는 버전 번호를 비교한다. 같은 코드도 Xcode가 바뀌면 다르게 빌드되기 때문이다.
    static var serverOutdated: Bool {
        guard installed, FileManager.default.fileExists(atPath: installedBinaryPath),
              let bundled = Bundle.main.path(forResource: "kleantalk-adserver", ofType: nil) else { return false }
        return serverVersion(at: installedBinaryPath) < serverVersion(at: bundled)
    }

    /// --version을 모르는 예전 서버(1.10까지)는 1
    private static func serverVersion(at path: String) -> Int { Int(run(path, "--version")) ?? 1 }

    static func certificateData() -> Data? { FileManager.default.contents(atPath: certPath) }

    private static func certificate(_ data: Data? = certificateData()) -> SecCertificate? {
        guard let data else { return nil }
        return SecCertificateCreateWithData(nil, data as CFData)
    }

    static func isTrusted(_ data: Data? = certificateData()) -> Bool {
        guard let cert = certificate(data) else { return false }
        var existing: CFArray?
        return SecTrustSettingsCopyTrustSettings(cert, .user, &existing) == errSecSuccess
    }

    /// 서버 인증서를 'serv.ds.kakao.com의 HTTPS 서버 인증'에만 믿도록 이 사용자의 신뢰 설정에 등록한다.
    /// 관리자 권한 스크립트 안에서는 macOS가 확인 창을 띄울 수 없어 거부하므로, 앱이 사용자 권한으로 한다(확인 창이 뜬다).
    static func trustCertificate() -> OSStatus {
        guard let cert = certificate() else { return errSecItemNotFound }
        let setting: [String: Any] = [
            kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(true, host as CFString),
            kSecTrustSettingsPolicyString as String: host,
            kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue,
        ]
        return SecTrustSettingsSetTrustSettings(cert, .user, [setting] as CFArray)
    }

    /// 등록해 둔 신뢰 설정을 지운다. 설정이 없으면 아무것도 하지 않는다(확인 창도 뜨지 않는다).
    static func untrustCertificate(_ data: Data? = certificateData()) {
        guard isTrusted(data), let cert = certificate(data) else { return }
        SecTrustSettingsRemoveTrustSettings(cert, .user)
    }

    /// 카카오톡이 켜져 있으면 끄고 다시 연다 (새 광고 설정을 바로 받게)
    static func restartKakaoTalk() async -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.kakao.KakaoTalkMac").first,
              let url = app.bundleURL else { return false }
        app.terminate()
        for _ in 0..<50 where !app.isTerminated { try? await Task.sleep(nanoseconds: 200_000_000) }
        guard app.isTerminated else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        return (try? await NSWorkspace.shared.openApplication(at: url, configuration: config)) != nil
    }

    /// 앱 안에 든 설치·제거 스크립트를 관리자 권한으로 실행한다. (암호 창은 macOS가 띄운다)
    static func run(install: Bool, t: Strings) -> Result {
        func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        guard let script = Bundle.main.path(forResource: install ? "install-adserver" : "uninstall-adserver", ofType: "sh"),
              let binary = Bundle.main.path(forResource: "kleantalk-adserver", ofType: nil) else {
            return .failed(t.missingFiles)
        }
        let cmd = "/bin/zsh \(quoted(script)) \(quoted(binary)) 2>&1"
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let source = "do shell script \"\(escape(cmd))\" with administrator privileges with prompt \"\(escape(t.adminPrompt))\""
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        guard let err else { return .ok }
        if (err[NSAppleScript.errorNumber] as? Int) == -128 { return .canceled }
        return .failed(err[NSAppleScript.errorMessage] as? String ?? "")
    }
}

// MARK: - 로그인 시 자동 실행 (설정이 풀렸는지 확인하는 용도)

enum LoginItem {
    static let label = "com.myungchul.kleantalk"

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func set(_ on: Bool) {
        guard on else { try? FileManager.default.removeItem(at: url); return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [Bundle.main.executablePath ?? "", "--background"],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: url)
        }
    }
}

// MARK: - 상태

@MainActor
final class AppModel: ObservableObject {
    enum Screen { case language, install, status, uninstallConfirm }

    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language"); onLanguageChange?() }
    }
    @Published var screen: Screen
    @Published var state: AdServer.State = .checking
    @Published var busy = false
    @Published var error: String?
    @Published var restartedKakao = false
    @Published var serverOutdated = false
    /// '정보 복사'를 누른 직후 잠깐 '복사했습니다'로 보여 준다
    @Published var copiedInfo = false
    /// Sparkle로 확인한 새 버전. 확인 전이거나 확인하지 못하면 unknown.
    enum Update: Equatable { case unknown, upToDate, available(String) }
    @Published var update = Update.unknown
    var onLanguageChange: (() -> Void)?
    var onInstallUpdate: (() -> Void)?

    var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }

    var t: Strings { language == .ko ? .ko : .en }

    init() {
        language = Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .ko
        // 설치돼 있으면 상태 화면, 아니면 언어부터 묻는다
        screen = AdServer.installed ? .status : .language
        // 개발용: 화면 확인·스크린샷을 위해 시작 화면과 언어를 고른다 (KLEANTALK_PREVIEW=language|install|status|uninstall, KLEANTALK_LANG=ko|en)
        let env = ProcessInfo.processInfo.environment
        if let lang = env["KLEANTALK_LANG"].flatMap(Language.init(rawValue:)) { language = lang }
        switch env["KLEANTALK_PREVIEW"] {
        case "language": screen = .language
        case "install": screen = .install
        case "status": screen = .status; preview = true
        case "uninstall": screen = .uninstallConfirm
        default: break
        }
        // 개발용: 상태 화면의 업데이트 줄과 다시 설치 줄 (KLEANTALK_PREVIEW_UPDATE=1.7|latest, KLEANTALK_PREVIEW_OUTDATED=1,
        // 작동하지 않음 화면은 KLEANTALK_PREVIEW_BROKEN=1)
        switch env["KLEANTALK_PREVIEW_UPDATE"] {
        case nil: break
        case "latest": update = .upToDate
        case let v?: update = .available(v)
        }
        previewOutdated = env["KLEANTALK_PREVIEW_OUTDATED"] != nil
        previewBroken = env["KLEANTALK_PREVIEW_BROKEN"] != nil
    }

    /// 개발용 미리 보기 중에는 실제 상태를 확인하지 않고 '작동 중'으로 보여 준다
    private var preview = false
    private var previewOutdated = false
    private var previewBroken = false

    func check() async {
        if preview { state = previewBroken ? .notWorking : .working; serverOutdated = previewOutdated; return }
        guard AdServer.installed else { state = .notWorking; return }
        serverOutdated = AdServer.serverOutdated
        if state != .working { state = .checking }
        state = await AdServer.isWorking() ? .working : .notWorking
    }

    func install() {
        busy = true; error = nil
        let oldCert = AdServer.certificateData()
        switch AdServer.run(install: true, t: t) {
        case .ok:
            LoginItem.set(true)
            screen = .status
            // 인증서가 새로 만들어졌을 때만 신뢰를 (다시) 등록한다. 그대로면 확인 창 없이 넘어간다.
            let newCert = AdServer.certificateData()
            if let oldCert, oldCert != newCert { AdServer.untrustCertificate(oldCert) }
            let status = AdServer.isTrusted(newCert) ? errSecSuccess : AdServer.trustCertificate()
            if status == errSecSuccess {
                Task {
                    restartedKakao = await AdServer.restartKakaoTalk()
                    await check()
                }
            } else {
                error = status == errAuthorizationCanceled ? t.trustCanceled : "\(t.trustFailed) (\(status))"
                Task { await check() }
            }
        case .canceled:
            break
        case .failed(let message):
            error = message.isEmpty ? nil : message
        }
        busy = false
    }

    /// GitHub에 새 이슈 쓰기 화면을 연다. 버전·macOS·칩·카카오톡 버전·상태를 본문에 미리 채운다.
    /// 설치했는데 작동하지 않으면 어느 단계에서 막혔는지도 넣는다.
    func reportBug() {
        Task {
            let checks = AdServer.installed && state != .working ? await AdServer.diagnose() : []
            var c = URLComponents(string: "https://github.com/showmeyourway-sketch/KleanTalk/issues/new")!
            let body = t.bugBody + environment(checks: checks).joined(separator: "\n")
            c.queryItems = [.init(name: "labels", value: "bug"), .init(name: "title", value: t.bugTitle), .init(name: "body", value: body)]
            if let url = c.url { NSWorkspace.shared.open(url) }
        }
    }

    /// 버그 신고와 같은 내용(환경 + 단계별 확인 결과)을 클립보드에 복사한다.
    /// GitHub이나 터미널을 몰라도 카페 댓글·카카오톡·이메일에 붙여 넣어 보낼 수 있게.
    func copyInfo() {
        Task {
            let checks = AdServer.installed ? await AdServer.diagnose() : []
            let text = ([t.infoTitle] + environment(checks: checks)).joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedInfo = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copiedInfo = false
        }
    }

    private func environment(checks: [String]) -> [String] {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
        let kakao = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.kakao.KakaoTalkMac")
            .flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? "-"
        #if arch(arm64)
        let chip = "Apple Silicon"
        #else
        let chip = "Intel"
        #endif
        let state = switch self.state { case .working: "working"; case .notWorking: "not working"; case .checking: "checking" }
        return [
            "- KleanTalk: \(version)",
            "- macOS: \(ProcessInfo.processInfo.operatingSystemVersionString) · \(chip)",
            "- KakaoTalk: \(kakao)",
            "- 상태 / State: \(state)\(serverOutdated ? ", server outdated" : "")\(error.map { " · \($0)" } ?? "")",
        ] + checks.map { "  - \($0)" }
    }

    func uninstall() {
        busy = true; error = nil
        AdServer.untrustCertificate()
        switch AdServer.run(install: false, t: t) {
        case .ok:
            LoginItem.set(false)
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
            // 앱도 휴지통으로 옮기고 끝낸다
            NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        case .canceled:
            screen = .status
        case .failed(let message):
            error = message.isEmpty ? nil : message
            screen = .status
        }
        busy = false
    }
}

// MARK: - 화면 (모든 창은 같은 크기)

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.screen {
            case .language: LanguageView(model: model)
            case .install: InstallView(model: model)
            case .status: StatusView(model: model)
            case .uninstallConfirm: UninstallView(model: model)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 16)
        // 상태 화면은 줄 수에 따라 높이가 바뀌고(창도 따라 바뀐다), 나머지 화면은 같은 크기
        .frame(width: 440, height: model.screen == .status ? nil : 162, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: model.screen == .status)
    }
}

struct Header<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
            content
        }
    }
}

struct LanguageView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 다른 화면처럼 로고는 왼쪽에, 언어는 상태 화면과 같은 묶음 줄로
            Header { Text("KleanTalk").font(.title3.bold()) }
            GroupRow {
                Text("언어 · Language")
                Spacer()
                Picker("", selection: $model.language) {
                    Text("한국어").tag(Language.ko)
                    Text("English").tag(Language.en)
                }
                .labelsHidden()
                .fixedSize()
            }
            .groupBox()
            .padding(.top, 14)
            Spacer()
            HStack {
                Spacer()
                Button(model.t.continue) { model.screen = .install }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct InstallView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let t = model.t
        VStack(alignment: .leading, spacing: 0) {
            Header { Text(t.installTitle).font(.headline) }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(t.installItems, id: \.self) { Text("•  " + $0) }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
            Spacer()
            HStack(spacing: 8) {
                Text(model.error ?? t.adminNote)
                    .font(.caption)
                    .foregroundStyle(model.error == nil ? Color.secondary : Color.red)
                    .lineLimit(2)
                Spacer()
                Button(t.cancel) { NSApp.terminate(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(t.install) { model.install() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(model.busy)
        }
    }
}

struct StatusView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let t = model.t
        let (label, symbol, color): (String, String, Color) = switch model.state {
        case .working: (t.working, "checkmark.circle.fill", .green)
        case .notWorking: (t.notWorking, "exclamationmark.triangle.fill", .orange)
        case .checking: (t.checking, "circle.dotted", .secondary)
        }
        // 안내 문구: 오류 > 다시 설치 필요 > 작동 안 함 > 카카오톡 재시작 알림 순으로 하나만
        let note: (text: String, isError: Bool)? =
            if let error = model.error { (error, true) }
            else if model.serverOutdated { (t.serverOutdated, false) }
            else if model.state == .notWorking { (t.notWorkingNote, false) }
            else if model.restartedKakao && model.state == .working { (t.restarted, false) }
            else { nil }
        let needsReinstall = model.state == .notWorking || model.serverOutdated
        VStack(alignment: .leading, spacing: 14) {
            Header {
                Text("KleanTalk").font(.title3.bold())
                Label(label, systemImage: symbol).foregroundStyle(color)
            }
            // 설정 앱처럼 한 묶음 안에 줄을 나란히 둔다
            VStack(spacing: 0) {
                if let note {
                    GroupRow {
                        Text(note.text).font(.callout)
                            .foregroundStyle(note.isError ? Color.red : Color.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        // 문제가 있을 때만: 진단 정보를 복사해 어디든 붙여 넣어 보낼 수 있게
                        if model.state == .notWorking || model.error != nil {
                            Button(model.copiedInfo ? t.copiedInfo : t.copyInfo) { model.copyInfo() }
                        }
                        if needsReinstall { Button(t.reinstall) { model.install() } }
                    }
                    Divider()
                }
                GroupRow {
                    Text(t.version)
                    Spacer()
                    switch model.update {
                    case .available(let new):
                        Text(model.version).foregroundStyle(.secondary)
                        Button(String(format: t.updateTo, new)) { model.onInstallUpdate?() }
                            .buttonStyle(.borderedProminent)
                    case .upToDate:
                        Text("\(model.version) · \(t.upToDate)").foregroundStyle(.secondary)
                    case .unknown:
                        Text(model.version).foregroundStyle(.secondary)
                    }
                }
                Divider()
                GroupRow {
                    Text(t.language)
                    Spacer()
                    Picker("", selection: $model.language) {
                        Text("한국어").tag(Language.ko)
                        Text("English").tag(Language.en)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                LinkRow(title: t.reportBug) { model.reportBug() }
                Divider()
                LinkRow(title: t.uninstallButton) { model.error = nil; model.screen = .uninstallConfirm }
            }
            .groupBox()
            .disabled(model.busy)
        }
        .task { await model.check() }
    }
}

extension View {
    /// 설정 앱처럼 줄들을 둥근 묶음으로 감싼다
    func groupBox() -> some View {
        padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// 묶음 안의 한 줄: 왼쪽에 이름, 오른쪽에 값이나 버튼
struct GroupRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 8) { content }
            .frame(minHeight: 34)
            .padding(.vertical, 2)
    }
}

/// 누르면 동작하는 줄 (오른쪽에 >)
struct LinkRow: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            GroupRow {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct UninstallView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let t = model.t
        VStack(alignment: .leading, spacing: 0) {
            Header { Text(t.uninstallTitle).font(.headline) }
            Text(t.uninstallBody).font(.callout).foregroundStyle(.secondary).padding(.top, 12)
            Spacer()
            HStack(spacing: 8) {
                Spacer()
                Button(t.cancel) { model.screen = .status }
                    .keyboardShortcut(.cancelAction)
                Button(t.uninstall, role: .destructive) { model.uninstall() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .disabled(model.busy)
        }
    }
}

// MARK: - 앱

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.myungchul.kleantalk"
    private static let showWindowNotification = Notification.Name(bundleID + ".showWindow")

    static func main() {
        // 지원용: 터미널에서 KleanTalk.app/Contents/MacOS/KleanTalk --diagnose 로 단계별 확인 결과를 출력한다
        if CommandLine.arguments.contains("--diagnose") {
            Task {
                for line in await AdServer.diagnose() { print(line) }
                exit(0)
            }
            dispatchMain()
        }
        let app = NSApplication.shared
        let pid = ProcessInfo.processInfo.processIdentifier
        // 이미 실행 중이면 그쪽에 창을 띄우라고 알리고 끝낸다 (로그인 때 뜬 백그라운드 실행과 겹치지 않게)
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: {
            $0.processIdentifier != pid && !$0.isTerminated
        }) {
            if !isBackgroundLaunch {
                DistributedNotificationCenter.default().postNotificationName(
                    showWindowNotification, object: bundleID, userInfo: nil, deliverImmediately: true)
            }
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        DistributedNotificationCenter.default().addObserver(
            delegate, selector: #selector(showWindowRequested(_:)), name: showWindowNotification, object: bundleID)
        app.run()
        DistributedNotificationCenter.default().removeObserver(delegate)
    }

    private var model: AppModel!
    private var window: NSWindow?
    private var updater: SPUStandardUpdaterController!
    private var showWindowWhenReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        model.onLanguageChange = { [weak self] in self?.buildMenu() }
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        model.onInstallUpdate = { [weak self] in self?.updater.checkForUpdates(nil) }
        if ProcessInfo.processInfo.environment["KLEANTALK_UPDATE_TEST"] != nil {
            // 개발용: 업데이트를 바로 확인해 창 없이 받고, 받자마자 설치·재실행한다
            updater.updater.automaticallyDownloadsUpdates = true
            updater.updater.checkForUpdatesInBackground()
        }
        buildMenu()
        if isBackgroundLaunch {
            NSApp.setActivationPolicy(.accessory)
            Task { await checkAndShowIfBroken() }
        }
        if !isBackgroundLaunch || showWindowWhenReady {
            showWindowWhenReady = false
            showWindow()
        }
        // 켜져 있는 동안 6시간마다 설정이 풀리지 않았는지 확인한다
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkAndShowIfBroken() }
        }
    }

    private func checkAndShowIfBroken() async {
        guard AdServer.installed else { return }
        await model.check()
        if model.state == .notWorking || model.serverOutdated { model.screen = .status; showWindow() }
    }

    // MARK: 업데이트 (Sparkle)

    /// 개발용: 시험할 때만 업데이트 목록 주소를 바꾼다 (KLEANTALK_FEED). 평소에는 Info.plist의 SUFeedURL.
    func feedURLString(for updater: SPUUpdater) -> String? { ProcessInfo.processInfo.environment["KLEANTALK_FEED"] }

    /// 창 없이 도는 동안에도 업데이트 창이 다른 창 뒤에 숨지 않게 한다
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.setActivationPolicy(.regular)
        NSApp.bringToFront()
    }

    func standardUserDriverWillFinishUpdateSession() {
        if window?.isVisible != true && AdServer.installed { NSApp.setActivationPolicy(.accessory) }
    }

    @objc private func checkForUpdates(_ sender: Any?) { updater.checkForUpdates(sender) }

    /// 창을 열 때 새 버전이 있는지 조용히 확인한다(창은 띄우지 않는다). 결과는 상태 화면의 버전 줄에 보인다.
    private func probeForUpdate() {
        let env = ProcessInfo.processInfo.environment
        guard env["KLEANTALK_PREVIEW_UPDATE"] == nil, env["KLEANTALK_SNAPSHOT"] == nil,
              updater.updater.canCheckForUpdates, !updater.updater.sessionInProgress else { return }
        updater.updater.checkForUpdateInformation()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        model.update = .available(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        model.update = .upToDate
    }
    @objc private func reportBug(_ sender: Any?) { model.reportBug() }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        guard ProcessInfo.processInfo.environment["KLEANTALK_UPDATE_TEST"] != nil else { return false }
        immediateInstallationBlock()
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        requestWindow()
        return true
    }

    @objc private func showWindowRequested(_ notification: Notification) { requestWindow() }

    private func requestWindow() {
        guard model != nil else { showWindowWhenReady = true; return }
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        // 설치 전이면 끝낸다. 설치 후에는 창 없이 남아 가끔 상태를 확인한다.
        if AdServer.installed { NSApp.setActivationPolicy(.accessory) } else { NSApp.terminate(nil) }
    }

    private func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 190),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "KleanTalk"   // 제목은 보이지 않지만 Mission Control·윈도우 메뉴에 쓰인다
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            if ProcessInfo.processInfo.environment["KLEANTALK_SNAPSHOT"] != nil {
                // 스냅숏은 창이 맨 앞이 아니어도 활성 창 모양(파란 기본 버튼)으로 그린다
                w.contentView = NSHostingView(rootView: RootView(model: model).environment(\.controlActiveState, .key))
            } else {
                w.contentView = NSHostingView(rootView: RootView(model: model))
            }
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.bringToFront()
        // 키보드 탐색이 켜진 맥에서는 창이 첫 버튼(버그 신고)에 초점을 줘 선택된 것처럼 보인다. 열 때는 초점을 비운다(Tab으로는 그대로 이동).
        window?.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(nil) }
        probeForUpdate()
        if let path = ProcessInfo.processInfo.environment["KLEANTALK_SNAPSHOT"] { snapshot(to: path) }
    }

    /// 개발용: 창 내용을 2배 크기 PNG로 저장하고 끝낸다 (소개 이미지·문서용, KLEANTALK_SNAPSHOT=<파일>)
    private func snapshot(to path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let view = self?.window?.contentView else { NSApp.terminate(nil); return }
            let size = view.bounds.size
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { NSApp.terminate(nil); return }
            rep.size = size
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }

    private func buildMenu() {
        let t = model.t
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: t.checkUpdates, action: #selector(checkForUpdates(_:)), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: t.reportBug + "…", action: #selector(reportBug(_:)), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: t.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: t.edit)
        edit.addItem(withTitle: t.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: t.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: t.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: t.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: t.window)
        windowMenu.addItem(withTitle: t.close, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}

extension NSApplication {
    /// 창을 앞으로 가져온다. activate()는 macOS 14부터라 12·13에서는 예전 방식을 쓴다.
    func bringToFront() {
        if #available(macOS 14, *) { activate() } else { activate(ignoringOtherApps: true) }
    }
}
