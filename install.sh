#!/bin/bash
#
# Install git-release.
#
# The download goes to a temp file that is then renamed into place. `curl -o`
# onto the live path truncates and rewrites the same inode, which corrupts the
# script if a copy is currently running — see `function upgrade` in git-release.
#
# Overrides:
#   GIT_RELEASE_UPGRADE_URL   where to fetch from (default: GitHub main)
#   GIT_RELEASE_INSTALL_PATH  where to install    (default: ~/bin/git-release)

set -u

UPGRADE_URL=${GIT_RELEASE_UPGRADE_URL:-https://raw.githubusercontent.com/neverbehind/git-release/main/git-release}
INSTALL_PATH=${GIT_RELEASE_INSTALL_PATH:-$HOME/bin/git-release}
INSTALL_DIR=$(dirname "$INSTALL_PATH")

mkdir -p "$INSTALL_DIR" || exit 1

TMP_PATH="$INSTALL_DIR/.git-release.install.$$"
trap 'rm -f "$TMP_PATH"' EXIT

# -f so an HTTP error is a failure rather than a 404 page written over the tool.
if ! curl -fsSL "$UPGRADE_URL" -o "$TMP_PATH"
then
	echo "ERROR: download failed from $UPGRADE_URL" >&2
	exit 1
fi

if [ ! -s "$TMP_PATH" ] || ! bash -n "$TMP_PATH" 2>/dev/null
then
	echo "ERROR: the downloaded file is empty or not valid bash. Nothing was installed." >&2
	exit 1
fi

chmod +x "$TMP_PATH"
mv -f "$TMP_PATH" "$INSTALL_PATH" || exit 1
echo "Installed $INSTALL_PATH"

# Put the install directory on PATH — once. Re-running the installer used to
# append another PATH line every time.
case "$SHELL" in
	*/zsh)  PROFILE="$HOME/.zshrc" ;;
	*/bash) PROFILE="$HOME/.bashrc" ;;
	*)      PROFILE="" ;;
esac

if [ -n "$PROFILE" ]
then
	touch "$PROFILE"
	TILDE_DIR=${INSTALL_DIR/#$HOME/\~}
	if grep -qF "$INSTALL_DIR" "$PROFILE" || grep -qF "$TILDE_DIR" "$PROFILE"
	then
		echo "$INSTALL_DIR is already on PATH in $PROFILE"
	else
		printf '\nexport PATH="%s:$PATH"\n' "$INSTALL_DIR" >> "$PROFILE"
		echo "Added $INSTALL_DIR to PATH in $PROFILE"
	fi
	# Sourcing a profile from here cannot affect the shell that invoked us.
	echo "Open a new shell (or run: source $PROFILE) to pick it up."
fi
