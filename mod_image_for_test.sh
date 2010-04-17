#!/bin/bash

# Copyright (c) 2009 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Script to modify a keyfob-based chromeos system image for testability.

# Load common constants.  This should be the first executable line.
# The path to common.sh should be relative to your script's location.
. "$(dirname "$0")/common.sh"

# Load functions and constants for chromeos-install
. "$(dirname "$0")/chromeos-common.sh"

get_default_board

DEFINE_string board "$DEFAULT_BOARD" "Board for which the image was built"
DEFINE_string qualdb "/tmp/run_remote_tests.*" \
    "Location of qualified component file"
DEFINE_string image "" "Location of the rootfs raw image file"
DEFINE_boolean factory $FLAGS_FALSE "Modify the image for manufacturing testing"
DEFINE_boolean yes $FLAGS_FALSE "Answer yes to all prompts" "y"

# Parse command line
FLAGS "$@" || exit 1
eval set -- "${FLAGS_ARGV}"

# No board, no default and no image set then we can't find the image
if [ -z $FLAGS_image ] && [ -z $FLAGS_board ] ; then
  setup_board_warning
  echo "*** mod_image_for_test failed.  No board set and no image set"
  exit 1
fi

# We have a board name but no image set.  Use image at default location
if [ -z $FLAGS_image ] ; then
  IMAGES_DIR="${DEFAULT_BUILD_ROOT}/images/${FLAGS_board}"
  FILENAME="chromiumos_image.bin"
  FLAGS_image="${IMAGES_DIR}/$(ls -t $IMAGES_DIR 2>&-| head -1)/${FILENAME}"
fi

# Abort early if we can't find the image
if [ ! -f $FLAGS_image ] ; then
  echo "No image found at $FLAGS_image"
  exit 1
fi

# Make sure anything mounted in the rootfs is cleaned up ok on exit.
cleanup_rootfs_mounts() {
  # Occasionally there are some daemons left hanging around that have our
  # root image file system open. We do a best effort attempt to kill them.
  PIDS=`sudo lsof -t "${ROOT_FS_DIR}" | sort | uniq`
  for pid in ${PIDS}
  do
    local cmdline=`cat /proc/$pid/cmdline`
    echo "Killing process that has open file on our rootfs: $cmdline"
    sudo kill $pid || /bin/true
  done
}

cleanup_rootfs_loop() {
  sudo umount "${LOOP_DEV}"
  sleep 1  # in case $LOOP_DEV is in use
  sudo losetup -d "${LOOP_DEV}"
}

cleanup() {
  # Disable die on error.
  set +e

  cleanup_rootfs_mounts
  if [ -n "${LOOP_DEV}" ]
  then
    cleanup_rootfs_loop
  fi

  rmdir "${ROOT_FS_DIR}"

  # Turn die on error back on.
  set -e
}

# main process begins here.

# Make sure this is really what the user wants, before nuking the device
if [ $FLAGS_yes -ne $FLAGS_TRUE ]; then
  read -p "Modifying image ${FLAGS_image} for test; are you sure (y/N)? " SURE
  SURE="${SURE:0:1}" # Get just the first character
  if [ "$SURE" != "y" ]; then
    echo "Ok, better safe than sorry."
    exit 1
  fi
else
  echo "Modifying image ${FLAGS_image} for test..."
fi

set -e

ROOT_FS_DIR=$(dirname "${FLAGS_image}")/rootfs
mkdir -p "${ROOT_FS_DIR}"

trap cleanup EXIT

# Figure out how to loop mount the rootfs partition. It should be partition 3
# on the disk image.
offset=$(partoffset "${FLAGS_image}" 3)

LOOP_DEV=$(sudo losetup -f)
if [ -z "$LOOP_DEV" ]; then
  echo "No free loop device"
  exit 1
fi
sudo losetup -o $(( $offset * 512 )) "${LOOP_DEV}" "${FLAGS_image}"
sudo mount "${LOOP_DEV}" "${ROOT_FS_DIR}"

MOD_SCRIPTS_ROOT="${GCLIENT_ROOT}/src/scripts/mod_for_test_scripts"
# Run test setup script inside chroot jail to modify the image
sudo GCLIENT_ROOT="${GCLIENT_ROOT}" ROOT_FS_DIR="${ROOT_FS_DIR}" \
    "${MOD_SCRIPTS_ROOT}/test_setup.sh"

# Run manufacturing test setup
if [ ${FLAGS_factory} -eq ${FLAGS_TRUE} ]; then
  echo "Modifying image ${FLAGS_image} for manufacturing test..."

  echo "Disabling ui.conf, don't do chrome startup on boot."
  sudo mv ${ROOT_FS_DIR}/etc/init/ui.conf \
      ${ROOT_FS_DIR}/etc/init/ui.conf.disabled

  echo "Applying patch to init scripts"
  MOD_MFG_ROOT="${GCLIENT_ROOT}/src/scripts/mod_for_factory_scripts"
  pushd ${ROOT_FS_DIR}
  sudo patch -d ${ROOT_FS_DIR} -p1 < ${MOD_MFG_ROOT}/factory.patch
  popd

  echo "Modifying Release Description for Factory."
  FILE="${ROOT_FS_DIR}/etc/lsb-release"
  sudo sed -i 's/Test/Factory/' $FILE

  echo "Done applying patch."

  # Try to use the sytem component file in the most recent autotest result
  FLAGS_qualdb=$(ls -dt ${FLAGS_qualdb} 2>&-| head -1)

  # Try to append the full path to the file if FLAGS_qualdb is a directory
  if [ ! -z ${FLAGS_qualdb} ] && [ -d ${FLAGS_qualdb} ]; then
    # TODO(waihong): Handle multiple results to deliver to multiple images
    FLAGS_qualdb="${FLAGS_qualdb}/hardware_Components,*"
    FLAGS_qualdb=$(ls -dt ${FLAGS_qualdb} 2>&-| head -1)
    FLAGS_qualdb="${FLAGS_qualdb}/hardware_Components/results/system_components"
  fi

  if [ ! -z ${FLAGS_qualdb} ] && [ -f ${FLAGS_qualdb} ]; then
    # Copy the qualified component file to the image
    echo "Copying ${FLAGS_qualdb} to the image."
    sudo mkdir -p ${ROOT_FS_DIR}/usr/local/manufacturing
    sudo cp -f ${FLAGS_qualdb} \
      ${ROOT_FS_DIR}/usr/local/manufacturing/qualified_components
  else
    echo "No qualified component file found at: ${FLAGS_qualdb}"
  fi
fi

cleanup
trap - EXIT

