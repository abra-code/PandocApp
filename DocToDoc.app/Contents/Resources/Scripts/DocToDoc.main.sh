#!/bin/bash
# DocToDoc.main.sh - Entry point for the DocToDoc applet
#
# The window is opened by NEXT_COMMAND_ID = doctodoc.new; the object context
# (documents dropped on the app icon) propagates to the chained command, and
# doctodoc.init seeds the document list from OMC_OBJ_PATH.
#
# A non-blocking window's main command runs at an unpredictable time relative to
# the window appearing, so this stays empty on purpose - all initialization
# belongs in doctodoc.init.
exit 0
