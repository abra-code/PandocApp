#!/bin/bash
# DocToDoc.main.sh - Entry point for DocToDoc applet

echo "[$(/usr/bin/basename "$0")]"
# env | sort

# This is the main command handler. The ActionUI window is already shown
# via the ACTIONUI_WINDOW definition in Command.plist.
# The INIT_SUBCOMMAND_ID (pandoc.init) will run automatically.
