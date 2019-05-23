#!/usr/bin/env bash
hdiutil attach /Applications/Install\ macOS\ Mojave\.app/Contents/SharedSupport/InstallESD.dmg -noverify -mountpoint /Volumes/mojave
hdiutil create -o ./MojaveBase.cdr -size 7316m -layout SPUD -fs HFS+J
hdiutil attach ./MojaveBase.cdr.dmg -noverify -mountpoint /Volumes/install_build
asr restore -source /Applications/Install\ macOS\ Mojave\.app/Contents/SharedSupport/BaseSystem.dmg -target /Volumes/install_build -noprompt -noverify -erase
rm -rf /Volumes/macOS\ Base\ System//System/Installation/Packages
mkdir -p /Volumes/macOS\ Base\ System//System/Installation/Packages
cp -R /Volumes/mojave/Packages/* /Volumes/macOS\ Base\ System//System/Installation/Packages/
hdiutil detach /Volumes/macOS\ Base\ System//
hdiutil detach /Volumes/mojave/
mv ./MojaveBase.cdr.dmg ./BaseSystem.dmg
# Restore the 10.13 Installer's BaseSystem.dmg into file system and place custom BaseSystem.dmg into the root
hdiutil create -o ./Mojave.cdr -size 8965m -layout SPUD -fs HFS+J
hdiutil attach ./Mojave.cdr.dmg -noverify -mountpoint /Volumes/install_build
asr restore -source /Applications/Install\ macOS\ Mojave\.app/Contents/SharedSupport/BaseSystem.dmg -target /Volumes/install_build -noprompt -noverify -erase
cp ./BaseSystem.dmg /Volumes/macOS\ Base\ System/
hdiutil detach /Volumes/macOS\ Base\ System//
hdiutil convert ./Mojave.cdr.dmg -format UDTO -o ./Mojave.iso
mv ./Mojave.iso.cdr ~/Desktop/Mojave.iso
rm ./Mojave.cdr.dmg
