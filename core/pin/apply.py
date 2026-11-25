# Certificate pinning for links of the Xray kind (`pcs=` / `pinnedPeerCertSha256`): Xray pins the SHA-256 of a whole
# certificate (any one of the chain), stock sing-box 1.14 only the SHA-256 of the leaf's public key
# (`certificate_public_key_sha256`). With this patch a value in `certificate_public_key_sha256` also matches the hash of
# any certificate of the chain, so the app can pass both kinds there. Run by patch-singbox.sh from core/.
import io


def read(p):
    return io.open(p, encoding="utf8").read()


def write(p, s):
    io.open(p, "w", encoding="utf8", newline="\n").write(s)


def rep(s, a, b):
    assert a in s, a[:80]
    return s.replace(a, b, 1)


p = "patched/sing-box/common/tls/std_client.go"
s = read(p)
s = rep(
    s,
    "\thashValue := sha256.Sum256(pubKeyBytes)\n\tfor _, value := range knownHashValues {\n\t\tif bytes.Equal(value, hashValue[:]) {\n\t\t\treturn nil\n\t\t}\n\t}\n",
    "\thashValue := sha256.Sum256(pubKeyBytes)\n\tfor _, value := range knownHashValues {\n\t\tif bytes.Equal(value, hashValue[:]) {\n\t\t\treturn nil\n\t\t}\n\t}\n"
    "\tfor _, raw := range rawCerts {\n\t\tcertHash := sha256.Sum256(raw)\n\t\tfor _, value := range knownHashValues {\n\t\t\tif bytes.Equal(value, certHash[:]) {\n\t\t\t\treturn nil\n\t\t\t}\n\t\t}\n\t}\n",
)
write(p, s)
print("pin patched")
