#!/bin/sh
# Tests/make-fixtures.sh - build the document fixtures the suite runs against.
#
# Generated rather than committed. These are all text formats, so the generator
# is both smaller and more informative than the files it produces: it states
# exactly what each fixture contains, which is what the assertions read back.
# Usage: make-fixtures.sh <dest-dir>

set -e

dest="${1:?usage: make-fixtures.sh <dest-dir>}"
/bin/mkdir -p "$dest"

# Markdown with real heading structure, so the table-of-contents option has
# something to build a contents list out of.
cat > "$dest/article.md" <<'MD'
# First Heading

Hello from markdown. MARKER-MD

## A Subheading

More text under the subheading.

## Another Subheading

Closing text.
MD

cat > "$dest/page.html" <<'HTML'
<html><head><title>Fixture</title></head>
<body><h1>Heading</h1><p>Hello from html. MARKER-HTML</p></body></html>
HTML

# Plain text with no heading structure at all - the input the applet must NOT
# pass --toc for, because a contents list of nothing is worse than none.
printf 'Hello from plain text. MARKER-TXT\nA second line with no headings.\n' \
    > "$dest/notes.txt"

# An extension pandoc has no reader for. The applet filters it out of the list
# rather than handing it over.
printf 'nothing pandoc can read\n' > "$dest/blob.bin"

/bin/chmod a-w "$dest"/* 2>/dev/null || true
