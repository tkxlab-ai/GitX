#!/bin/bash
# test_sanitize_coverage.sh — v1.13.0 review remediation (Lane A)
#
# Why: the six-dimension review found release-sanitize.sh only scanned an
# extension allowlist (a .npmrc holding a GitHub token scanned clean), capped
# file size (a silent bypass), applied GitX-only self-test exemptions to every
# downstream project, and dropped whole lines on allowlist hits (one
# placeholder on a line hid a real address next to it).
#
# Every sensitive literal below is assembled at runtime (split strings) so
# this file itself stays clean under the repo self-scan.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANITIZE="$ROOT/scripts/release-sanitize.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# check <desc> <dir> <expected-exit> [needle...] — every needle must appear
check() {
    local desc="$1" dir="$2" want="$3"; shift 3
    local out rc n
    out=$(/bin/bash "$SANITIZE" "$dir" 2>&1); rc=$?
    if [ "$rc" != "$want" ]; then
        fail "$desc — exit $rc, want $want"
        head -30 <<<"$out" | sed 's/^/    | /'
        return
    fi
    for n in "$@"; do
        if ! grep -qF -- "$n" <<<"$out"; then
            fail "$desc — output lacks '$n'"
            head -30 <<<"$out" | sed 's/^/    | /'
            return
        fi
    done
    ok "$desc"
}

TOK="gh""p_$(printf 'A%.0s' {1..36})"
AT='@'

echo "══ test_sanitize_coverage.sh ══"

# ── A1: every regular text file is scanned (no ext allowlist, no size cap) ──
echo "A1: coverage"
mkdir -p "$TMP/a1a"
printf '//registry.npmjs.org/:_authToken=%s\n' "$TOK" > "$TMP/a1a/.npmrc"
check "A1a .npmrc with GitHub token is flagged" "$TMP/a1a" 1 ".npmrc"

mkdir -p "$TMP/a1b"
printf 'TOKEN = "%s"\n' "$TOK" > "$TMP/a1b/deploy.rb"
printf -- '-----%s OPENSSH PRIVATE KEY-----\nb3BlbnNzaA==\n' "BEGIN" > "$TMP/a1b/id_ed25519"
check "A1b deploy.rb + id_ed25519 are flagged" "$TMP/a1b" 1 "deploy.rb" "id_ed25519"

mkdir -p "$TMP/a1c" "$TMP/a1c_clean"
# Follow-up S1: credentials are scanned in binaries too (a token in a .p12 /
# sqlite / mixed blob is still a leak); the 0xFF bytes exercise byte-wise
# matching under a UTF-8 locale. The noisy detectors stay text-only.
{ printf 'x\0\0\0\377\376 '; printf '%s\n' "$TOK"; } > "$TMP/a1c/blob.bin"
check "A1c binary blob with token is credential-flagged" "$TMP/a1c" 1 "blob.bin" "GitHub personal token"
{ printf 'x\0\0\0\377\376 '; printf 'mail alice.real%sgmail.com\n' "$AT"; } > "$TMP/a1c_clean/blob-clean.bin"
check "A1c binary blob without token passes (noisy detectors stay text-only)" "$TMP/a1c_clean" 0

mkdir -p "$TMP/a1d" "$TMP/a1e"
awk 'BEGIN{for(i=0;i<300000;i++)print "lorem ipsum dolor sit"}' > "$TMP/a1e/big.txt"
cp "$TMP/a1e/big.txt" "$TMP/a1d/big.txt"
printf '%s\n' "$TOK" >> "$TMP/a1d/big.txt"
check "A1d ~6 MB text with token on last line is flagged" "$TMP/a1d" 1 "big.txt"
check "A1e ~6 MB clean text passes" "$TMP/a1e" 0

# Text head + NUL after 4 KiB: classified as text, so grep must not fall back
# to "Binary file matches" (which yields no line to report).
mkdir -p "$TMP/a1f"
{ awk 'BEGIN{for(i=0;i<300;i++)print "lorem ipsum dolor sit"}'; printf '\0\n'; echo "mail alice.real${AT}gmail.com"; } > "$TMP/a1f/late-nul.txt"
check "A1f late NUL byte does not hide a real email" "$TMP/a1f" 1 "late-nul.txt:302:alice.real${AT}gmail.com"

# Fix round 1 (I1): NUL earlier on the SAME line as the secret — bash `read`
# stops at NUL, so the old per-line loop lost the rest of the line.
nul_same_line() {
    local name="$1" secret="$2" d="$TMP/a1g_$1"
    mkdir -p "$d"
    { awk 'BEGIN{for(i=0;i<300;i++)print "lorem ipsum dolor sit"}'; printf 'x\0 %s\n' "$secret"; } > "$d/same-nul.txt"
    check "A1g same-line NUL does not hide a $name" "$d" 1 "same-nul.txt:301:$3"
}
nul_same_line path "/Us""ers/alice/secret" "/Us""ers/alice/"
nul_same_line email "alice.real${AT}gmail.com" "alice.real${AT}gmail.com"
nul_same_line ip "54.12.""34.56" "54.12.""34.56"

# Fix round 1 (I2): caps bound output, not work — a large file full of
# allowed matches must still scan in one pass per file, not one fork per line.
mkdir -p "$TMP/a1h"
awk -v at="$AT" 'BEGIN{for(i=0;i<20000;i++)print "user" at "example.com"}' > "$TMP/a1h/many.md"
_t0=$(date +%s)
check "A1h 20k allowed-email lines pass" "$TMP/a1h" 0
_dt=$(( $(date +%s) - _t0 ))
if [ "$_dt" -lt 5 ]; then ok "A1h 20k-line scan finished in ${_dt}s (< 5s)"; else fail "A1h 20k-line scan took ${_dt}s (>= 5s)"; fi

# ── A3: self-test exemptions apply only when scanning GitX itself ──────────
echo "A3: self-exemption scope"
mk_skill() { mkdir -p "$1"; printf -- '---\nname: %s\ndescription: x\n---\n# body\n' "$2" > "$1/SKILL.md"; }
plant_exempt_paths() {
    mkdir -p "$1/references" "$1/tests/fixtures" "$1/evals/data"
    printf '%s\n' "$TOK" > "$1/references/TEST-SCENARIOS.md"
    printf '%s\n' "$TOK" > "$1/tests/fixtures/x.md"
    printf '%s\n' "$TOK" > "$1/evals/data/y.md"
}
mk_skill "$TMP/a3a" demo-skill; plant_exempt_paths "$TMP/a3a"
check "A3-A downstream skill: GitX self-test paths are scanned" "$TMP/a3a" 1 \
    "references/TEST-SCENARIOS.md" "tests/fixtures/x.md" "evals/data/y.md"
mk_skill "$TMP/a3b" gitx-release; plant_exempt_paths "$TMP/a3b"
check "A3-B gitx-release itself: self-test paths stay exempt" "$TMP/a3b" 0

# Fix round 1 (M2): a root SKILL.md that is NOT gitx-release wins over a
# vendored skills/gitx-release/; and a body line never counts as frontmatter.
mk_skill "$TMP/a3d" other-repo
mk_skill "$TMP/a3d/skills/gitx-release" gitx-release
mkdir -p "$TMP/a3d/skills/other/tests/fixtures"
printf '%s\n' "$TOK" > "$TMP/a3d/skills/other/tests/fixtures/x.md"
check "A3-D vendored skills/gitx-release does not exempt the host repo" "$TMP/a3d" 1 \
    "skills/other/tests/fixtures/x.md"
mkdir -p "$TMP/a3e/tests/fixtures"
printf '# no frontmatter\nname: gitx-release\n' > "$TMP/a3e/SKILL.md"
printf '%s\n' "$TOK" > "$TMP/a3e/tests/fixtures/x.md"
check "A3-E body line 'name: gitx-release' without frontmatter is ignored" "$TMP/a3e" 1 \
    "tests/fixtures/x.md"

# Follow-up S2: exemptions are anchored to $DIR. Fallback detection (no root
# SKILL.md, only skills/gitx-release/SKILL.md) exempts only the vendored
# skills/gitx-release/ copies, never the host's own root tests/fixtures/.
mk_skill "$TMP/a3f/skills/gitx-release" gitx-release
mkdir -p "$TMP/a3f/tests/fixtures"
printf '%s\n' "$TOK" > "$TMP/a3f/tests/fixtures/x.md"
check "A3-F fallback-detected tree: host root tests/fixtures/ is scanned" "$TMP/a3f" 1 \
    "tests/fixtures/x.md"
mk_skill "$TMP/a3g/skills/gitx-release" gitx-release
mkdir -p "$TMP/a3g/skills/gitx-release/tests/fixtures"
printf '%s\n' "$TOK" > "$TMP/a3g/skills/gitx-release/tests/fixtures/x.md"
check "A3-G fallback-detected tree: skills/gitx-release/tests/fixtures/ stays exempt" "$TMP/a3g" 0
mk_skill "$TMP/a3h" gitx-release
mkdir -p "$TMP/a3h/tests/fixtures" "$TMP/a3h/docs/tests/fixtures"
printf '%s\n' "$TOK" > "$TMP/a3h/tests/fixtures/x.md"
check "A3-H root-detected gitx-release: root tests/fixtures/ stays exempt" "$TMP/a3h" 0
printf '%s\n' "$TOK" > "$TMP/a3h/docs/tests/fixtures/y.md"
check "A3-H2 root-detected: a nested docs/tests/fixtures/ is NOT exempt (anchored)" "$TMP/a3h" 1 \
    "docs/tests/fixtures/y.md"

# Shipped scanner + config must not self-trigger once copied into a
# downstream skill (no scanner-file exclusion applies there any more).
mk_skill "$TMP/a3c" my-skill
mkdir -p "$TMP/a3c/scripts"
for s in release-sanitize.sh scan-credentials.sh gitx-marketplace.sh; do
    cp "$ROOT/scripts/$s" "$TMP/a3c/scripts/$s"
done
cp "$ROOT/.sanitize-ignore" "$TMP/a3c/.sanitize-ignore"
check "A3-C downstream copy of real scanner files + .sanitize-ignore is clean" "$TMP/a3c" 0

# ── A5: match-level allowlists, line-level context exemption, caps last ────
echo "A5: match-level allowlists"
REAL="alice.real${AT}gmail.com"
mkdir -p "$TMP/a5a"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "a${i}${AT}example.com"; done > "$TMP/a5a/a.md"
echo "$REAL" >> "$TMP/a5a/a.md"
check "A5a allowed matches don't consume the per-file cap" "$TMP/a5a" 1 "a.md:13:$REAL"

mkdir -p "$TMP/a5b"
echo "user${AT}example.com noreply${AT}anthropic.com noreply${AT}github.com" > "$TMP/a5b/b.md"
check "A5b all-allowed emails on one line pass" "$TMP/a5b" 0

mkdir -p "$TMP/a5c"
echo "user${AT}example.com $REAL" > "$TMP/a5c/c.md"
check "A5c placeholder on a line no longer hides a real email" "$TMP/a5c" 1 "c.md:1:$REAL"

IP_PUB="54.12.""34.56"
mkdir -p "$TMP/a5d"
echo "primary $IP_PUB fallback 10.0.0.1" > "$TMP/a5d/d.md"
check "A5d private IP on a line no longer hides a public one" "$TMP/a5d" 1 "d.md:1:$IP_PUB"

ip_case() {
    local ip="$1" want="$2" d
    d="$TMP/a5e_$(printf '%s' "$ip" | tr '.' '_')"
    mkdir -p "$d"; echo "host $ip" > "$d/e.md"
    if [ "$want" = 1 ]; then
        check "A5e $ip is flagged (allowlist is match-anchored)" "$d" 1 "e.md:1:$ip"
    else
        check "A5e $ip is allowed" "$d" 0
    fi
}
ip_case "54.10.""0.1" 1
ip_case "1.1.1.""10" 1
ip_case "10.0.0.1" 0
ip_case "1.1.1.1" 0
ip_case "192.0.2.7" 0

US="/Us""ers"
mkdir -p "$TMP/a5f"
echo "$US/<user>/x and $US/alice/secret" > "$TMP/a5f/f.md"
check "A5f placeholder path no longer hides a real one" "$TMP/a5f" 1 "f.md:1:$US/alice/"

mkdir -p "$TMP/a5g"
echo "op://vault/item user${AT}corp.example.net" > "$TMP/a5g/g.md"
check "A5g op:// line context exempts the line" "$TMP/a5g" 0

# Same as A3-C but with no .sanitize-ignore at all: the shipped scripts
# (incl. gitx-marketplace.sh's GitHub noreply identity) are clean on their own.
mk_skill "$TMP/a5h" my-skill
mkdir -p "$TMP/a5h/scripts"
for s in release-sanitize.sh scan-credentials.sh gitx-marketplace.sh; do
    cp "$ROOT/scripts/$s" "$TMP/a5h/scripts/$s"
done
check "A5h shipped scanner scripts clean with no .sanitize-ignore" "$TMP/a5h" 0

# Placeholder domains excuse exactly one TLD label: a tail wildcard let a
# real domain that merely starts with a placeholder word slip through.
email_case() {
    local d="$TMP/a5i_$3"
    mkdir -p "$d"
    echo "contact $1" > "$d/e.md"
    check "A5i $1 → exit $2" "$d" "$2"
}
email_case "bob${AT}yourco.evil.com" 1 a
email_case "a${AT}xxxcorp.com" 1 b
email_case "a${AT}yourco.com" 0 c
email_case "a${AT}placeholder.io" 0 d

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ]
