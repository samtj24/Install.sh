#!/bin/bash
set -e
echo -e "\e[1;32m--- Установка Arch Linux (BIOS, для старого ноутбука) ---\e[0m"

# Ввод данных
read -r -p "Укажи диск для установки (например: /dev/sda): " DISK
read -r -p "Имя хоста (hostname): " HOSTNAME
read -r -p "Имя пользователя: " USERNAME
read -r -s -p "Пароль для пользователя $USERNAME: " USERPASS
echo
read -r -s -p "Пароль для root: " ROOTPASS
echo

# Проверка существования диска
if [ ! -b "$DISK" ]; then
  echo "Ошибка: диск $DISK не найден"
  exit 1
fi

# Проверка размера диска (минимум 8GB)
DISK_SIZE=$(lsblk -b -n -o SIZE "$DISK" | head -1)
MIN_SIZE=$((8*1024*1024*1024)) # 8GB в байтах
if [ "$DISK_SIZE" -lt "$MIN_SIZE" ]; then
  echo "Ошибка: диск слишком мал (минимум 8GB)"
  exit 1
fi

# Подтверждение установки
echo -e "\e[1;33mВНИМАНИЕ: Все данные на диске $DISK будут удалены!\e[0m"
read -r -p "Продолжить? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Установка отменена"
  exit 0
fi

echo -e "\e[1;34m[*] Подготовка диска $DISK...\e[0m"
wipefs -af "$DISK"

# Создаем разделы: swap (2GB) + root (остальное место)
SWAP_SIZE="2GiB"
parted "$DISK" --script mklabel msdos \
 mkpart primary linux-swap 1MiB ${SWAP_SIZE} \
 mkpart primary ext4 ${SWAP_SIZE} 100% \
 set 2 boot on

# Обновляем таблицу разделов и ждем
partprobe "$DISK"
sleep 3

# Определяем имена разделов (для nvme и обычных дисков)
if [[ "$DISK" == *"nvme"* ]]; then
  SWAP_PART="${DISK}p1"
  ROOT_PART="${DISK}p2"
else
  SWAP_PART="${DISK}1"
  ROOT_PART="${DISK}2"
fi

# Форматируем разделы
echo -e "\e[1;34m[*] Форматирование разделов...\e[0m"
mkswap "$SWAP_PART"
mkfs.ext4 -F "$ROOT_PART"

echo -e "\e[1;34m[*] Монтирование разделов...\e[0m"
mount "$ROOT_PART" /mnt
swapon "$SWAP_PART"

echo -e "\e[1;34m[*] Установка базовой системы и пакетов...\e[0m"
pacstrap -K /mnt base base-devel linux linux-firmware grub vim nano networkmanager \
             sudo git wget curl htop tree unzip zip bash-completion man-db man-pages \
             openssh firefox chromium libreoffice-fresh gimp vlc

echo -e "\e[1;34m[*] Генерация fstab...\e[0m"
genfstab -U /mnt >> /mnt/etc/fstab

echo -e "\e[1;34m[*] Создание скрипта настройки системы внутри chroot...\e[0m"

# Создаем скрипт с передачей переменных через аргументы
cat > /mnt/install.sh << 'SCRIPT_END'
#!/bin/bash
set -e

# Получаем переменные из аргументов
HOSTNAME="$1"
USERNAME="$2"
USERPASS="$3"
ROOTPASS="$4"
DISK="$5"

# Настройка хоста и времени
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/Asia/Dushanbe /etc/localtime
hwclock --systohc

# Настройка локали
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/#ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Настройка пользователей
echo "root:$ROOTPASS" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USERPASS" | chpasswd

# Включаем sudo для группы wheel
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Настройка /etc/hosts
cat >> /etc/hosts << 'HOST_END'
127.0.0.1   localhost
::1         localhost
HOST_END
echo "127.0.1.1   $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Включаем сервисы
systemctl enable NetworkManager
systemctl enable sshd

# Установка загрузчика
grub-install --target=i386-pc "$DISK"
grub-mkconfig -o /boot/grub/grub.cfg

echo -e "\e[1;32m[*] Настройка системы завершена!\e[0m"
SCRIPT_END

chmod +x /mnt/install.sh

echo -e "\e[1;34m[*] Выполнение настроечного скрипта в chroot...\e[0m"
arch-chroot /mnt /install.sh "$HOSTNAME" "$USERNAME" "$USERPASS" "$ROOTPASS" "$DISK"

# Создаем файл с полезными командами для нового пользователя
cat > /mnt/home/"$USERNAME"/first_steps.txt << 'STEPS_END'
=== Полезные команды после первой загрузки ===

1. Обновить систему:
   sudo pacman -Syu

2. Установить AUR helper (yay):
   git clone https://aur.archlinux.org/yay.git
   cd yay && makepkg -si

3. Настроить Git:
   git config --global user.name "Ваше Имя"
   git config --global user.email "your@email.com"

4. Установить дополнительные драйверы:
   sudo pacman -S xf86-video-intel    # для Intel графики
   sudo pacman -S xf86-video-amd      # для AMD графики
   sudo pacman -S nvidia              # для NVIDIA графики

5. Установить рабочее окружение:
   sudo pacman -S xorg plasma-desktop sddm
   sudo systemctl enable sddm

6. Подключиться к Wi-Fi:
   nmcli device wifi list
   nmcli device wifi connect "SSID" password "пароль"

Этот файл можно удалить после ознакомления.
STEPS_END

chown "$USERNAME":"$USERNAME" /mnt/home/"$USERNAME"/first_steps.txt

rm /mnt/install.sh

echo -e "\e[1;34m[*] Отключение swap и отмонтирование разделов...\e[0m"
swapoff "$SWAP_PART"
umount -R /mnt

echo -e "\e[1;32m✅ Установка завершена!\e[0m"
echo -e "\e[1;36mЧто установлено:\e[0m"
echo "• Базовая система с дополнительными пакетами"
echo "• Пользователь $USERNAME с правами sudo"
echo "• Swap раздел 2GB"
echo "• SSH сервер (включен)"
echo "• Браузеры: Firefox, Chromium"
echo "• Офис: LibreOffice"
echo "• Мультимедиа: GIMP, VLC"
echo "• Системные утилиты: htop, tree, git и др."
echo ""
echo -e "\e[1;33mПерезагрузи компьютер и не забудь извлечь установочный носитель.\e[0m"
echo -e "\e[1;36mПосле загрузки посмотри файл ~/first_steps.txt для дальнейших шагов.\e[0m"
