# 🔧 Решение проблем

> Руководство по устранению частых ошибок при установке и настройке

## 🚨 Проблемы при установке

### 1. "Диск не найден"

**Симптомы:**
```
Ошибка: диск /dev/sda не найден
```

**Причины:**
- Неправильно указано имя диска
- Диск не подключен или не определяется системой

**Решение:**
```bash
# Проверьте все доступные диски
lsblk

# Альтернативно
fdisk -l

# Для NVMe дисков имена будут:
# /dev/nvme0n1, /dev/nvme1n1

# Для SATA/IDE дисков:
# /dev/sda, /dev/sdb, /dev/sdc
```

### 2. "Диск слишком мал"

**Симптомы:**
```
Ошибка: диск слишком мал (минимум 8GB)
```

**Решение:**
- Используйте диск размером минимум 8 ГБ
- Освободите место на текущем диске
- Рекомендуется 20+ ГБ для комфортной работы

### 3. "Ошибка при форматировании"

**Симптомы:**
```
mkfs.ext4: Device or resource busy
```

**Причины:**
- Диск используется другой программой
- Разделы диска смонтированы

**Решение:**
```bash
# Отмонтируйте все разделы диска
sudo umount /dev/sda*
sudo umount /dev/nvme0n1p*

# Проверьте, что ничего не смонтировано
lsblk

# Убейте процессы, использующие диск
sudo fuser -km /dev/sda

# Перезапустите скрипт
```

### 4. "Нет подключения к интернету"

**Симптомы:**
```
pacstrap: error: failed to retrieve packages
```

**Решение для проводного подключения:**
```bash
# Проверьте сетевые интерфейсы
ip link

# Включите интерфейс
ip link set enp0s3 up

# Получите IP автоматически
dhcpcd enp0s3
```

**Решение для Wi-Fi:**
```bash
# Запустите iwctl
iwctl

# В iwctl выполните:
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "Имя_вашей_сети"
# Введите пароль

# Выйдите из iwctl
exit

# Проверьте подключение
ping -c 3 google.com
```

### 5. "GPG signature verification failed"

**Симптомы:**
```
error: key "..." could not be imported
```

**Решение:**
```bash
# Обновите ключи
pacman-key --refresh-keys

# Или заново инициализируйте
pacman-key --init
pacman-key --populate archlinux
```

---

## 🖥️ Проблемы с X11 и i3wm

### 1. "Черный экран после startx"

**Причины:**
- Неправильные драйверы видеокарты
- Отсутствует файл .xinitrc

**Решение:**
```bash
# Проверьте наличие .xinitrc
ls -la ~/.xinitrc

# Если файла нет, создайте:
echo "exec i3" > ~/.xinitrc

# Проверьте драйверы видеокарты
lspci | grep VGA

# Для Intel:
sudo pacman -S xf86-video-intel

# Для AMD:
sudo pacman -S xf86-video-amdgpu

# Для NVIDIA:
sudo pacman -S nvidia

# Универсальный драйвер:
sudo pacman -S xf86-video-vesa
```

### 2. "i3 не запускается"

**Симптомы:**
```
i3: command not found
```

**Решение:**
```bash
# Проверьте установку i3
pacman -Q i3-wm

# Если не установлен:
sudo pacman -S i3-wm i3status i3lock dmenu

# Проверьте .xinitrc
cat ~/.xinitrc
# Должно быть: exec i3
```

### 3. "Нет звука"

**Решение:**
```bash
# Установите ALSA и PulseAudio
sudo pacman -S alsa-utils pulseaudio pulseaudio-alsa

# Проверьте звуковые карты
aplay -l

# Откройте микшер
alsamixer

# Включите звук (клавиша M для unmute)
# Увеличьте громкость стрелками

# Для PulseAudio GUI:
sudo pacman -S pavucontrol
pavucontrol
```

### 4. "Клавиатура работает только на английском"

**Решение:**
```bash
# Установите раскладки
setxkbmap -layout us,ru -option grp:alt_shift_toggle

# Добавьте в i3 config для автозапуска:
echo "exec --no-startup-id setxkbmap -layout us,ru -option grp:alt_shift_toggle" >> ~/.config/i3/config

# Перезапустите i3: Win+Shift+R
```

### 5. "Wi-Fi не подключается"

**Решение:**
```bash
# Проверьте статус NetworkManager
sudo systemctl status NetworkManager

# Если не запущен:
sudo systemctl start NetworkManager
sudo systemctl enable NetworkManager

# Проверьте беспроводной интерфейс
nmcli device status

# Подключитесь к сети
nmcli device wifi connect "SSID" password "password"

# Для GUI управления:
sudo pacman -S network-manager-applet
nm-applet &
```

---

## 📦 Проблемы с пакетами

### 1. "Package not found"

**Решение:**
```bash
# Обновите базы пакетов
sudo pacman -Sy

# Поиск пакета
pacman -Ss имя_пакета

# Проверьте AUR (для yay)
yay -Ss имя_пакета
```

### 2. "Dependency conflicts"

**Решение:**
```bash
# Принудительное обновление
sudo pacman -Syu --overwrite "*"

# Очистка кэша
sudo pacman -Scc

# Переустановка проблемного пакета
sudo pacman -S имя_пакета --overwrite "*"
```

---

## 🔍 Диагностические команды

### Информация о системе
```bash
# Версия ядра
uname -r

# Информация о дистрибутиве
cat /etc/os-release

# Использование диска
df -h

# Использование памяти
free -h

# Запущенные сервисы
systemctl list-units --type=service --state=running
```

### Логи системы
```bash
# Системные логи
journalctl -xe

# Логи X11
cat ~/.local/share/xorg/Xorg.0.log

# Логи i3
cat ~/.config/i3/log
```

---

## 🆘 Когда ничего не помогает

### 1. Восстановление через chroot
```bash
# Загрузитесь с Arch ISO
# Смонтируйте корневой раздел
mount /dev/sda2 /mnt

# Войдите в систему
arch-chroot /mnt

# Исправьте проблемы
# ...

# Выйдите и перезагрузитесь
exit
reboot
```

### 2. Переустановка пакетов
```bash
# Переустановка группы пакетов
sudo pacman -S xorg --overwrite "*"

# Переустановка i3
sudo pacman -Rns i3-wm
sudo pacman -S i3-wm i3status i3lock
```

### 3. Очистка конфигураций
```bash
# Сброс конфига i3
rm -rf ~/.config/i3
# При следующем запуске i3 создаст новый конфиг

# Сброс .xinitrc
rm ~/.xinitrc
echo "exec i3" > ~/.xinitrc
```

---

## 📞 Получение помощи

### Официальные ресурсы
- **Arch Wiki**: https://wiki.archlinux.org/
- **Arch Forums**: https://bbs.archlinux.org/
- **i3 Documentation**: https://i3wm.org/docs/

### Сообщества
- **r/archlinux** - Reddit сообщество
- **r/i3wm** - i3 сообщество
- **Arch Linux Telegram** группы

### Как правильно задавать вопросы
1. 📋 Опишите проблему подробно
2. 📱 Приложите вывод команд диагностики
3. 🔧 Укажите, что уже пробовали
4. 💻 Опишите конфигурацию системы

---

*Помните: в Linux почти любую проблему можно решить! 🐧*