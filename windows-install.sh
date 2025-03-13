#!/bin/bash

# Calculate the free size on the current partition
free_space=$( df --block-size=1M / | awk 'NR==2 {print $4}' )

# Show a warning if there's less than 400 MB on the current partition
if [[ "$free_space" -lt 400 ]]; then
	echo "Warning, there is only $free_space MB of free space on the current / partition, so the installation will very likely fail."
	
	# Prompt the user for confirmation
	echo ""
	read -p "Do you want to continue anyway? (y/n): " choice

	# Check the user's input
	if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
		echo "Exiting ..."
		exit 0
	fi
	
fi

echo ""
echo "Refreshing the list of APT packages available ..."
apt-get update

echo ""
echo "Install update APT packages..."
apt-get upgrade -y

echo ""
echo "Cleaning APT files ..."
apt-get autoremove -y
apt-get autoclean -y
apt-get clean -y

echo ""
echo "Install necessary tools using APT ..."
apt-get install grub2 wimtools ntfs-3g parted curl wget -y

echo ""
echo "Cleaning APT files ..."
apt-get autoremove -y
apt-get autoclean -y
apt-get clean -y

# Re-calculate the free size on the current partition
free_space=$( df --block-size=1M / | awk 'NR==2 {print $4}' )

# Exit if there's less than 200 MB on the current partition
if [[ "$free_space" -lt 200 ]]; then
	echo "Error, there is only $free_space MB of free space on the current / partition, so the installation will very likely fail."
	exit 1
fi


# Define the user agent to use for download ISO files
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

# Variables for ISO download URLs (English versions)
WINDOWS_10_EN_ISO_URL="https://www.dropbox.com/scl/fi/ntcgvg59s6573f3d4pzv5/Windows.iso?rlkey=k4mjmw65c7ot9pc27tw7obo3o&dl=1"
WINDOWS_11_EN_ISO_URL=""
WINDOWS_SERVER_2019_EN_ISO_URL="https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66749/17763.3650.221105-1748.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
WINDOWS_SERVER_2022_EN_ISO_URL="https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso"

# VirtIO ISO URL
VIRTIO_STABLE_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/"

# Query the page of Virtio Stable to try to find the latest stable version to use
virtio_stable_page_content=$( curl --user-agent "$USER_AGENT" --silent --location "$VIRTIO_STABLE_URL" )

# Make sure we got a valid response
if [[ -z $virtio_stable_page_content ]]; then
	echo "Error, unable to fetch the content of the page $VIRTIO_STABLE_URL"
	exit 1
fi

# Clean the page content to only keep what we need
virtio_stable_page_content=$( echo "$virtio_stable_page_content" | tr '<>"' '\n' | grep -E "Index of|virtio-win.*\.iso$" | grep -v "virtio-win.iso" | sort | uniq | sed -E "s|.*Index of ||g" )

# Extract the path and the filename to use
virtio_stable_folders=$( echo "$virtio_stable_page_content" | grep -E "^/groups" | sed -E "s|^/||g" )
virtio_stable_filename=$( echo "$virtio_stable_page_content" | grep -E -v "^/groups" | grep -E "\.iso$" )

# Make sure we found some content
if [[ -z $virtio_stable_folders || -z $virtio_stable_filename ]]; then
	echo "Error, unable to detect the URL to use to download the latest stable version of Virtio Drivers"
	exit 1
fi

# Build the URL
VIRTIO_ISO_URL="https://fedorapeople.org/$virtio_stable_folders/$virtio_stable_filename"

# Partition sizes (in MB)
MBR_PARTITION_SIZE_MB=100       # MBR/Bootloader partition size
WINDOWS_PARTITION_SIZE_MB=30720   # Windows installation partition size (30 GB)
INSTALLER_PARTITION_SIZE_MB=10240 # Temporary installer partition size (10 GB)

# Calculate required disk size
REQUIRED_DISK_SIZE_MB=$((MBR_PARTITION_SIZE_MB + INSTALLER_PARTITION_SIZE_MB + WINDOWS_PARTITION_SIZE_MB))

echo ""

# Prompt user to select the Windows version
echo "Select the version of Windows to install:"
echo "1) Windows 10 (English)"
echo "2) Windows 11 (English)"
echo "3) Windows Server 2019 (English)"
echo "4) Windows Server 2022 (English)"
echo ""
read -p "Enter the number corresponding to your choice: " choice

# Determine the ISO URL based on user choice
case $choice in
    1)
        WINDOWS_ISO_URL="$WINDOWS_10_EN_ISO_URL"
        echo "Windows 10 (English) selected."
        ;;
    2)
        WINDOWS_ISO_URL="$WINDOWS_11_EN_ISO_URL"
        echo "Windows 11 (English) selected."
        ;;
    3)
        WINDOWS_ISO_URL="$WINDOWS_SERVER_2019_EN_ISO_URL"
        echo "Windows Server 2019 (English) selected."
        ;;
    4)
        WINDOWS_ISO_URL="$WINDOWS_SERVER_2022_EN_ISO_URL"
        echo "Windows Server 2022 (English) selected."
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""

if [[ -z "$WINDOWS_ISO_URL" ]]; then
    echo "Error: Empty ISO URL. Please verify."
    exit 1
fi

# Show the URLs we will be using
echo ""
echo "WINDOWS_ISO_URL: $WINDOWS_ISO_URL"
echo "VIRTIO_ISO_URL (latest stable): $VIRTIO_ISO_URL"

# Get the disk size in MB
disk_size_gb=$(parted /dev/sda --script print | awk '/^Disk \/dev\/sda:/ {print int($3)}')
disk_size_mb=$((disk_size_gb * 1024))

# Check if the disk is large enough
if [ "$disk_size_mb" -lt "$REQUIRED_DISK_SIZE_MB" ]; then
	echo ""
    echo "Error: The disk is too small. At least $((REQUIRED_DISK_SIZE_MB / 1024)) GB is required."
    echo "Detected disk size: $((disk_size_mb / 1024)) GB."
    exit 1
fi

# Show warning
echo ""
echo "Warning: This script will erase all partitions on /dev/sda and create a new partition table."
echo ""
read -p "Are you sure you want to continue? (y/n): " choice

# Check the user's input
if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
	echo "Exiting ..."
	exit 0
fi

echo ""
echo "Create GPT partition table ..."
parted /dev/sda --script -- mklabel gpt

echo ""
echo "Create partitions ..."
# 1. First partition: MBR/Bootloader (100 MB)
# 2. Second partition: Windows installation (25 GB)
# 3. Third partition: Temporary installer (20 GB)
parted /dev/sda --script -- mkpart primary ntfs 1MB ${MBR_PARTITION_SIZE_MB}MB
parted /dev/sda --script -- mkpart primary ntfs ${MBR_PARTITION_SIZE_MB}MB $((MBR_PARTITION_SIZE_MB + WINDOWS_PARTITION_SIZE_MB))MB
parted /dev/sda --script -- mkpart primary ntfs $((MBR_PARTITION_SIZE_MB + WINDOWS_PARTITION_SIZE_MB))MB $((MBR_PARTITION_SIZE_MB + WINDOWS_PARTITION_SIZE_MB + INSTALLER_PARTITION_SIZE_MB))MB

echo ""
echo "Sleeping 10 seconds ..."
sleep 10

echo ""
echo "Detecting partition changes (1/3) ..."
partprobe /dev/sda
echo "Sleeping 10 seconds (1/3) ..."
sleep 10
echo "Detecting partition changes (2/3) ..."
partprobe /dev/sda
echo "Sleeping 10 seconds (2/3) ..."
sleep 10
echo "Detecting partition changes (3/3) ..."
partprobe /dev/sda
echo "Sleeping 10 seconds (3/3) ..."
sleep 10

echo ""
echo "Format the partitions ..."
mkfs.ntfs -f /dev/sda1  # MBR partition
mkfs.ntfs -f /dev/sda2  # Windows installation partition
mkfs.ntfs -f /dev/sda3  # Temporary installer partition

echo ""
echo "Partitions created and formatted !"

echo ""
echo "Show the files in /mnt ..."
ls -alh /mnt

echo ""
echo "Install GRUB to the first partition (MBR/Bootloader) ..."
mkdir /mnt/grub
mount /dev/sda1 /mnt/grub
grub-install --root-directory=/mnt/grub /dev/sda

echo ""
echo "Show the files in /mnt/grub ..."
find /mnt/grub -type f

echo ""
echo "Configure GRUB to boot the Windows installer ..."
cd /mnt/grub/boot/grub
cat <<EOF > grub.cfg
menuentry "windows installer" {
    insmod ntfs
    search --no-floppy --set=root --file /bootmgr
    ntldr /bootmgr
    boot
}
EOF

echo ""
echo "Change dir back to / ..."
cd /

echo ""
echo "Show the .cfg files in /mnt/grub ..."
find /mnt/grub -type f -name "*.cfg"

echo ""
echo "Unmount the Grub folder and clean up  ..."
umount /mnt/grub
rmdir /mnt/grub

echo ""
echo "Create the folder to store the ISO files ..."
mkdir /mnt/download
mount /dev/sda2 /mnt/download

echo ""
echo "Download the Windows installer ISO ..."
wget -O /mnt/download/windows.iso --user-agent="$USER_AGENT" "$WINDOWS_ISO_URL"

echo ""
echo "Download and add VirtIO drivers ..."
wget -O /mnt/download/virtio.iso --user-agent="$USER_AGENT" "$VIRTIO_ISO_URL"

echo ""
echo "Show the files in /mnt/download ..."
ls -alh /mnt/download

echo ""
echo "Mount the installer partition in /mnt/installer ..."
mkdir /mnt/installer
mount /dev/sda3 /mnt/installer

echo ""
echo "Use the /mnt/installer dir ..."
cd /mnt/installer

echo ""
echo "Show the files in /mnt ..."
ls -alh /mnt

echo ""
echo "Show the files in /mnt/installer ..."
ls -alh /mnt/installer

echo ""
echo "Mount the Windows ISO file to the folder /mnt/installer/windows_iso ..."
mkdir /mnt/installer/windows_iso
mount -o loop /mnt/download/windows.iso /mnt/installer/windows_iso

echo ""
echo "Decompress the Windows Installer files into the /mnt/installer folder ..."
rsync -avz /mnt/installer/windows_iso/* /mnt/installer > /dev/null

echo ""
echo "Unmount the Windows ISO and clean up ..."
umount /mnt/installer/windows_iso
rmdir /mnt/installer/windows_iso
rm /mnt/download/windows.iso

echo ""
echo "Mount the VirtIO ISO file to the folder /mnt/installer/irtio_iso ..."
mkdir /mnt/installer/virtio_iso
mount -o loop /mnt/download/virtio.iso /mnt/installer/virtio_iso

echo ""
echo "Creates the folder /mnt/installer/sources/virtio to store the files ..."
mkdir /mnt/installer/sources/virtio

echo ""
echo "Decompress the VirtIO files into the /mnt/installer/sources/virtio folder ..."
rsync -avz /mnt/installer/virtio_iso/* /mnt/installer/sources/virtio > /dev/null

echo ""
echo "Unmount the VirtIO ISO and clean up ..."
umount /mnt/installer/virtio_iso
rmdir /mnt/installer/virtio_iso
rm /mnt/download/virtio.iso

echo ""
echo "Show the files in /mnt/download ..."
ls -alh /mnt/download

echo ""
echo "Delete and cleanup the download folder ..."
umount /mnt/download
rmdir /mnt/download

echo ""
echo "Show the files in /mnt/installer ..."
ls -alh /mnt/installer

echo ""
echo "Update boot.wim to include VirtIO drivers ..."
cd /mnt/installer/sources
touch cmd.txt
echo 'add virtio /virtio_drivers' >> cmd.txt
wimlib-imagex update boot.wim 2 < cmd.txt

echo ""
echo "Show the files in /mnt ..."
ls -alh /mnt

echo ""
echo "Show the files in /mnt/installer ..."
ls -alh /mnt/installer

echo ""
echo "Show some specific files in /mnt/installer ..."
find /mnt/installer -type f | grep -E "bootmgr"

echo ""
echo "Change dir back to / ..."
cd /

echo ""
echo "Unmount /mnt/installer and clean up  ..."
umount /mnt/installer
rmdir /mnt/installer

echo ""
echo "Unmount /mnt ..."
umount /mnt

echo ""
echo "Setup complete. The machine will restart in 15 seconds ..."
sleep 15
reboot
