#!/usr/bin/env bash
# setup-zsh-arch-zinit.sh — Arch Linux (pacman), Zsh + zinit + Powerlevel10k
# Требуется: zsh установлен; Alacritty уже есть (патч шрифта — опционально)

set -euo pipefail
IFS=$'\n\t'

log()  { printf "\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m==>\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m==>\033[0m %s\n" "$*"; }

WITH_YSU=0           # плагин "you-should-use"
WITH_VI=0            # vi-режим биндингов
INSTALL_FONT=1       # JetBrains Mono Nerd Font (через pacman, с fallback)
PATCH_ALACRITTY=0    # пропатчить Alacritty на JetBrainsMono Nerd Font
RUN_SYSUPGRADE=0     # pacman -Syu перед установкой

usage() {
  cat <<'USAGE'
Usage: setup-zsh-arch-zinit.sh [options]
Options:
  --with-ysu           Enable "you-should-use" plugin
  --vi-mode            Enable vi key bindings
  --no-font            Skip JetBrains Mono Nerd Font installation
  --patch-alacritty    Patch Alacritty config to use JetBrains Mono Nerd Font
  --sysupgrade         Run "sudo pacman -Syu" before installing packages
  -h, --help           Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-ysu)        WITH_YSU=1 ;;
    --vi-mode)         WITH_VI=1 ;;
    --no-font)         INSTALL_FONT=0 ;;
    --patch-alacritty) PATCH_ALACRITTY=1 ;;
    --sysupgrade)      RUN_SYSUPGRADE=1 ;;
    -h|--help)         usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

# Проверки окружения
if ! command -v pacman >/dev/null 2>&1; then
  err "Похоже, это не Arch (pacman не найден). Прерываю."; exit 1
fi

SUDO=""
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    $SUDO -v || { err "Нужны sudo-права для установки пакетов."; exit 1; }
  else
    err "sudo не найден. Запусти от root или установи sudo."; exit 1
  fi
fi

# Обновления и пакеты
if [[ $RUN_SYSUPGRADE -eq 1 ]]; then
  log "Полное обновление системы…"
  $SUDO pacman -Syu --noconfirm
else
  log "Синхронизирую базы пакетов…"
  $SUDO pacman -Sy --noconfirm
fi

PKGS=(git curl fzf fd ripgrep eza bat zoxide zsh-completions fontconfig unzip)
log "Устанавливаю пакеты: ${PKGS[*]} …"
$SUDO pacman -S --needed --noconfirm "${PKGS[@]}"

# Установка JetBrains Mono Nerd Font
install_jb_nerd() {
  if pacman -Si ttf-jetbrains-mono-nerd &>/dev/null; then
    log "Ставлю ttf-jetbrains-mono-nerd из репозиториев…"
    $SUDO pacman -S --needed --noconfirm ttf-jetbrains-mono-nerd
  else
    warn "ttf-jetbrains-mono-nerd не найден в репозиториях. Пытаюсь установить из релиза Nerd Fonts…"
    local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    local tmp="$(mktemp -d)"
    local font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"
    log "Скачиваю $url …"
    curl -fsSL "$url" -o "$tmp/JetBrainsMono.zip"
    log "Распаковываю шрифт в $font_dir …"
    unzip -o "$tmp/JetBrainsMono.zip" -d "$font_dir" >/dev/null
    rm -rf "$tmp"
    log "Обновляю кеш шрифтов…"
    fc-cache -f "$font_dir" || warn "Не удалось обновить кеш шрифтов. Проверь наличие fontconfig."
  fi
}

if [[ $INSTALL_FONT -eq 1 ]]; then
  install_jb_nerd
else
  warn "Пропускаю установку шрифта (--no-font)."
fi

# Патч Alacritty (опционально)
patch_alacritty() {
  local cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty"
  local fonts_file="$cfg_dir/fonts-jbmnf.toml"
  mkdir -p "$cfg_dir"

  cat >"$fonts_file" <<'TOML'
[font]
normal = { family = "JetBrainsMono Nerd Font", style = "Regular" }
bold = { family = "JetBrainsMono Nerd Font", style = "Bold" }
italic = { family = "JetBrainsMono Nerd Font", style = "Italic" }
bold_italic = { family = "JetBrainsMono Nerd Font", style = "Bold Italic" }
TOML

  local main_toml="$cfg_dir/alacritty.toml"
  if [[ -f "$main_toml" ]]; then
    if ! grep -q 'fonts-jbmnf\.toml' "$main_toml"; then
      log "Добавляю import в alacritty.toml (бэкап делаю)…"
      cp "$main_toml" "$main_toml.backup-$(date +%Y%m%d-%H%M%S)"
      printf 'import = ["%s"]\n%s' "$fonts_file" "$(cat "$main_toml")" > "$main_toml.tmp"
      mv "$main_toml.tmp" "$main_toml"
    else
      log "fonts-jbmnf.toml уже импортирован в alacritty.toml"
    fi
  else
    log "Создаю alacritty.toml с импортом fonts-jbmnf.toml…"
    printf 'import = ["%s"]\n' "$fonts_file" > "$main_toml"
  fi
}

if [[ $PATCH_ALACRITTY -eq 1 ]]; then
  patch_alacritty
fi

# Установка zinit
if [[ ! -r "$HOME/.zinit/bin/zinit.zsh" ]]; then
  log "Ставлю zinit…"
  mkdir -p "$HOME/.zinit"
  git clone https://github.com/zdharma-continuum/zinit.git "$HOME/.zinit/bin"
else
  log "zinit уже установлен."
fi

# Бэкап .zshrc и генерация нового
TS="$(date +%Y%m%d-%H%M%S)"
if [[ -f "$HOME/.zshrc" ]]; then
  cp "$HOME/.zshrc" "$HOME/.zshrc.backup-$TS"
  warn "Сделан бэкап: ~/.zshrc.backup-$TS"
fi
mkdir -p "$HOME/.cache/zsh"

log "Генерирую ~/.zshrc под zinit…"
{
  cat <<'ZRC'
# ---------- Powerlevel10k instant prompt (оставь сверху) ----------
[[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh

# ---------- Пути системных completions ----------
fpath=(/usr/share/zsh/site-functions $fpath)

# ---------- Базовые опции Zsh ----------
setopt autocd
setopt correct
setopt no_beep
setopt interactive_comments
setopt complete_in_word

# История
HISTFILE=~/.zsh_history
HISTSIZE=500000
SAVEHIST=500000
setopt extended_history
setopt hist_ignore_all_dups
setopt hist_reduce_blanks
setopt share_history
setopt inc_append_history
setopt hist_verify

# Клавиатурные биндинги
ZRC
  if [[ $WITH_VI -eq 1 ]]; then
    echo 'bindkey -v'
    echo 'KEYTIMEOUT=1'
  else
    echo 'bindkey -e'
  fi
  cat <<'ZRC'

# ---------- Менеджер плагинов zinit ----------
if [[ ! -r ~/.zinit/bin/zinit.zsh ]]; then
  mkdir -p ~/.zinit && git clone https://github.com/zdharma-continuum/zinit.git ~/.zinit/bin
fi
source ~/.zinit/bin/zinit.zsh

# Тема Powerlevel10k
zinit light romkatv/powerlevel10k

# Инициализация completion
autoload -Uz compinit
[[ -d ~/.cache/zsh ]] || mkdir -p ~/.cache/zsh
compinit -d ~/.cache/zsh/zcompdump-$ZSH_VERSION

# FZF-Tab — красивое меню на Tab (после compinit)
zinit light Aloxaf/fzf-tab

# Подсказки и подсветка
zinit light zsh-users/zsh-autosuggestions
zinit light zdharma-continuum/fast-syntax-highlighting

# Поиск по истории по подстроке
zinit light zsh-users/zsh-history-substring-search
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# Стили и поведение completion
zmodload zsh/complist
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'r:|[._-]=** r:|=**'

# Интеграция FZF (горячие клавиши: Ctrl-T, Ctrl-R, Alt-C)
if [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
  source /usr/share/fzf/key-bindings.zsh
fi
if [[ -f /usr/share/fzf/completion.zsh ]]; then
  source /usr/share/fzf/completion.zsh
fi
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# Умная навигация по директориям (zoxide, команда "z")
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# Небольшие алиасы
alias ls='eza --icons=auto --group-directories-first'
alias l='ls -la'
alias cat='bat -p'
alias grep='rg'
alias ..='cd ..'
alias ...='cd ../..'
alias gs='git status -sb'
alias gl='git log --oneline --graph --decorate'
ZRC

  if [[ $WITH_YSU -eq 1 ]]; then
    cat <<'ZRC'
# Подсказки «you-should-use»
zinit light MichaelAquilina/zsh-you-should-use
ZRC
  fi

  cat <<'ZRC'

# Конфиг Powerlevel10k (если создан)
[[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh
ZRC
} > "$HOME/.zshrc"

# Сделать zsh логин-шеллом (если ещё не)
if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
  log "Делаю zsh логин-шеллом… (потребуется пароль)"
  if ! chsh -s "$(command -v zsh)"; then
    warn "Не удалось сменить логин-шелл. Сделай вручную: chsh -s $(command -v zsh)"
  fi
fi

log "Готово! Перезапусти терминал или выполни: exec zsh"
log "Затем запусти мастер Powerlevel10k: p10k configure"
if [[ $INSTALL_FONT -eq 1 ]]; then
  log "Выбери шрифт в терминале: JetBrainsMono Nerd Font (Regular/Bold/Italic/Bold Italic)."
fi
if [[ $PATCH_ALACRITTY -eq 1 ]]; then
  log "Alacritty настроен на JetBrainsMono Nerd Font."
fi