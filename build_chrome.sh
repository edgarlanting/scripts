#!/bin/bash

# Copyright (c) 2009 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Script for building our own custom Chrome

# Load common constants.  This should be the first executable line.
# The path to common.sh should be relative to your script's location.
. "$(dirname "$0")/common.sh"

# Script must be run outside the chroot
assert_outside_chroot

# This script defaults Chrome source is in /usr/local/google/home/$USER/chrome
# You may override the Chrome source dir by passing in chrome_dir
# or with the CHROME_DIR environment variable
DEFAULT_CHROME_DIR="${CHROME_DIR:-/usr/local/google/home/$USER/chrome}"

# Flags
DEFINE_string chrome_dir "$DEFAULT_CHROME_DIR" \
  "Directory to Chrome source"
DEFINE_string mode "Release" \
  "The mode to build Chrome in (Debug or Release)"

# Parse command line
FLAGS "$@" || exit 1
eval set -- "${FLAGS_ARGV}"

# Die on error; print commands
set -e

# Convert args to paths.  Need eval to un-quote the string so that shell
# chars like ~ are processed; just doing FOO=`readlink -f $FOO` won't work.
FLAGS_chrome_dir=`eval readlink -f $FLAGS_chrome_dir`

# Build Chrome
echo Building Chrome in mode $FLAGS_mode
export GYP_DEFINES=chromeos=1
CHROME_DIR=$FLAGS_chrome_dir
cd "$CHROME_DIR/src/build"
gclient runhooks --force
hammer --implicit-deps-changed --mode=$FLAGS_mode chrome

# Zip into chrome-chromeos.zip and put in local_assets
BUILD_DIR="$CHROME_DIR/src/sconsbuild"
CHROME_LINUX_DIR="$BUILD_DIR/chrome-chromeos"
OUTPUT_DIR="${SRC_ROOT}/build/x86/local_assets"
OUTPUT_ZIP="$BUILD_DIR/chrome-chromeos.zip"
if [ -n "$OUTPUT_DIR" ]
then
  mkdir -p $OUTPUT_DIR
fi
# create symlink so that we can create the zip file with prefix chrome-chromeos
rm -f $CHROME_LINUX_DIR
ln -s $BUILD_DIR/$FLAGS_mode $CHROME_LINUX_DIR

echo Zipping $CHROME_LINUX_DIR to $OUTPUT_ZIP
cd $BUILD_DIR
rm -f $OUTPUT_ZIP
zip -r9 $OUTPUT_ZIP chrome-chromeos -x "chrome-chromeos/lib/*" \
  "chrome-chromeos/obj/*" "chrome-chromeos/mksnapshot" "chrome-chromeos/protoc"
cp -f $OUTPUT_ZIP $OUTPUT_DIR
echo Done.
