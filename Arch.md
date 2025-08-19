# Установка и настройка Arch Linux
## Этап 1. LiveISO

1. Очистка дисков
```bash
    wipefs -a /dev/sda /dev/sdb /dev/nvme0n1
    sgdisk --zap-all /dev/nvme0n1
    vgchange -an
    sgdisk --zap-all /dev/sda
    sgdisk --zap-all /dev/sdb
    dd if=/dev/zero of=/dev/sda bs=1M count=10
    dd if=/dev/zero of=/dev/sdb bs=1M count=10
```
2. Создание разделов
```bash
    echo -e "g\nn\n\n\n+1G\nt\n1\nn\n\n\n\nw" | fdisk /dev/nvme0n1
    echo -e "g\nn\n\n\n\nw" | fdisk /dev/sda
    echo -e "g\nn\n\n\n\nw" | fdisk /dev/sdb
    pvcreate /dev/sda1 /dev/sdb1
    vgcreate sdgroup /dev/sda1 /dev/sdb1
    lvcreate -i 2 -I 64 -l 100%FREE -n homeland sdgroup
```
3. Форматирование и монтирование
```bash
    mkfs.fat -F 32 /dev/nvme0n1p1
    mkfs.ext4 /dev/nvme0n1p2
    mkfs.ext4 /dev/sdgroup/homeland
    mount /dev/nvme0n1p2 /mnt
    mkdir -p /mnt/{boot/efi,home}
    mount /dev/nvme0n1p1 /mnt/boot/efi
    mount /dev/sdgroup/homeland /mnt/home
```
4. SWAP-файл
```bash
    cd /mnt/home && fallocate -l 32G .swapfile
    dd if=/dev/zero of=/mnt/home/.swapfile bs=1G count=32 status=progress
    chmod 600 /mnt/home/.swapfile
    mkswap /mnt/home/.swapfile
    swapon /mnt/home/.swapfile && cd
```
5. Конфигурация Pacman
```bash
    sed -i -e 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' -e '/^#\[multilib\]/{N;s/#\[multilib\]\n#/[multilib]\n/}' /etc/pacman.conf
```
6. Установка программ
```bash
    pacstrap /mnt base linux linux-firmware linux-headers sudo dhcpcd lvm2 vim nano glances fastfetch iwd openssh git base-devel zsh curl
```
7. Перенос конфигураций, создание fstab и вход в систему
```bash
    cp /etc/pacman.conf /mnt/etc/pacman.conf
    cp /etc/ssh/sshd_config /mnt/etc/ssh/sshd_config
    genfstab -U /mnt >> /mnt/etc/fstab
    arch-chroot /mnt
```

## Этап 2. Преднастройка в chroot
1. Пользователи
```bash
    sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
    useradd -mG wheel -g users -s /bin/zsh statix
    echo 'statix:1234' | sudo chpasswd
    echo 'root:1234' | sudo chpasswd
```
Не забыть указать надежный пароль `echo 'statix:<пароль>' | sudo chpasswd`

2. Запуск основных служб
```bash
    systemctl enable sshd dhcpcd iwd
```
3. Время и часовой пояс
```bash
    ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
    hwclock --systohc
```
4. GRUB и выход из Chroot
```bash
    pacman -Syu grub efibootmgr --noconfirm
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=SvetOS
    sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="SvetOS Alpha"/' /etc/os-release || \
      echo 'PRETTY_NAME="SvetOS Alpha"' >> /etc/os-release
    grub-mkconfig -o /boot/grub/grub.cfg
```
5. Выход
```bash
    exit
```

## Этап 3. Загрузка в систему
1. Перезагрузка
```bash
    umount -R /mnt
    reboot
```
2. Установка драйверов Nvidia
```bash
    sudo pacman -Syy nvidia nvidia-utils vulkan-icd-loader lib32-nvidia-utils lib32-vulkan-icd-loader opencl-nvidia lib32-opencl-nvidia --noconfirm
```
3. Xorg
```bash
    sudo pacman -S xorg xorg-server xorg-xinit xorg-xrandr xdotool --noconfirm 
```
4. Оконный менеджер Awesome
```bash
    sudo pacman -S awesome xorg-xprop rofi alacritty --noconfirm
    mkdir -p /home/statix/.config/awesome
    cp /etc/xdg/awesome/rc.lua /home/statix/.config/awesome/rc.lua || true
    chown -R statix:users /home/statix/.config/awesome
```
5. Xinitrc
```bash
    cat > /home/statix/.xinitrc <<'XINIT'
    #!/bin/sh
    exec awesome
    XINIT
    chown statix:users /home/statix/.xinitrc
    chmod +x /home/statix/.xinitrc
```
6. Запуск скриптов для автонастройки
```bash
    git clone https://github.com/statix05/svetos-arch
    find svetos-arch/scripts -type f -name "*.sh" -exec chmod +x {} \;
    cd svet0s-arch/scripts
    ./setup-zsh-arch-zinit.sh --vi-mode --with-ysu --patch-alacritty # Желательно запускать на самом ПК через Alacritty
    ./makepkg-configurator.sh
```