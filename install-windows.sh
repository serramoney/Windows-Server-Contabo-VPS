#!/bin/bash
#
# ESEMPIO di script per installare Windows su disco MBR (msdos)
# con BIOS Legacy. Crea 3 partizioni NTFS e installa GRUB in /dev/sda.
#

# ------------------------
# 1) AGGIORNA SISTEMA E STRUMENTI
# ------------------------
apt-get update -y
apt-get upgrade -y

# Installa i pacchetti necessari
apt-get install grub-pc parted wimtools ntfs-3g curl wget -y

# ------------------------
# 2) DEFINISCI ALCUNE VARIABILI
# ------------------------
# Dimensioni in MB per le partizioni
MBR_PARTITION_SIZE_MB=100       # Prima partizione (bootloader) ~100 MB
WINDOWS_PARTITION_SIZE_MB=30720 # Seconda partizione ~30 GB
INSTALLER_PARTITION_SIZE_MB=10240 # Terza partizione ~10 GB

# URL ISO Windows
#WINDOWS_SERVER_2019_EN_ISO_URL="https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66749/17763.3650.221105-1748.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
#WINDOWS_SERVER_2022_EN_ISO_URL="https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso"
WINDOWS_ISO_URL="https://www.dropbox.com/scl/fi/ntcgvg59s6573f3d4pzv5/Windows.iso?rlkey=k4mjmw65c7ot9pc27tw7obo3o&dl=1"

# URL ISO VirtIO (esempio stable)
VIRTIO_ISO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

# ------------------------
# 3) CREAZIONE PARTIZIONI IN MBR
# ------------------------
echo "Attenzione: verranno cancellate tutte le partizioni su /dev/sda!"
sleep 5

# Crea etichetta MBR (msdos)
parted /dev/sda --script mklabel msdos

# Crea 3 partizioni primarie
parted /dev/sda --script mkpart primary ntfs 1MiB $((1 + MBR_PARTITION_SIZE_MB))MiB
parted /dev/sda --script mkpart primary ntfs $((1 + MBR_PARTITION_SIZE_MB))MiB $((1 + MBR_PARTITION_SIZE_MB + WINDOWS_PARTITION_SIZE_MB))MiB
parted /dev/sda --script mkpart primary ntfs $((1 + MBR_PARTITION_SIZE_MB + WINDOWS_PARTITION_SIZE_MB))MiB $((1 + MBR_PARTITION_SIZE_MB + WINDOWS_PARTITION_SIZE_MB + INSTALLER_PARTITION_SIZE_MB))MiB

# Imposta il flag di boot sulla prima partizione (dove installeremo GRUB)
parted /dev/sda --script set 1 boot on

# Aggiorna la tabella partizioni e attendi un po'
partprobe /dev/sda
sleep 10
partprobe /dev/sda
sleep 10

# Formatta in NTFS
mkfs.ntfs -f /dev/sda1
mkfs.ntfs -f /dev/sda2
mkfs.ntfs -f /dev/sda3

echo "Partizioni create e formattate (MBR + NTFS)."

# ------------------------
# 4) INSTALLAZIONE GRUB (BIOS LEGACY) SU /dev/sda
# ------------------------
mkdir -p /mnt/bootpart
mount /dev/sda1 /mnt/bootpart

# Installa GRUB in modalità i386-pc (BIOS)
grub-install --target=i386-pc --boot-directory=/mnt/bootpart/boot /dev/sda

# Crea un file di configurazione base
cat <<EOF > /mnt/bootpart/boot/grub/grub.cfg
menuentry "Windows Installer" {
    insmod ntfs
    search --no-floppy --set=root --file /bootmgr
    ntldr /bootmgr
    boot
}
EOF

umount /mnt/bootpart
rmdir /mnt/bootpart

echo "GRUB (BIOS) installato correttamente su /dev/sda."

# ------------------------
# 5) SCARICA ISO WINDOWS E VIRTIO
# ------------------------
mkdir -p /mnt/windows
mount /dev/sda2 /mnt/windows

echo "Scarico ISO Windows..."
wget -O /mnt/windows/windows.iso --user-agent="$USER_AGENT" "$WINDOWS_ISO_URL"

echo "Scarico ISO VirtIO..."
wget -O /mnt/windows/virtio.iso --user-agent="$USER_AGENT" "$VIRTIO_ISO_URL"

ls -alh /mnt/windows

# ------------------------
# 6) COPIA FILE NELLA PARTIZIONE INSTALLER
# ------------------------
mkdir -p /mnt/installer
mount /dev/sda3 /mnt/installer

# Monta l'ISO di Windows e copia i file
mkdir /mnt/installer/winiso
mount -o loop /mnt/windows/windows.iso /mnt/installer/winiso

rsync -av /mnt/installer/winiso/ /mnt/installer/
umount /mnt/installer/winiso
rmdir /mnt/installer/winiso
rm /mnt/windows/windows.iso

# Monta l'ISO VirtIO e copia i driver
mkdir /mnt/installer/virtioiso
mount -o loop /mnt/windows/virtio.iso /mnt/installer/virtioiso

mkdir -p /mnt/installer/sources/virtio
rsync -av /mnt/installer/virtioiso/ /mnt/installer/sources/virtio/
umount /mnt/installer/virtioiso
rmdir /mnt/installer/virtioiso
rm /mnt/windows/virtio.iso

# ------------------------
# 7) AGGIORNA boot.wim PER AGGIUNGERE I DRIVER VIRTIO
# ------------------------
cd /mnt/installer/sources
echo 'add virtio /virtio_drivers' > cmd.txt
wimlib-imagex update boot.wim 2 < cmd.txt
rm cmd.txt

# ------------------------
# 8) PULIZIA E RIAVVIO
# ------------------------
cd /
umount /mnt/installer
umount /mnt/windows
rmdir /mnt/installer
rmdir /mnt/windows

echo "Installazione completata. Riavvio tra 10 secondi..."
sleep 10
reboot
