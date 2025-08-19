#!/usr/bin/env bash

# makepkg-configurator.sh — Настройка makepkg и ccache/sccache для Arch Linux
sudo cp $HOME/svetos-arch/configs/makepkg.conf /etc/makepkg.conf
sudo pacman -Syu cmake ninja meson pkgconf --noconfirm
sudo pacman -S --needed lld ccache sccache --noconfirm
sudo pacman -S --needed mold --noconfirm

# Создание директорий для кэша makepkg и ccache/sccache
mkdir -p "$HOME/.cache/makepkg/"{pkg,src,srcpkg,logs} "$HOME/.cache"/{ccache,sccache}
ccache -M 20G
sccache --max-size 20G


# Установка paru
git clone https://aur.archlinux.org/paru
cd paru
makepkg -si --noconfirm
cd ..
paru -Syu --noconfirm