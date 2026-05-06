#!/bin/sh
# Drop-in profile snippet so /usr/local/bin (where the bratan-pacman wrapper
# lives) is searched before /usr/bin even in non-login shells and sudo.
#
# Most distros ship /usr/local/bin first by default, but on minimal Arch
# images PATH is built up by /etc/profile + shell rc files only — make
# sure interactive shells get the wrapper.
case ":$PATH:" in
    *":/usr/local/bin:"*) ;;
    *) PATH="/usr/local/bin:$PATH" ;;
esac
export PATH
