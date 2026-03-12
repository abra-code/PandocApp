# DocToDoc.app

![DocToDoc Icon](Icon/DocToDoc-Default-256x256@1x.png)

A native macOS applet for batch conversion of documents using [pandoc](https://pandoc.org) — a universal document converter.  
Bundles pandoc 3.9 binary so no separate installation is required.

Built with **OMC 5.0** engine — [github.com/abra-code/OMC](https://github.com/abra-code/OMC/)  
UI rendered by **ActionUI** — [github.com/abra-code/ActionUI](https://github.com/abra-code/ActionUI/)

## Features

- **Batch conversion** of multiple documents in one go
- **Drag & drop** files or folders onto the app to populate the file list
- **Recursive folder scanning** for supported document types
- **30+ output formats**

## Popular Output Formats

HTML, Microsoft Word (docx), OpenDocument (odt), EPUB, PowerPoint (pptx), RTF, Markdown, LaTeX, Plain Text — plus many more in the Other section.

## Supported Input Formats

md, markdown, rst, tex, latex, html, htm, docx, odt, epub, txt, org, adoc, asciidoc, wiki, rtf, csv, tsv, json, xml, opml, ipynb, textile, t2t

## Requirements

- **macOS 14.6+**
- Separate builds for Apple Silicon (arm64) and Intel (x86_64)

## Usage

1. Launch `DocToDoc.app` (or drop files/folders onto it)
2. Add documents using the **+** button
3. Select a document to see its info
4. Choose the output format and optional flavor variant
5. Click **Convert** and pick a destination folder
