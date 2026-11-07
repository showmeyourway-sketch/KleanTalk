#!/bin/zsh
# KleanTalk 빈 광고 서버 설치 (다시 실행하면 인증서를 새로 만들어 갱신한다)
# 실행: KleanTalk 앱의 '빈 광고 서버 설치' 버튼, 또는 ./build.sh 로 빌드한 뒤  sudo ./scripts/install-adserver.sh [서버 실행 파일]
#
# 하는 일
#  1. serv.ds.kakao.com 한 이름에만 쓰는 인증서와 키를 만든다. (인증 기관이 아닌 일반 인증서, 365일)
#     키는 root만 읽을 수 있는 폴더에 둔다.
#  2. (인증서 신뢰 등록은 이 스크립트가 아니라 KleanTalk 앱이 사용자 권한으로 한다. 아래 참고)
#  3. 빈 광고 서버를 LaunchDaemon으로 등록한다. (전용 주소 127.84.11.1:443 / 포트를 연 뒤 nobody 권한으로 동작)
#  4. /etc/hosts에서 serv.ds.kakao.com을 그 전용 주소로 돌린다. 다른 광고 주소는 계속 막는다.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "sudo로 실행하세요: sudo $0"; exit 1; }

HOST=serv.ds.kakao.com
ADDR=127.84.11.1   # 서버 전용 루프백 주소 (127.0.0.1:443을 쓰는 개발 도구와 부딪치지 않게)
LABEL=com.myungchul.kleantalk.adserver
DIR="/Library/Application Support/KleanTalk/AdServer"
PLIST=/Library/LaunchDaemons/$LABEL.plist
# 서버 실행 파일: 인자로 받거나(앱 안에 든 것), 없으면 빌드 폴더의 것
SRC="${1:-${0:A:h}/../build/kleantalk-adserver}"

[[ -x $SRC ]] || { echo "먼저 ./build.sh 로 빌드하세요 ($SRC 없음)"; exit 1; }

# 이전 설치가 있으면 서버를 멈춘다
launchctl bootout system/$LABEL 2>/dev/null || true

# 지금 인증서가 30일 넘게 남아 있으면 그대로 쓴다 (다시 설치해도 인증서 신뢰를 다시 등록할 필요가 없다)
REUSE=false
if [[ -f $DIR/cert.pem && -f $DIR/key.der ]] && /usr/bin/openssl x509 -in "$DIR/cert.pem" -noout -checkend 2592000 >/dev/null 2>&1; then
  REUSE=true
fi

# 1. 프로그램과 인증서·키
mkdir -p "$DIR"
chown root:wheel "$DIR"; chmod 755 "$DIR"
install -o root -g wheel -m 755 "$SRC" "$DIR/kleantalk-adserver"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
if [[ $REUSE == false ]]; then
# 확장 항목은 설정 파일로 준다. macOS 12의 LibreSSL 2.8.3에는 -addext 옵션이 없다.
cat > "$TMP/req.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $HOST
[ext]
subjectAltName = DNS:$HOST
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
CNF
/usr/bin/openssl genrsa -out "$TMP/key.pem" 2048 2>/dev/null
/usr/bin/openssl req -new -x509 -key "$TMP/key.pem" -days 365 -config "$TMP/req.cnf" -out "$TMP/cert.pem" 2>/dev/null
install -o root -g wheel -m 600 /dev/null "$DIR/key.der"
/usr/bin/openssl rsa -in "$TMP/key.pem" -outform DER -out "$DIR/key.der" 2>/dev/null
install -o root -g wheel -m 644 "$TMP/cert.pem" "$DIR/cert.pem"
/usr/bin/openssl x509 -in "$DIR/cert.pem" -outform DER -out "$DIR/cert.der"
chmod 644 "$DIR/cert.der"
fi

# 2. 인증서 신뢰는 여기서 하지 않는다. 관리자 권한 스크립트 안에서는 macOS가 확인 창을 띄울 수 없어
#    신뢰 설정을 거부하기 때문이다. KleanTalk 앱이 설치 뒤 사용자 권한으로 등록한다(macOS 확인 창이 뜬다).
#    터미널로 설치할 때는 맨 끝에 안내하는 명령을 사용자 권한(sudo 없이)으로 실행한다.

# 3. LaunchDaemon
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$DIR/kleantalk-adserver</string>
		<string>$DIR/cert.der</string>
		<string>$DIR/key.der</string>
	</array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
chown root:wheel "$PLIST"; chmod 644 "$PLIST"
launchctl bootstrap system "$PLIST"

# 4. hosts: serv.ds.kakao.com만 서버 전용 주소로. KleanTalk 블록이 없으면 만든다.
# 매번 타임스탬프 백업을 남기고(최대 5개), 같은 디렉터리 임시 파일+rename으로 원자 교체한다.
TS=$(date +%Y%m%d-%H%M%S)
cp -p /etc/hosts "/etc/hosts.kleantalk.$TS.bak"
ls -t /etc/hosts.kleantalk.*.bak 2>/dev/null | tail -n +6 | xargs rm -f --
if ! grep -q '^# >>> KakaoAdBlock' /etc/hosts; then
  printf '\n# >>> KakaoAdBlock (managed by KleanTalk)\n0.0.0.0 display.ad.daum.net\n:: display.ad.daum.net\n0.0.0.0 analytics.ad.daum.net\n:: analytics.ad.daum.net\n0.0.0.0 %s\n:: %s\n# <<< KakaoAdBlock\n' $HOST $HOST >> /etc/hosts
fi
# 블록 안에서 관리 대상(serv.ds.kakao.com, daum 광고 2종)만 정리하고, 그 밖의 행·주석·별칭은 그대로 둔다.
# IPv6가 막혀 있으면 카카오톡은 곧바로 IPv4(전용 주소)로 연결한다.
TMP_HOSTS=$(mktemp /etc/hosts.kleantalk.XXXXXX)
trap 'rm -f "$TMP_HOSTS"; rm -rf "${TMP:?}"' EXIT
awk -v host="$HOST" -v addr="$ADDR" '
  /^# >>> KakaoAdBlock/ { inside = 1; print; next }
  /^# <<< KakaoAdBlock/ { inside = 0; print; next }
  !inside { print; next }
  NF < 2 { print; next }
  $1 ~ /^[0-9.]+$/ {
    if ($2 == host) { sub(/^[0-9.]+/, addr); print; next }
    if ($2 == "display.ad.daum.net" || $2 == "analytics.ad.daum.net") { sub(/^[0-9.]+/, "0.0.0.0"); print; next }
    print; next
  }
  $1 ~ /:/ {
    if ($2 == host || $2 == "display.ad.daum.net" || $2 == "analytics.ad.daum.net") { sub(/^[^[:space:]]+/, "::"); print; next }
    print; next
  }
  { print }
' /etc/hosts > "$TMP_HOSTS"
chmod 644 "$TMP_HOSTS"; chown root:wheel "$TMP_HOSTS"
mv -f "$TMP_HOSTS" /etc/hosts
trap - EXIT
dscacheutil -flushcache; killall mDNSResponder 2>/dev/null || true

# 5. 모든 사용자 로그인 확인: 시스템 에이전트로 등록한다 (upstream #1: 다른 계정에서 광고 복귀).
#    인증서 신뢰가 사용자 도메인이라, 다른 계정에서는 그 계정으로 한 번 신뢰 등록이 필요하다.
#    시스템 에이전트가 각 로그인 때 백그라운드 확인을 돌려, 풀렸으면 창을 띄워 안내한다.
#    앱이 공용 위치(/Applications)에 있을 때만 등록한다.
AGENT_LABEL=com.myungchul.kleantalk
SYSAGENT=/Library/LaunchAgents/$AGENT_LABEL.plist
APP_DIR=${SRC%/Contents/Resources/kleantalk-adserver}
if [[ $SRC == */Contents/Resources/kleantalk-adserver && $APP_DIR == /Applications/* && -x $APP_DIR/Contents/MacOS/KleanTalk ]]; then
  cat > "$SYSAGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$AGENT_LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$APP_DIR/Contents/MacOS/KleanTalk</string>
		<string>--background</string>
	</array>
	<key>RunAtLoad</key><true/>
	<key>ProcessType</key><string>Interactive</string>
	<key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF
  chown root:wheel "$SYSAGENT"; chmod 644 "$SYSAGENT"
  echo "모든 사용자 로그인 확인을 등록했습니다 ($SYSAGENT). 다른 계정에서는 첫 로그인 때 신뢰 등록 안내가 뜹니다."
else
  echo "참고: 앱이 /Applications에 없어서 설치한 계정에서만 로그인 확인이 돕니다. /Applications로 옮긴 뒤 다시 설치하세요."
fi

echo "설치했습니다. 터미널로 설치했다면 마지막으로 인증서 신뢰를 등록하세요 (sudo 없이, macOS 확인 창이 뜸):"
echo "  security add-trusted-cert -r trustRoot -p ssl -s $HOST \"$DIR/cert.pem\""
echo "그다음 카카오톡을 종료했다가 다시 열면 광고 자리가 빈 공간으로 바뀝니다."
echo "인증서 만료: $(/usr/bin/openssl x509 -in "$DIR/cert.pem" -noout -enddate | cut -d= -f2) — 그 전에 이 스크립트를 다시 실행하면 갱신됩니다."
