#!/usr/bin/env bash
# Makes a patched copy of sing-box (core/patched/sing-box) for the build: the groups of the multi-server mode
# ("site-*" and "ai-*") keep a latency history of their own. Stock sing-box has one history for every group, keyed by
# the server: a site group's test of a page overwrote what the main Auto chose by (and the main Auto's results were
# taken as the site's), so Auto jumped from server to server.
set -euo pipefail
cd "$(dirname "$0")"
SRC="${GOMODCACHE:-C:/dev/tools/gopath/pkg/mod}/github.com/sagernet/sing-box@v1.14.4"
rm -rf patched
mkdir -p patched
cp -r "$SRC" patched/sing-box
chmod -R u+w patched/sing-box
python - <<'PY'
p='patched/sing-box/protocol/group/urltest.go'
s=open(p,encoding='utf8').read()
s=s.replace('\t"slices"\n','\t"slices"\n\t"strings"\n',1)
a="\t\ts.group = group\n"
assert a in s
s=s.replace(a,a+'\t\tif strings.HasPrefix(s.Tag(), "site-") || strings.HasPrefix(s.Tag(), "ai-") {\n\t\t\tgroup.history = urltest.NewHistoryStorage()\n\t\t}\n',1)
open(p,'w',encoding='utf8').write(s)
PY
cp smart/urltest_smart.go patched/sing-box/protocol/group/urltest_smart.go
cp smart/urltest_smart_test.go patched/sing-box/protocol/group/urltest_smart_test.go
python smart/apply.py
python xhttp/apply.py
python timeout/apply.py
echo patched
