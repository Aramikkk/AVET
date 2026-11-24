#!/usr/bin/env bash
# Builds AVET's core for Android: sing-box's libbox plus our avcore layer, as one AAR.
set -euo pipefail
. /c/dev/tools/env.sh
export PATH="/c/dev/tools/go/bin:/c/dev/tools/gopath/bin:$PATH"
export GOPATH="C:/dev/tools/gopath" GOMODCACHE="C:/dev/tools/gopath/pkg/mod" GOCACHE="C:/dev/tools/gocache"
export GOTOOLCHAIN=go1.27.3 GOFLAGS=-mod=mod
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
export CGO_LDFLAGS="-O2 -g -s -w -Wl,-z,max-page-size=16384"
TAGS=with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0
cd "$(dirname "$0")"
bash ./patch-singbox.sh
mkdir -p bin
gomobile bind -v -androidapi=24 -javapkg=app.avet -libname=avcore \
  -tags="$TAGS" -trimpath -ldflags="-w -s -checklinkname=0 -buildid=" \
  -target=android/arm64 \
  -o bin/avcore.aar github.com/sagernet/sing-box/experimental/libbox ./avcore
ls -la bin/avcore.aar
