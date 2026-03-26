#!/usr/bin/env bash

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m';      RESET='\033[0m'

info()   { echo -e "  ${CYAN}→${RESET} $*"; }
ok()     { echo -e "  ${GREEN}✔${RESET} $*"; }
warn()   { echo -e "  ${YELLOW}⚠${RESET} $*"; }
err()    { echo -e "  ${RED}✖${RESET} $*" >&2; }
header() { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ── Dependency check ─────────────────────────────────────────
check_deps() {
    local missing=()
    for cmd in unzip zip python3; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing dependencies: ${missing[*]}"
        echo "  Install (Arch):   sudo pacman -S ${missing[*]}"
        echo "  Install (Debian): sudo apt install ${missing[*]}"
        exit 1
    fi
}

# ════════════════════════════════════════════════════════════
#  All fixes — Python (faithful port + new fixes)
#  Output is written to a dedicated JSON file to avoid
#  mixing prompts/warnings with the result payload.
# ════════════════════════════════════════════════════════════
run_fixes() {
    local workdir="$1"
    local json_out="$2"
    python3 - "$workdir" "$json_out" <<'PYEOF'
import sys, os, re, json

workdir  = sys.argv[1]
json_out = sys.argv[2]
fixed_problems = []

# ── Helpers ──────────────────────────────────────────────────
TEXT_EXTS = {'html','xhtml','htm','xml','svg','css','opf','ncx'}

def all_files(wd):
    """Yield (rel_path, abs_path) for all files."""
    for root, dirs, files in os.walk(wd):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
        for f in sorted(files):
            abs_p = os.path.join(root, f)
            rel   = os.path.relpath(abs_p, wd).replace(os.sep, '/')
            yield rel, abs_p

def text_files(wd):
    for rel, abs_p in all_files(wd):
        e = fext(rel)
        if e in TEXT_EXTS or rel == 'mimetype':
            yield rel, abs_p

def binary_files(wd):
    for rel, abs_p in all_files(wd):
        e = fext(rel)
        if e not in TEXT_EXTS and rel != 'mimetype':
            yield rel, abs_p

def read_text(path):
    with open(path, 'r', encoding='utf-8-sig', errors='replace') as f:
        # utf-8-sig automatically strips BOM on read
        return f.read()

def write_text(path, content):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

def fext(rel):
    return rel.rsplit('.', 1)[-1].lower() if '.' in rel else ''

def fbase(path):
    return os.path.basename(path)

def simplify_language(lang):
    return lang.split('-')[0].lower()

def prompt_user(message, default=''):
    print(f'\n  \033[1;33m⚠\033[0m  {message}', flush=True)
    try:
        val = input(f'  [default: {default!r}]: ').strip()
    except EOFError:
        val = ''
    return val if val else default

# ── KDP allowed languages ─────────────────────────────────────
ALLOWED_LANGUAGES = {
    'af','gsw','ar','eu','nb','br','ca','zh','kw','co','da','nl','stq','en','fi','fr','fy','gl',
    'de','gu','hi','is','ga','it','ja','lb','mr','ml','gv','frr','nb','nn','pl','pt','oc','rm',
    'sco','gd','es','sv','ta','cy',
    'afr','ara','eus','baq','nob','bre','cat','zho','chi','cor','cos','dan','nld','dut','eng','fin',
    'fra','fre','fry','glg','deu','ger','guj','hin','isl','ice','gle','ita','jpn','ltz','mar','mal',
    'glv','nor','nno','por','oci','roh','gla','spa','swe','tam','cym','wel',
}

# ── MIME type map ─────────────────────────────────────────────
EXT_TO_MIME = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'svg': 'image/svg+xml',
    'webp': 'image/webp',
}

FONT_EXTS = {'ttf', 'otf', 'woff', 'woff2', 'eot'}

# ── Build file index ──────────────────────────────────────────
files = {}  # rel_path -> abs_path (text files only)
for rel, abs_p in text_files(workdir):
    files[rel] = abs_p

# Collect binary filenames for font-face check
binary_basenames = set()
for rel, abs_p in binary_files(workdir):
    binary_basenames.add(fbase(rel))

# ════════════════════════════════════════════════════════════
# Fix 1 — fixBodyIdLink
#   Only replaces href="…#bodyID" and src="…#bodyID" attributes.
#   String replace was too broad (false positives in body text).
# ════════════════════════════════════════════════════════════
body_id_list = []

for rel, abs_p in files.items():
    if fext(rel) not in ('html', 'xhtml'):
        continue
    content = read_text(abs_p)
    m = re.search(r'<body\b[^>]*\bid=["\']([^"\']+)["\']', content, re.IGNORECASE)
    if m:
        body_id  = m.group(1)
        link_src = fbase(rel) + '#' + body_id
        link_dst = fbase(rel)
        body_id_list.append((link_src, link_dst))

if body_id_list:
    for rel, abs_p in files.items():
        content = read_text(abs_p)
        changed = False
        for src, dst in body_id_list:
            # Only replace inside href="…" or src="…" attribute values
            escaped = re.escape(src)
            new_content = re.sub(
                r'((?:href|src)=["\'])' + escaped + r'(["\'])',
                lambda m, d=dst: m.group(1) + d + m.group(2),
                content, flags=re.IGNORECASE
            )
            if new_content != content:
                fixed_problems.append(f'Replaced link target {src} → {dst} in {rel}')
                content = new_content
                changed = True
        if changed:
            write_text(abs_p, content)

# ════════════════════════════════════════════════════════════
# Fix 2 — fixBookLanguage
# ════════════════════════════════════════════════════════════
CONTAINER = 'META-INF/container.xml'

if CONTAINER in files:
    container_str = read_text(files[CONTAINER])
    opf_m = re.search(
        r'<rootfile\b[^>]+\bmedia-type=["\']application/oebps-package\+xml["\'][^>]+\bfull-path=["\']([^"\']+)["\']'
        r'|<rootfile\b[^>]+\bfull-path=["\']([^"\']+)["\'][^>]+\bmedia-type=["\']application/oebps-package\+xml["\']',
        container_str, re.IGNORECASE
    )
    opf_rel = (opf_m.group(1) or opf_m.group(2)).strip() if opf_m else None

    if opf_rel and opf_rel in files:
        opf_abs     = files[opf_rel]
        opf_content = read_text(opf_abs)
        lang_m      = re.search(r'<dc:language\b[^>]*>([^<]*)</dc:language>', opf_content, re.IGNORECASE)

        original_language = 'undefined'
        language          = 'en'

        if not lang_m:
            language = prompt_user(
                'No <dc:language> found. Specify the language (RFC 5646, e.g. en, it, fr, ja).',
                'en'
            )
        else:
            language = lang_m.group(1).strip()
            original_language = language

        if simplify_language(language) not in ALLOWED_LANGUAGES:
            language = prompt_user(
                f'Language "{language}" is not in Amazon KDP allowed list. Enter replacement or keep.',
                language
            )

        if language != original_language:
            if not lang_m:
                opf_content = re.sub(
                    r'(</metadata>)',
                    f'    <dc:language>{language}</dc:language>\n\\1',
                    opf_content, count=1, flags=re.IGNORECASE
                )
            else:
                opf_content = re.sub(
                    r'<dc:language\b[^>]*>[^<]*</dc:language>',
                    f'<dc:language>{language}</dc:language>',
                    opf_content, count=1, flags=re.IGNORECASE
                )
            write_text(opf_abs, opf_content)
            fixed_problems.append(f'Changed document language: {original_language} → {language}')
    else:
        print('  \033[1;33m⚠\033[0m OPF file not found — skipping language fix.', file=sys.stderr)
else:
    print('  \033[1;33m⚠\033[0m META-INF/container.xml not found.', file=sys.stderr)

# ════════════════════════════════════════════════════════════
# Fix 3 — fixStrayIMG
# ════════════════════════════════════════════════════════════
IMG_RE = re.compile(r'<img(?:\s[^>]*)?\s*/?>', re.IGNORECASE | re.DOTALL)

def img_has_src(tag):
    return bool(re.search(r'\bsrc\s*=', tag, re.IGNORECASE))

for rel, abs_p in files.items():
    if fext(rel) not in ('html', 'xhtml'):
        continue
    content = read_text(abs_p)
    matches = IMG_RE.findall(content)
    stray   = [t for t in matches if not img_has_src(t)]
    if stray:
        new_content = IMG_RE.sub(lambda m: m.group(0) if img_has_src(m.group(0)) else '', content)
        write_text(abs_p, new_content)
        fixed_problems.append(f'Removed {len(stray)} stray <img> tag(s) in {rel}')

# ════════════════════════════════════════════════════════════
# Fix 4 — fixEncoding (with BOM strip via utf-8-sig reader)
# ════════════════════════════════════════════════════════════
XML_DECL_RE    = re.compile(
    r'^<\?xml\s+version=["\'][\d.]+["\']\s+encoding=["\'][a-zA-Z\d\-.]+["\'].*?\?>',
    re.IGNORECASE
)
ENCODING_HEADER = '<?xml version="1.0" encoding="utf-8"?>'

for rel, abs_p in files.items():
    if fext(rel) not in ('html', 'xhtml'):
        continue
    content = read_text(abs_p)   # utf-8-sig reader already stripped BOM
    stripped = content.lstrip()
    if not XML_DECL_RE.match(stripped):
        write_text(abs_p, ENCODING_HEADER + '\n' + content)
        fixed_problems.append(f'Added XML encoding declaration to {rel}')
    elif stripped != content:
        # BOM was stripped but declaration was present — persist clean version
        write_text(abs_p, stripped)
        fixed_problems.append(f'Stripped BOM from {rel}')

# ════════════════════════════════════════════════════════════
# Fix 5 — fixCoverMeta
#   Ensure <meta name="cover" content="…"/> exists in OPF.
# ════════════════════════════════════════════════════════════
if CONTAINER in files and opf_rel and opf_rel in files:
    opf_content = read_text(files[opf_rel])

    has_cover_meta = bool(re.search(r'<meta\b[^>]+\bname=["\']cover["\']', opf_content, re.IGNORECASE))
    if not has_cover_meta:
        # Find a manifest item that looks like a cover image
        cover_m = re.search(
            r'<item\b[^>]+\bid=["\']([^"\']*cover[^"\']*)["\'][^>]+\bmedia-type=["\']image/[^"\']+["\']'
            r'|<item\b[^>]+\bmedia-type=["\']image/[^"\']+["\'][^>]+\bid=["\']([^"\']*cover[^"\']*)["\']',
            opf_content, re.IGNORECASE
        )
        if cover_m:
            cover_id = (cover_m.group(1) or cover_m.group(2)).strip()
            meta_tag = f'<meta name="cover" content="{cover_id}"/>'
            opf_content = re.sub(
                r'(</metadata>)',
                f'    {meta_tag}\n\\1',
                opf_content, count=1, flags=re.IGNORECASE
            )
            write_text(files[opf_rel], opf_content)
            fixed_problems.append(f'Added cover meta tag for manifest item "{cover_id}"')

# ════════════════════════════════════════════════════════════
# Fix 6 — fixManifestTypes
#   Correct wrong media-type for image items in manifest.
# ════════════════════════════════════════════════════════════
if CONTAINER in files and opf_rel and opf_rel in files:
    opf_content = read_text(files[opf_rel])
    changed_mt  = False

    def fix_media_type(m):
        global changed_mt
        tag      = m.group(0)
        href_m   = re.search(r'\bhref=["\']([^"\']+)["\']', tag, re.IGNORECASE)
        type_m   = re.search(r'\bmedia-type=["\']([^"\']+)["\']', tag, re.IGNORECASE)
        if not href_m or not type_m:
            return tag
        ext          = fext(href_m.group(1))
        expected     = EXT_TO_MIME.get(ext)
        declared     = type_m.group(1)
        if expected and declared and declared != expected:
            fixed_problems.append(f'Fixed media-type for {href_m.group(1)}: "{declared}" → "{expected}"')
            changed_mt = True
            return tag.replace(type_m.group(0), f'media-type="{expected}"')
        return tag

    new_opf = re.sub(r'<item\b[^>]+/>', fix_media_type, opf_content, flags=re.IGNORECASE)
    if changed_mt:
        write_text(files[opf_rel], new_opf)

# ════════════════════════════════════════════════════════════
# Fix 7 — fixSpineLinear
#   Set linear="yes" for spine items that look like real chapters.
# ════════════════════════════════════════════════════════════
if CONTAINER in files and opf_rel and opf_rel in files:
    opf_content = read_text(files[opf_rel])

    # Build id → href map from manifest
    id_to_href = {}
    for m in re.finditer(r'<item\b[^>]+>', opf_content, re.IGNORECASE):
        tag   = m.group(0)
        id_m  = re.search(r'\bid=["\']([^"\']+)["\']', tag, re.IGNORECASE)
        hr_m  = re.search(r'\bhref=["\']([^"\']+)["\']', tag, re.IGNORECASE)
        if id_m and hr_m:
            id_to_href[id_m.group(1)] = hr_m.group(1)

    spine_changed = False

    def fix_spine_linear(m):
        global spine_changed
        tag   = m.group(0)
        lin_m = re.search(r'\blinear=["\']no["\']', tag, re.IGNORECASE)
        if not lin_m:
            return tag
        id_m  = re.search(r'\bidref=["\']([^"\']+)["\']', tag, re.IGNORECASE)
        idref = id_m.group(1) if id_m else ''
        href  = id_to_href.get(idref, idref).lower()
        # Keep linear="no" only for real cover/toc pages
        if 'cover' in href or 'toc' in href or 'contents' in href or 'ncx' in href:
            return tag
        # This is a real chapter — fix it
        new_tag = re.sub(r'\blinear=["\']no["\']', 'linear="yes"', tag, flags=re.IGNORECASE)
        fixed_problems.append(f'Fixed spine linear="yes" for "{href}" (was "no")')
        spine_changed = True
        return new_tag

    new_opf = re.sub(r'<itemref\b[^>]+/?>', fix_spine_linear, opf_content, flags=re.IGNORECASE)
    if spine_changed:
        write_text(files[opf_rel], new_opf)

# ════════════════════════════════════════════════════════════
# Fix 8 — fixBrokenFontFace
#   Remove @font-face blocks referencing missing font files.
# ════════════════════════════════════════════════════════════
FONT_FACE_RE = re.compile(r'@font-face\s*\{[^}]*\}', re.IGNORECASE | re.DOTALL)
SRC_URL_RE   = re.compile(r"url\(['\"]?([^'\")\s]+)['\"]?\)", re.IGNORECASE)

for rel, abs_p in files.items():
    if fext(rel) != 'css':
        continue
    css     = read_text(abs_p)
    changed = False

    def replace_broken_font(m):
        global changed
        block = m.group(0)
        urls  = SRC_URL_RE.findall(block)
        for url in urls:
            ext = fext(url)
            if ext not in FONT_EXTS:
                continue
            fname = fbase(url)
            if fname not in binary_basenames:
                changed = True
                return '/* [kindle-epub-fix] removed broken @font-face */'
        return block

    new_css = FONT_FACE_RE.sub(replace_broken_font, css)
    if changed:
        write_text(abs_p, new_css)
        fixed_problems.append(f'Removed broken @font-face rule(s) in {rel}')

# ── Write JSON result to dedicated file ───────────────────────
with open(json_out, 'w', encoding='utf-8') as f:
    json.dump({'fixes': fixed_problems}, f, ensure_ascii=False)

PYEOF
}

# ════════════════════════════════════════════════════════════
#  Process a single EPUB
# ════════════════════════════════════════════════════════════
process_epub() {
    local epub_path="$1"
    local epub_name
    epub_name=$(basename "$epub_path")

    header "$epub_name"

    if [[ ! -f "$epub_path" ]]; then
        err "File not found: $epub_path"; return 1
    fi
    if [[ "${epub_path##*.}" != "epub" ]]; then
        warn "Not an .epub file — skipping."; return 1
    fi

    # ── Extract ──────────────────────────────────────────────
    local workdir json_out
    workdir=$(mktemp -d)
    json_out=$(mktemp)

    trap '[[ -d "${workdir:-}" ]] && rm -rf "$workdir"; [[ -f "${json_out:-}" ]] && rm -f "$json_out"' RETURN

    unzip -q "$epub_path" -d "$workdir"
    info "Extracted to temp dir"

    # ── Run fixes ────────────────────────────────────────────
    info "Applying fixes..."
    run_fixes "$workdir" "$json_out"

    # ── Read JSON result ─────────────────────────────────────
    local fix_count=0
    if [[ -f "$json_out" ]]; then
        fix_count=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(len(d['fixes']))
except Exception:
    print(0)
" "$json_out" 2>/dev/null || echo 0)

        if [[ "$fix_count" -gt 0 ]]; then
            python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
for f in d['fixes']:
    print(f'  \033[0;32m✔\033[0m {f}')
" "$json_out"
        fi
    fi

    # ── Repack ───────────────────────────────────────────────
    local out_dir out_name out_path
    out_dir=$(dirname "$epub_path")
    [[ "$fix_count" -gt 0 ]] \
        && out_name="(fixed) ${epub_name}" \
        || out_name="(repacked) ${epub_name}"
    out_path="${out_dir}/${out_name}"

    info "Repacking → ${out_name}"
    (
        cd "$workdir"
        rm -f "$out_path"
        # mimetype MUST be first and uncompressed (EPUB spec §3.3)
        if [[ -f mimetype ]]; then
            zip -qX0 "$out_path" mimetype
            # LC_ALL=C sort for deterministic, portable ordering
            find . -mindepth 1 ! -name mimetype -type f \
                | LC_ALL=C sort \
                | zip -qr "$out_path" -@
        else
            find . -mindepth 1 -type f \
                | LC_ALL=C sort \
                | zip -qr "$out_path" -@
        fi
    )

    if [[ "$fix_count" -gt 0 ]]; then
        echo -e "\n  ${GREEN}${BOLD}✔ ${fix_count} fix(es) applied${RESET}"
    else
        echo -e "\n  ${CYAN}ℹ  No errors detected — file repacked cleanly.${RESET}"
    fi
    echo -e "  ${GREEN}Output:${RESET} $out_path\n"
}

# ── Main ─────────────────────────────────────────────────────
main() {
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║   Kindle EPUB Fix  —  v1.0               ║"
    echo "  ║   port of innocenat/kindle-epub-fix      ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${RESET}"

    check_deps

    if [[ $# -eq 0 ]]; then
        echo -e "  ${YELLOW}Usage:${RESET} $0 book.epub [book2.epub ...]"
        echo -e "         $0 *.epub"
        exit 1
    fi

    local success=0 failed=0
    for epub in "$@"; do
        if process_epub "$epub"; then
            (( success++ )) || true
        else
            (( failed++ ))  || true
        fi
    done

    echo -e "${BOLD}Summary:${RESET} ${GREEN}${success} OK${RESET}  ${RED}${failed} failed${RESET}\n"
}

main "$@"
