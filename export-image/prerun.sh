#!/bin/bash -e

IMG_FILE="${STAGE_WORK_DIR}/${IMG_DATE}-${IMG_NAME}${IMG_SUFFIX}.img"

unmount_image "${IMG_FILE}"

rm -f "${IMG_FILE}"

rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

# Partition sizes in MB
BOOT_SIZE=64
ROOT_SIZE=1728
DATA_SIZE=250

# calc values for fdisk
BOOT_START=2048
BOOT_SIZE_CALC=$((BOOT_SIZE * 1024 * 2))
ROOT_START_CALC=$((BOOT_SIZE_CALC + 2048))
ROOT_SIZE_CALC=$((ROOT_SIZE * 1024 * 2))
DATA_START_CALC=$((BOOT_SIZE_CALC + ROOT_SIZE_CALC + 2048))
DATA_SIZE_CALC=$((DATA_SIZE * 1024 * 2))

# Image size in MB
IMG_SIZE=$((BOOT_SIZE + ROOT_SIZE + DATA_SIZE))

fallocate -l ${IMG_SIZE}M "${IMG_FILE}"

fdisk "${IMG_FILE}" <<EOF
o
n
p
1
${BOOT_START}
+${BOOT_SIZE}M
n
p
2
${ROOT_START_CALC}
+${ROOT_SIZE}M
n
p
3
${DATA_START_CALC}
+$((DATA_SIZE - 2))M
t
1
b
w
EOF

PARTED_OUT=$(parted -s "${IMG_FILE}" unit b print)
BOOT_OFFSET=$(echo "$PARTED_OUT" | grep -e '^ 1'| xargs echo -n \
| cut -d" " -f 2 | tr -d B)
BOOT_LENGTH=$(echo "$PARTED_OUT" | grep -e '^ 1'| xargs echo -n \
| cut -d" " -f 4 | tr -d B)

ROOT_OFFSET=$(echo "$PARTED_OUT" | grep -e '^ 2'| xargs echo -n \
| cut -d" " -f 2 | tr -d B)
ROOT_LENGTH=$(echo "$PARTED_OUT" | grep -e '^ 2'| xargs echo -n \
| cut -d" " -f 4 | tr -d B)

DATA_OFFSET=$(echo "$PARTED_OUT" | grep -e '^ 3'| xargs echo -n \
| cut -d" " -f 2 | tr -d B)
DATA_LENGTH=$(echo "$PARTED_OUT" | grep -e '^ 3'| xargs echo -n \
| cut -d" " -f 4 | tr -d B)

BOOT_DEV=$(losetup --show -f -o "${BOOT_OFFSET}" --sizelimit "${BOOT_LENGTH}" "${IMG_FILE}")
ROOT_DEV=$(losetup --show -f -o "${ROOT_OFFSET}" --sizelimit "${ROOT_LENGTH}" "${IMG_FILE}")
DATA_DEV=$(losetup --show -f -o "${DATA_OFFSET}" --sizelimit "${DATA_LENGTH}" "${IMG_FILE}")
echo "/boot:    offset $BOOT_OFFSET, length $BOOT_LENGTH"
echo "/:        offset $ROOT_OFFSET, length $ROOT_LENGTH"
echo "/storage: offset $DATA_OFFSET, length $DATA_LENGTH"

ROOT_FEATURES="^huge_file"
for FEATURE in metadata_csum 64bit; do
	if grep -q "$FEATURE" /etc/mke2fs.conf; then
	    ROOT_FEATURES="^$FEATURE,$ROOT_FEATURES"
	fi
done
mkdosfs -n BOOT -F 32 -v "$BOOT_DEV" > /dev/null
mkfs.ext4 -L rootfs -O "$ROOT_FEATURES" "$ROOT_DEV" > /dev/null
mkfs.ext4 -L storage -O "$ROOT_FEATURES" "$DATA_DEV" > /dev/null

mount -v "$ROOT_DEV" "${ROOTFS_DIR}" -t ext4
mkdir -p "${ROOTFS_DIR}/boot"
mount -v "$BOOT_DEV" "${ROOTFS_DIR}/boot" -t vfat

rsync -aHAXx --exclude var/cache/apt/archives --exclude boot "${EXPORT_ROOTFS_DIR}/" "${ROOTFS_DIR}/"
cp -r "${EXPORT_ROOTFS_DIR}/boot/." "${ROOTFS_DIR}/boot/"
