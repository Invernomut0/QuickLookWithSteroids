#!/bin/bash
# OmniPreview – Remove macOS quarantine flag
# Double-click this file to run it.

APP="/Applications/OmniPreview.app"

if [ ! -d "$APP" ]; then
    osascript -e 'display alert "OmniPreview not found" message "Please drag OmniPreview to your Applications folder first, then run this script." as critical'
    exit 1
fi

osascript -e 'display dialog "OmniPreview needs one-time permission to run.\n\nClick OK to remove the macOS quarantine flag. You may be asked for your password." buttons {"Cancel", "OK"} default button "OK" with icon caution' 2>/dev/null
if [ $? -ne 0 ]; then exit 0; fi

# Remove quarantine (requires sudo for /Applications)
sudo xattr -cr "$APP"

if [ $? -eq 0 ]; then
    osascript -e 'display dialog "Done! OmniPreview is now ready to use.\n\nOpen Finder, press Space on any supported file to try it." buttons {"Open OmniPreview"} default button 1 with icon note' 2>/dev/null
    open "$APP"
else
    osascript -e 'display alert "Something went wrong" message "Try running this in Terminal:\n\nsudo xattr -cr /Applications/OmniPreview.app" as critical'
fi
