<div align="center">
  <img src="epub-kindle-fix-logo.svg" alt="epub-kindle-fix logo" width="520"/>
</div>

<div align="center">

![Shell Script](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnu-bash&logoColor=white)
![Python](https://img.shields.io/badge/python-3.x-3776AB?logo=python&logoColor=white)
![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS-lightgrey)
![EPUB](https://img.shields.io/badge/format-EPUB-orange)
![Kindle](https://img.shields.io/badge/target-Send%20to%20Kindle-232F3E?logo=amazon&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)
</div>

# epub-kindle-fix

A CLI tool to fix EPUB files for use with Amazon's **Send to Kindle** service.

This project is a faithful port and improvement of the original web-based tool by [**@innocenat**](https://github.com/innocenat) — [kindle-epub-fix](https://github.com/innocenat/kindle-epub-fix). All credit for the original idea, research, and core fixes goes to him. This repository extends his work with additional fixes and brings it to the command line as a Bash + Python script, so you can process EPUBs directly from your terminal without a browser.

---

## Why does this exist?

The EPUB format requires files to declare their character encoding explicitly — without that declaration, a parser has no reliable way to know how bytes map to characters. Amazon's Send to Kindle service, built on infrastructure that predates widespread UTF-8 adoption, fills that gap by falling back to **ISO-8859-1** (also known as Latin-1), a legacy single-byte encoding that only covers 256 characters.

The result: any character outside that range — accented letters like `à`, `ö`, `ñ`, punctuation like `"` or `—`, or any non-Latin script — gets decoded incorrectly and shows up on your Kindle as garbled symbols or empty boxes. The book was never broken. The encoding assumption was.

Beyond encoding, Send to Kindle also enforces stricter EPUB structural rules than most readers do. Errors that Calibre, Apple Books, or Kobo silently overlook — a missing language tag, a wrong image MIME type, a fragment link pointing to a `<body>` ID — will cause Amazon's converter to reject or mangle the file. This tool fixes all of those issues before the file ever reaches Amazon's servers.

---

## Fixes applied

The script runs 8 fixes in order:

**1. `fixBodyIdLink`**
Replaces fragment links (e.g. `chapter.xhtml#bodyID`) that point to a `<body id="…">` element with a plain file reference (`chapter.xhtml`). Amazon rejects EPUBs where NCX or TOC files link directly to a body ID hash. Replacement is scoped to `href` and `src` attributes only — no false positives in body text.

**2. `fixBookLanguage`**
Checks the `<dc:language>` tag in the OPF metadata against Amazon KDP's list of supported language codes (ISO 639-1 and ISO 639-2). If the tag is missing or uses an unsupported code, the script prompts you interactively to provide a valid replacement.

**3. `fixStrayIMG`**
Removes `<img>` tags that have no `src` attribute. These are technically invalid and can cause Kindle to reject the EPUB during processing.

**4. `fixEncoding`**
Prepends an XML encoding declaration (`<?xml version="1.0" encoding="utf-8"?>`) to every HTML/XHTML file that is missing one. Also strips the UTF-8 BOM (`\xEF\xBB\xBF`) if present, which would otherwise make the declaration appear after the BOM and break XML parsing.

**5. `fixCoverMeta`**
Ensures a `<meta name="cover" content="…"/>` element exists in the OPF metadata, pointing to the cover image manifest item. Without this, Kindle does not display the cover thumbnail in your library grid.

**6. `fixManifestTypes`**
Corrects wrong `media-type` declarations in the OPF manifest for image files. For example, a `.jpg` file declared as `image/png` will be silently ignored by Kindle. The correct MIME type is inferred from the file extension.

**7. `fixSpineLinear`**
Sets `linear="yes"` on spine items that have `linear="no"` but appear to be real chapters (i.e. not cover, TOC, or NCX files). Some converters incorrectly mark all non-cover items as non-linear, causing Kindle to skip them during reading.

**8. `fixBrokenFontFace`**
Removes `@font-face` CSS rules that reference font files not actually included in the EPUB archive. These broken declarations generate warnings during conversion and can interfere with Kindle's rendering pipeline.

---

## Usage

```bash
chmod +x kindle-epub-fix.sh

# Single file
./kindle-epub-fix.sh book.epub

# Multiple files
./kindle-epub-fix.sh book1.epub book2.epub

# Whole folder
./kindle-epub-fix.sh *.epub
```

The script outputs a new file prefixed with `(fixed)` if any fixes were applied, or `(repacked)` if the file was already clean. The original file is never modified.

---

## Dependencies

| Tool | Purpose |
|---|---|
| `unzip` | Extract EPUB archive |
| `zip` | Repack EPUB archive |
| `python3` | Run all fix logic |

Install on **Arch Linux:**
```bash
sudo pacman -S unzip zip python3
```

Install on **Debian/Ubuntu:**
```bash
sudo apt install unzip zip python3
```

---

## Warning

The script never touches your original file — it always writes the result to a new `(fixed)` or `(repacked)` copy. That said, I still recommend keeping a manual backup of your EPUB before running it. The output should work correctly with Send to Kindle, but I can't guarantee it will be a valid EPUB in every edge case — EPUB files come in too many flavours to cover them all.

---

## Credits

Original concept and web implementation: [innocenat/kindle-epub-fix](https://github.com/innocenat/kindle-epub-fix)  
CLI port and extended fixes: this repository.

---

## License

MIT
