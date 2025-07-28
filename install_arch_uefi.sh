#!/bin/bash
set -e

echo -e "\e[1;32m--- Установка Arch Linux (UEFI/GPT) ---\e[0m"

# Проверка UEFI
if [ ! -d "/sys/firmware/efi/efivars" ]; then
    echo "Ошибка: Система не загружена в UEFI режиме!"
    echo "Используйте install_arch.sh для BIOS систем"
    exit 1
fi

# Ввод данных
read -p "Укажи диск для установки (например: /dev/sda): " DISK
read -p "Имя хоста (hostname): " HOSTNAME
read -p "Имя пользователя: " USERNAME
read -s -p "Пароль для пользователя $USERNAME: " USERPASS
echo
read -s -p "Пароль для root: " ROOTPASS
echo

# Проверка существования диска
if [ ! -b "$DISK" ]; then
  echo "Ошибка: диск $DISK не найден"
  exit 1
fi

# Проверка размера диска
DISK_SIZE=$(lsblk -b -n -o SIZE "$DISK" | head -1)
MIN_SIZE=$((10*1024*1024*1024)) # 10GB для UEFI
if [ "$DISK_SIZE" -lt "$MIN_SIZE" ]; then
  echo "Ошибка: диск слишком мал (минимум 10GB для UEFI)"
  exit 1
fi

# Подтверждение
echo -e "\e[1;33mВНИМАНИЕ: Все данные на диске $DISK будут удалены!\e[0m"
read -p "Продолжить? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Установка отменена"
  exit 0
fi

echo -e "\e[1;34m[*] Подготовка диска $DISK (GPT разметка)...\e[0m"
wipefs -af "$DISK"

# GPT разметка для UEFI
parted "$DISK" --script mklabel gpt \
 mkpart primary fat32 1MiB 513MiB \
 set 1 esp on \
 mkpart primary linux-swap 513MiB 2561MiB \
 mkpart primary ext4 2561MiB 100%

# Обновляем таблицу разделов
partprobe "$DISK"
sleep 3

# Определяем имена разделов
if [[ "$DISK" == *"nvme"* ]]; then
  EFI_PART="${DISK}p1"
  SWAP_PART="${DISK}p2"
  ROOT_PART="${DISK}p3"
else
  EFI_PART="${DISK}1"
  SWAP_PART="${DISK}2"
  ROOT_PART="${DISK}3"
fi

# Форматируем разделы
echo -e "\e[1;34m[*] Форматирование разделов...\e[0m"
mkfs.fat -F32 "$EFI_PART"
mkswap "$SWAP_PART"
mkfs.ext4 -F "$ROOT_PART"

# Монтируем разделы
echo -e "\e[1;34m[*] Монтирование разделов...\e[0m"
mount "$ROOT_PART" /mnt
mkdir /mnt/boot
mount "$EFI_PART" /mnt/boot
swapon "$SWAP_PART"

echo -e "\e[1;34m[*] Установка базовой системы...\e[0m"
pacstrap -K /mnt base base-devel linux linux-firmware \
         grub efibootmgr networkmanager vim nano sudo \
         git wget curl htop tree bash-completion man-db man-pages \
         openssh firefox chromium libreoffice-fresh gimp vlc

echo -e "\e[1;34m[*] Генерация fstab...\e[0m"
genfstab -U /mnt >> /mnt/etc/fstab

echo -e "\e[1;34m[*] Создание скрипта настройки...\e[0m"
cat > /mnt/install.sh << 'SCRIPT_END'
#!/bin/bash
set -e

HOSTNAME="$1"
USERNAME="$2"
USERPASS="$3"
ROOTPASS="$4"
DISK="$5"

# Настройка времени и локали
ln -sf /usr/share/zoneinfo/Asia/Dushanbe /etc/localtime
hwclock --systohc

sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/#ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname

# Hosts
cat >> /etc/hosts << 'HOST_END'
127.0.0.1   localhost
::1         localhost
HOST_END
echo "127.0.1.1   $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Пользователи
echo "root:$ROOTPASS" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USERPASS" | chpasswd

# Sudo
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Сервисы
systemctl enable NetworkManager
systemctl enable sshd

# GRUB для UEFI
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo -e "\e[1;32m[*] UEFI система настроена!\e[0m"
SCRIPT_END

chmod +x /mnt/install.sh

echo -e "\e[1;34m[*] Выполнение настройки в chroot...\e[0m"
arch-chroot /mnt /install.sh "$HOSTNAME" "$USERNAME" "$USERPASS" "$ROOTPASS" "$DISK"

#