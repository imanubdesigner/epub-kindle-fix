<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/epub-kindle-fix-logo-dark.svg"/>
    <img src="assets/epub-kindle-fix-logo.svg" alt="epub-kindle-fix logo" width="520"/>
  </picture>
</div>

<div align="center">

![Bash](https://img.shields.io/badge/Bash-4EAA25.svg?style=for-the-badge&logo=gnubash&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.x-3776AB.svg?style=for-the-badge&logo=python&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624.svg?style=for-the-badge&logo=linux&logoColor=black)
![macOS](https://img.shields.io/badge/macOS-000000.svg?style=for-the-badge&logo=apple&logoColor=white)
![EPUB](https://img.shields.io/badge/EPUB-EB5E28.svg?style=for-the-badge&logo=epub&logoColor=white)
![Kindle](https://img.shields.io/badge/Send%20to%20Kindle-232F3E.svg?style=for-the-badge&logo=amazon&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-6C3BAA.svg?style=for-the-badge&logo=opensourceinitiative&logoColor=white)
</div>



A CLI tool to fix EPUB files for use with Amazon's **Send to Kindle** service.

This project is a faithful port and improvement of the original web-based tool by [**@innocenat**](https://github.com/innocenat) — [kindle-epub-fix](https://github.com/innocenat/kindle-epub-fix). All credit for the original idea, research, and core fixes goes to him. This repository extends his work with additional fixes and brings it to the command line as a Bash + Python script, so you can process EPUBs directly from your terminal without a browser.

---

## ❓ Why does this exist?

The EPUB format requires files to declare their character encoding explicitly — without that declaration, a parser has no reliable way to know how bytes map to characters. Amazon's Send to Kindle service, built on infrastructure that predates widespread UTF-8 adoption, fills that gap by falling back to **ISO-8859-1** (Latin-1), a legacy single-byte encoding that only covers 256 characters.

The result: any character outside that range — accented letters like `à`, `ö`, `ñ`, punctuation like `"` or `—`, or any non-Latin script — gets decoded incorrectly and shows up on your Kindle as garbled symbols or empty boxes. The book was never broken. The encoding assumption was.

Beyond encoding, Send to Kindle also enforces stricter EPUB structural rules than most readers do. Errors that Calibre, Apple Books, or Kobo silently overlook — a missing language tag, a wrong image MIME type, a fragment link pointing to a `<body>` ID — will cause Amazon's converter to reject or mangle the file. This tool fixes all of those issues before the file ever reaches Amazon's servers.

---

## 🛠️ Fixes applied

The script runs 16 fixes in order (8 original + 8 EpubCheck-style validations).

<details>
<summary><b>1. <code>fixBodyIdLink</code></b> — Fix body ID fragment links</summary>

Replaces fragment links (e.g. `chapter.xhtml#bodyID`) that point to a `<body id="…">` element with a plain file reference (`chapter.xhtml`). Amazon rejects EPUBs where NCX or TOC files link directly to a body ID hash. Replacement is scoped to `href` and `src` attributes only — no false positives in body text.
</details>

<details>
<summary><b>2. <code>fixBookLanguage</code></b> — Validate book language</summary>

Checks the `<dc:language>` tag in the OPF metadata against Amazon KDP's list of supported language codes (ISO 639-1 and ISO 639-2). If the tag is missing or uses an unsupported code, the script prompts you interactively to provide a valid replacement.
</details>

<details>
<summary><b>3. <code>fixStrayIMG</code></b> — Remove stray images</summary>

Removes `<img>` tags that have no `src` attribute. These are technically invalid and can cause Kindle to reject the EPUB during processing.
</details>

<details>
<summary><b>4. <code>fixEncoding</code></b> — Add XML encoding declaration</summary>

Prepends an XML encoding declaration (`<?xml version="1.0" encoding="utf-8"?>`) to every HTML/XHTML file that is missing one. Also strips the UTF-8 BOM (`\xEF\xBB\xBF`) if present, which would otherwise make the declaration appear after the BOM and break XML parsing.
</details>

<details>
<summary><b>5. <code>fixCoverMeta</code></b> — Ensure cover meta tag</summary>

Ensures a `<meta name="cover" content="…"/>` element exists in the OPF metadata, pointing to the cover image manifest item. Without this, Kindle does not display the cover thumbnail in your library grid.
</details>

<details>
<summary><b>6. <code>fixManifestTypes</code></b> — Correct media types</summary>

Corrects wrong `media-type` declarations in the OPF manifest for image files. For example, a `.jpg` file declared as `image/png` will be silently ignored by Kindle. The correct MIME type is inferred from the file extension.
</details>

<details>
<summary><b>7. <code>fixSpineLinear</code></b> — Fix spine linearity</summary>

Sets `linear="yes"` on spine items that have `linear="no"` but appear to be real chapters (i.e. not cover, TOC, or NCX files). Some converters incorrectly mark all non-cover items as non-linear, causing Kindle to skip them during reading.
</details>

<details>
<summary><b>8. <code>fixBrokenFontFace</code></b> — Remove broken fonts</summary>

Removes `@font-face` CSS rules that reference font files not actually included in the EPUB archive. These broken declarations generate warnings during conversion and can interfere with Kindle's rendering pipeline.
</details>

<details>
<summary><b>9. <code>fixManifestFiles</code></b> — Verify manifest files</summary>

Verifies that all files referenced in the OPF manifest actually exist inside the EPUB archive. Manifest entries pointing to missing files are **automatically removed**, preventing reading system failures.
</details>

<details>
<summary><b>10. <code>fixBrokenLinks</code></b> — Fix broken file references</summary>

Scans all XHTML, OPF, and NCX files for `href` and `src` attributes. Broken internal links are **automatically fixed** by case-insensitive file matching or removed if the file cannot be found. External URLs, anchors (`#id`), and data URIs are correctly skipped.
</details>

<details>
<summary><b>11. <code>fixInvalidXmlIds</code></b> — Fix invalid XML IDs</summary>

Fixes invalid XML `id` attributes that contain colons or start with digits (e.g. UUIDs like `5fa24b14-a9b0-4b94-bd4b-c3513accae2d`). These violate XML naming rules and cause parsing errors. Invalid IDs are **automatically fixed** by replacing colons with underscores and prepending `id_` if needed. All references to renamed IDs are also updated.
</details>

<details>
<summary><b>12. <code>validateXML</code></b> — Validate XML well-formedness</summary>

Checks that all XHTML, OPF, and NCX files are well-formed XML using Python's `xml.etree.ElementTree` parser. Malformed XML is reported as a warning (manual fix required).
</details>

<details>
<summary><b>13. <code>fixDuplicateIds</code></b> — Fix duplicate IDs</summary>

Finds duplicate `id` attributes within each XHTML file. The first occurrence stays unchanged; subsequent duplicates are **automatically renamed** with unique `_dup2`, `_dup3`, etc. suffixes. Per-file processing is correct for EPUB, where each XHTML file is an independent XML document.
</details>

<details>
<summary><b>14. <code>fixNamespaces</code></b> — Add missing namespaces</summary>

Adds missing required XML namespaces:
- OPF: `http://www.idpf.org/2007/opf` and `http://purl.org/dc/elements/1.1/`
- XHTML: `http://www.w3.org/1999/xhtml`

Missing namespaces are **automatically added** to prevent parsing errors in strict reading systems like Kindle.
</details>

<details>
<summary><b>15. <code>fixValueAttributes</code></b> — Remove invalid value attributes</summary>

Removes the `value` attribute from HTML elements where it is not valid in XHTML 1.1 (EPUB 2.0.1). The `value` attribute is only permitted on `<input>`, `<option>`, `<param>`, and `<button>`. On `<li>` and other elements it triggers EpubCheck error RSC-005.
</details>

<details>
<summary><b>16. <code>fixBrokenFragments</code></b> — Remove broken fragment links</summary>

Strips fragment identifiers (`#id`) from links that reference non-existent IDs in the target file. Resolves EpubCheck error RSC-012.
</details>

---

## 🚀 Usage

```bash
chmod +x kindle-epub-fix.sh

# Single file
./kindle-epub-fix.sh book.epub

# Multiple files
./kindle-epub-fix.sh book1.epub book2.epub

# Whole folder
./kindle-epub-fix.sh *.epub
```

The script outputs a new file with ` (fixed)` suffix if any fixes were applied, or ` (repacked)` if the file was already clean. The original file is never modified.

---

## 📦 Dependencies

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

## ⚠️ Warning

The script never touches your original file — it always writes the result to a new `(fixed)` or `(repacked)` copy. That said, I still recommend keeping a manual backup of your EPUB before running it. The output should work correctly with Send to Kindle, but I can't guarantee it will be a valid EPUB in every edge case — EPUB files come in too many flavours to cover them all.

---

## 🙏 Credits

Original concept and web implementation: [innocenat/kindle-epub-fix](https://github.com/innocenat/kindle-epub-fix)  
CLI port and extended fixes: this repository.

---

## 📄 License

MIT
