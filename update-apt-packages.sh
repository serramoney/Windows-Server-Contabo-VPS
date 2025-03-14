#!/bin/bash

# Detect the OS name
os_name=$( cat /etc/os-release | grep -E "^NAME" | sed -e "s|^NAME=||g" | tr -d '"' | awk '{print tolower($1)}' )

# Detect the OS Version
os_codename=$( cat /etc/os-release | grep -E "^VERSION_CODENAME" | sed -e "s|^VERSION_CODENAME=||g" | tr -d '"' | awk '{print tolower($1)}' )

echo "os_name: $os_name"
echo "os_codename: $os_codename"
echo ""

# Check the OS, and show a warning if it's not officialy supported
if [[ "$os_codename" != "buster" && "$os_codename" != "bookworm" ]]; then
	echo ""
	echo "Warning, this script was made for Debian buster or Debian bookworm."
	
	# Prompt the user for confirmation
	echo ""
	read -p "Do you want to continue anyway ? (y/n): " choice

	# Check the user's input
	if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
		echo "Exiting ..."
		exit 0
	fi

fi

if [[ "$os_codename" == "buster" ]]; then
    echo ""
    echo "Recreating the file /etc/apt/sources.list for $os_codename ..."
    echo "deb http://deb.debian.org/debian $os_codename main contrib non-free" > /etc/apt/sources.list
    echo "deb http://deb.debian.org/debian $os_codename-updates main contrib non-free" >> /etc/apt/sources.list
    echo "deb http://security.debian.org/debian-security/ $os_codename/updates main contrib non-free" >> /etc/apt/sources.list
fi

if [[ "$os_codename" == "bookworm" ]]; then
    echo ""
    echo "Recreating the file /etc/apt/sources.list for $os_codename ..."
    echo "deb http://deb.debian.org/debian $os_codename contrib main non-free-firmware" > /etc/apt/sources.list
    echo "deb http://deb.debian.org/debian $os_codename-updates contrib main non-free-firmware" >> /etc/apt/sources.list
    echo "deb http://deb.debian.org/debian $os_codename-backports contrib main non-free-firmware" >> /etc/apt/sources.list
    echo "deb http://deb.debian.org/debian-security $os_codename-security contrib main non-free-firmware" >> /etc/apt/sources.list
fi

echo ""
echo "Refreshing the list of APT packages available ..."
apt-get update

echo ""
echo "Cleaning APT files ..."
apt-get clean -y
apt-get autoclean -y
apt-get autoremove -y

# Calculate the free size on the current / partition
free_space=$( df --block-size=1M / | awk 'NR==2 {print $4}' )

echo ""
echo "Free space on the main partition: $free_space MB"

# Prompt the user for confirmation
echo ""
read -p "Do you want to continue? (y/n): " choice

# Check the user's input
if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
	echo "Exiting ..."
	exit 0
fi

# Check if we need to update the kernel packages
if [[ ! -z $( apt-get upgrade --simulate | grep "linux-image-amd64" ) ]]; then

	echo ""
	echo "A kernel update seems to be available."
	
	# Prompt the user for confirmation
	echo ""
	read -p "Do you want to update the kernel ? (y/n): " choice

	# Check the user's input
	if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
		echo ""
		echo "Updating Linux Kernel ..."
		apt-get install -y linux-headers-amd64 linux-image-amd64
		echo ""
		echo "Cleaning APT files ..."
		apt-get clean -y
		apt-get autoclean -y
		apt-get autoremove -y
	else
		echo ""
		echo "Skipping kernel update."
	fi
fi

echo ""
echo "Updating APT packages ..."
apt-get upgrade -y

echo ""
echo "Cleaning APT files ..."
apt-get clean -y
apt-get autoclean -y
apt-get autoremove -y

# Calculate the free size on the current / partition
free_space=$( df --block-size=1M / | awk 'NR==2 {print $4}' )

echo "Free space on the main partition: $free_space MB"

# Exit if there's less than 300 MB on the current partition
if [[ "$free_space" -lt 300 ]]; then
	echo "Warning, there is only $free_space MB of free space on the current / partition, so the installation will very likely fail."
fi

echo ""
echo "End of the APT script."
echo ""
