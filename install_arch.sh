#!/bin/bash
set -euo pipefail

# Цвета для сообщений
COLOR_RESET="\e[0m"
COLOR_RED="\e[1;31m"
COLOR_GREEN="\e[1;32m"
COLOR_YELLOW="\e[1;33m"
COLOR_BLUE="\e[1;34m"

info()    { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"; }
success() { echo -e "${COLOR_GREEN}[ОК]${COLOR_RESET} $*"; }
warn()    { echo -e "${COLOR_YELLOW}[ВНИМАНИЕ]${COLOR_RESET} $*"; }
error()   { echo -e "${COLOR_RED}[ОШИБКА]${COLOR_RESET} $*" >&2; exit 1; }

# Обработка Ctrl+C
trap 'echo -e "\n${COLOR_YELLOW}[ПРЕРВАНО]${COLOR_RESET} Установка отменена пользователем."; exit 130' INT

# Проверка запуска от root
if [[ $EUID -ne 0 ]]; then
    error "Пожалуйста, запустите скрипт с правами root (sudo)"
fi

# Проверка необходимых команд
REQUIRED_CMDS=(parted mkfs.ext4 mkswap lsblk wipefs mount umount swapon pacstrap genfstab arch-chroot grub-install grub-mkconfig useradd passwd)
for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || error "Не найдена команда $cmd. Установите её."
done

# Логирование в файл
exec > >(tee -i install.log)
exec 2>&1

ask() {
    local prompt="$1"
    local var
    read -rp "$prompt" var
    echo "$var"
}

ask_secret() {
    local prompt="$1"
    local var
    read -srp "$prompt" var
    echo
    echo "$var"
}

main() {
    echo -e "${COLOR_GREEN}--- Установка Arch Linux (BIOS/MBR, автоматизация) ---${COLOR_RESET}"

    # Ввод основных данных
    DISK=$(ask "Укажите диск для установки (например: /dev/sda): ")
    [[ -b "$DISK" ]] || error "Диск $DISK не найден"
    HOSTNAME=$(ask "Имя хоста (hostname): ")
    USERNAME=$(ask "Имя пользователя: ")
    while :; do
        USERPASS=$(ask_secret "Пароль для пользователя $USERNAME: ")
        USERPASS2=$(ask_secret "Повторите пароль для $USERNAME: ")
        [[ "$USERPASS" == "$USERPASS2" ]] && break
        warn "Пароли не совпадают!"
    done
    while :; do
        ROOTPASS=$(ask_secret "Пароль для root: ")
        ROOTPASS2=$(ask_secret "Повторите пароль для root: ")
        [[ "$ROOTPASS" == "$ROOTPASS2" ]] && break
        warn "Пароли не совпадают!"
    done
    TZ_ZONE=$(ask "Укажите временную зону (например, Europe/Moscow): ")

    # Проверка размера диска
    DISK_SIZE=$(lsblk -b -n -o SIZE "$DISK" | head -1)
    (( DISK_SIZE >= 8*1024*1024*1024 )) || error "Диск слишком мал (минимум 8GB)"

    warn "Все данные на диске $DISK будут удалены!"
    read -r -p "Продолжить? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        info "Установка отменена"
        exit 0
    fi

    # Проверка и размонтирование /mnt
    if mountpoint -q /mnt; then
        warn "Точка /mnt занята, размонтирую..."
        umount -R /mnt || error "Не удалось размонтировать /mnt"
    fi

    info "Очистка таблицы разделов $DISK"
    wipefs -af "$DISK" || error "wipefs завершился неудачно"

    info "Создание разделов: swap (2GB) + root (ext4)"
    SWAP_SIZE="2GiB"
    parted "$DISK" --script mklabel msdos \
        mkpart primary linux-swap 1MiB "$SWAP_SIZE" \
        mkpart primary ext4 "$SWAP_SIZE" 100% \
        set 2 boot on || error "Ошибка parted"

    partprobe "$DISK"
    sleep 2

    if [[ "$DISK" == *"nvme"* ]]; then
        SWAP_PART="${DISK}p1"
        ROOT_PART="${DISK}p2"
    else
        SWAP_PART="${DISK}1"
        ROOT_PART="${DISK}2"
    fi

    info "Форматирование swap и root"
    mkswap "$SWAP_PART" || error "Ошибка mkswap"
    mkfs.ext4 -F "$ROOT_PART" || error "Ошибка mkfs.ext4"

    info "Монтирование root и активация swap"
    mount "$ROOT_PART" /mnt || error "Ошибка монтирования root"
    swapon "$SWAP_PART" || error "Ошибка swapon"

    info "Установка базовой системы (base, linux, linux-firmware, networkmanager, sudo, grub)"
    pacstrap /mnt base linux linux-firmware networkmanager sudo grub || error "Ошибка pacstrap"

    # ---- ДОПОЛНИТЕЛЬНЫЕ ПАКЕТЫ ----
    read -r -p "Установить дополнительные пакеты (vim, git, i3)? (y/N): " PKG_CONFIRM
    if [[ "$PKG_CONFIRM" =~ ^[Yy]$ ]]; then
      info "Устанавливаю дополнительные пакеты: vim, git, i3"
      pacstrap /mnt vim git i3 || warn "Не удалось установить некоторые или все дополнительные пакеты"
    fi

    info "Генерация fstab"
   true > /mnt/etc/fstab
    genfstab -U /mnt >> /mnt/etc/fstab

    info "Настройка системы в chroot"
    setup_in_chroot

    unset USERPASS USERPASS2 ROOTPASS ROOTPASS2

    # --- ИТОГОВАЯ ИНСТРУКЦИЯ ---
    success "Установка завершена!"
    echo -e "${COLOR_YELLOW}Что делать дальше:${COLOR_RESET}"
    echo -e "1. Перезагрузитесь: \e[1;32mpoweroff\e[0m или \e[1;32mreboot\e[0m"
    echo -e "2. Извлеките установочный носитель (флешку/ISO)."
    echo -e "3. Загрузитесь с установленного диска."
    echo -e "4. Войдите под пользователем \e[1;32m$USERNAME\e[0m или root."
    echo -e "5. Чтобы сменить пароль: \e[1;32mpasswd\e[0m"
    echo -e "6. Для получения root-прав используйте: \e[1;32msudo -i\e[0m (если вы в группе wheel)"
    echo -e "7. Для настройки графики или i3 — смотрите документацию i3wm."
}

setup_in_chroot() {
    arch-chroot /mnt /bin/bash <<EOF
set -e

echo "$HOSTNAME" > /etc/hostname

ln -sf /usr/share/zoneinfo/$TZ_ZONE /etc/localtime
hwclock --systohc

sed -i 's/#ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf

echo "root:$ROOTPASS" | chpasswd

useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USERPASS" | chpasswd

echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

systemctl enable NetworkManager

grub-install --target=i386-pc "$DISK"
grub-mkconfig -o /boot/grub/grub.cfg

EOF
}

main "$@"
