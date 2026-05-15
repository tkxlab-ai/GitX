#!/bin/bash
# anchor-rewrite.sh — align translated markdown's internal links to its own heading slugs
#
# usage: anchor-rewrite.sh <src.md> <dst.md>
#
# Context:
#   After translate-file.sh produces dst (translated), markdown links like
#   `[text](#某slug)` still point to src heading slugs — broken inside dst.
#   This script rebuilds the slug map by position-aligning headings, then
#   rewrites each src-slug → dst-slug in dst's links.
#
# Protections:
#   - Code blocks (``` fences) NOT touched
#   - External URLs (contain ://) keep their fragments unchanged
#   - Inline `code spans` with #anchor — NOT touched (best-effort: we only
#     match `](#...)` style link syntax, not bare #fragments)
#
# GitHub slug rules (subset):
#   - Lowercase
#   - Strip emoji, most ASCII punctuation
#   - Spaces → `-`
#   - CJK kept verbatim; consumer percent-encodes at URL time
#   - Duplicate slugs get `-1`, `-2` suffixes in document order
#
# Delegates heavy lifting to embedded python3 (bash alone is too weak for
# Unicode/URL-encoding + order-sensitive slug dedup).
#
# exit: 0 success / 1 runtime / 2 usage

set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "usage: anchor-rewrite.sh <src.md> <dst.md>" >&2
    exit 2
fi

SRC=$1
DST=$2

for f in "$SRC" "$DST"; do
    [ -f "$f" ] || { echo "❌ file not found: $f" >&2; exit 1; }
done

# python3 is required; if absent this is a fatal environment issue (CI should
# always have python3; bash heuristic can't safely do Unicode slug + URL-enc).
if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ anchor-rewrite.sh requires python3" >&2
    exit 1
fi

python3 - "$SRC" "$DST" <<'PY'
import sys, re, urllib.parse

src_path, dst_path = sys.argv[1], sys.argv[2]

# Emoji + symbol removal range (used by GitHub's anchor algorithm). Not complete,
# but covers the common cases seen in this repo's headings (🎯 🧭 📦 🐛 etc).
EMOJI_RE = re.compile(
    "["
    "\U0001F300-\U0001FAFF"  # symbols, pictographs, emoticons
    "\U00002600-\U000027BF"  # misc symbols + dingbats
    "\U0001F000-\U0001F0FF"
    "\U00002B00-\U00002BFF"
    "\U0001F900-\U0001F9FF"
    "‍️"           # ZWJ + variation selector
    "]+"
)

def slugify(text):
    """GitHub-style slug: lowercase, strip emoji, strip most punctuation,
    spaces → hyphens, keep CJK. Returns bare slug (NOT URL-encoded)."""
    s = text.strip()
    s = EMOJI_RE.sub("", s)
    # Drop GitHub-excluded punctuation; keep letters / digits / spaces / hyphens / CJK
    s = re.sub(r"[^\w\s\-一-鿿㐀-䶿]", "", s, flags=re.UNICODE)
    s = s.strip().lower()
    s = re.sub(r"\s+", "-", s)
    # Collapse multiple hyphens
    s = re.sub(r"-+", "-", s)
    s = s.strip("-")
    return s

def extract_heading_slugs(content):
    """Walk markdown headings in order, skipping code blocks.
    Return list of slugs in document order (with -N dedup)."""
    in_fence = False
    seen = {}
    slugs = []
    for line in content.splitlines():
        # Toggle on ```  or ~~~
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if not m:
            continue
        text = m.group(2)
        base = slugify(text)
        if not base:
            continue
        n = seen.get(base, 0)
        final = base if n == 0 else f"{base}-{n}"
        seen[base] = n + 1
        slugs.append(final)
    return slugs

def url_encode_cjk(slug):
    """GitHub encodes non-ASCII slug chars as percent-escapes; ASCII letters/
    digits/hyphens stay literal."""
    return urllib.parse.quote(slug, safe="-")

with open(src_path, "r", encoding="utf-8") as f:
    src_text = f.read()
with open(dst_path, "r", encoding="utf-8") as f:
    dst_text = f.read()

src_slugs = extract_heading_slugs(src_text)
dst_slugs = extract_heading_slugs(dst_text)

# Position-align: position i in src corresponds to position i in dst.
# If lengths differ, process prefix intersection; warn on stderr but proceed.
n = min(len(src_slugs), len(dst_slugs))
if len(src_slugs) != len(dst_slugs):
    print(
        f"⚠️  heading count mismatch: src={len(src_slugs)} dst={len(dst_slugs)}; "
        f"aligning prefix of {n}",
        file=sys.stderr,
    )

slug_map = {}  # src_variant -> dst_variant
for i in range(n):
    src_bare = src_slugs[i]
    dst_bare = dst_slugs[i]
    # Map both bare and URL-encoded forms of src to the corresponding dst form
    slug_map[src_bare] = dst_bare
    slug_map[url_encode_cjk(src_bare)] = url_encode_cjk(dst_bare)

# Rewrite dst: walk line-by-line, toggle on fences, only touch link-fragment
# syntax `](#...)` outside code blocks + ignore external URLs (with ://).
out_lines = []
in_fence = False
# `[text](#frag)` — capture frag as group 1; we only rewrite if no :// before #
LINK_RE = re.compile(r"\]\(#([^\s)]+)\)")

def rewrite_line(line):
    def repl(m):
        frag = m.group(1)
        mapped = slug_map.get(frag)
        if mapped is None:
            return m.group(0)
        return f"](#{mapped})"
    return LINK_RE.sub(repl, line)

for line in dst_text.splitlines(keepends=True):
    stripped = line.lstrip()
    if stripped.startswith("```") or stripped.startswith("~~~"):
        in_fence = not in_fence
        out_lines.append(line)
        continue
    if in_fence:
        out_lines.append(line)
        continue
    out_lines.append(rewrite_line(line))

new_text = "".join(out_lines)
# Atomic-ish write: only rewrite file if content changed
if new_text != dst_text:
    with open(dst_path, "w", encoding="utf-8") as f:
        f.write(new_text)
PY
