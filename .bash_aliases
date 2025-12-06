# refresh aliases
alias fresh="source $HOME/.bashrc"

#add intelliJ toolbox to path
export PATH=$PATH:/home/txl25/apps/jetbrains-toolbox-2.8.0.51430/bin

#add intelliJ to path
export PATH=$PATH:/home/txl25/.local/share/JetBrains/Toolbox/scripts

#add scripts directory to path
export PATH=$PATH:/home/txl25/scripts

#add .local/bin to path for lazydocker
export PATH=$PATH:/home/txl25/.local/bin

#add coursier to path for scala lsp
export PATH=$PATH:/home/txl25/.local/share/coursier/bin

# Search current and parent directories for env.sh and run it with the supplied options
e () {
  # searches the current directory then all parent directories for the env.sh script
  path=$(pwd)
  while [[ "$path" != "" && ! -e "$path/env.sh" ]]; do
    path=${path%/*}
  done

  cmd="$path/env.sh"
  # if the search was successful we will run the script we found
  if [[ -e "$cmd" ]]; then
    # echo "running cmd '$cmd $*'"
    eval "$cmd $* | tee out.out && push_to_mobile.sh $(basename $PWD) done"
  # if we cannot find it we will print an error message
  else
      echo "env.sh was not found in the current directory or any parent directory"
  fi
}

#lazydocker alias
alias lzd=lazydocker

#neovim alias
export PATH="$PATH:/opt/nvim-linux-x86_64/bin"
alias oldvim=/usr/bin/vim
alias vim=nvim

#neovim obsidian alias
alias obsidian='nvim ~/vaults/Main/views/home.md'
alias o=obsidian

# set bash to vi editing mode
set -o vi
export EDITOR=vim

# Remove dangling docker images (<none>:<none>)
docker-prune-dangling() {
    local images=$(docker images -f "dangling=true" -q)
    if [[ -z "$images" ]]; then
        echo "No dangling images to remove."
    else
        echo "Removing dangling images..."
        docker rmi $images
    fi
}
alias dprune='docker-prune-dangling'

# Docker cleanup - remove all containers, images, volumes, and custom networks
docker-nuke() {
    docker ps -aq | xargs -r docker rm -f -v
    docker images -q | xargs -r docker rmi -f
    docker volume ls -q | xargs -r docker volume rm
    docker network ls -q --filter "type=custom" | xargs -r docker network rm
}

export DOTFILES_DIR="$HOME/.cfg"
alias cfg='/usr/bin/git --git-dir="$DOTFILES_DIR/" --work-tree="$HOME"'

cfg-stage() {
  local files
  files=$(cfg ls-files --others --exclude-standard -- .)
  
  if [[ -z "$files" ]]; then
    echo "No untracked files in current directory"
    return 0
  fi
  
  echo "Untracked files to be staged:"
  echo "$files"
  echo
  read -rp "Stage these files? [y/n] " response
  
  if [[ "$response" == "y" ]]; then
    echo "$files" | xargs cfg add
    echo "Files staged"
  else
    echo "Cancelled"
  fi
}

# claude dangerous alias
alias clauded='claude --dangerously-skip-permissions'

# open neovim with a server
alias svim='nvim --listen /tmp/nvim'

# check on neovim processes and kill them
alias nvim-check='ss -lx | grep nvim | grep -oP "nvim\.\K[0-9]+" | xargs -I{} ps -p {} -o pid,ppid,tty,cmd'
alias nvim-kill='ss -lx | grep nvim | grep -oP "nvim\.\K[0-9]+" | xargs -r kill -9'
nvim-sessions() {
  printf "%-20s %-30s %s\n" "SESSION" "FILE" "PID"
  printf "%-20s %-30s %s\n" "-------" "----" "---"
  ss -lx | grep -oP 'nvim\.\K[0-9]+' | while read pid; do
    tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ -n "$tty" && "$tty" != "?" ]]; then
      session=$(tmux list-panes -a -F '#{pane_tty} #{session_name}:#{window_index}.#{pane_index}' 2>/dev/null | grep "$tty" | awk '{print $2}')
    else
      session="(detached)"
    fi
    file=$(ps -o args= -p "$pid" 2>/dev/null | sed 's/.*--embed //')
    printf "%-20s %-30s %s\n" "${session:-(unknown)}" "$file" "(pid: $pid)"
  done
}

# Mount a USB flash drive
mount-usb() {
  local device="$1"

  # If no device specified, detect and show available USB devices
  if [[ -z "$device" ]]; then
    local -a unmounted_devices

    # Find all block devices that look like USB drives (sda, sdb, sdc, etc.) and are not mounted
    while IFS= read -r line; do
      local name=$(echo "$line" | awk '{print $1}')
      local mountpoints=$(echo "$line" | awk '{print $2}')

      # Only include devices without mount points (unmounted)
      if [[ -z "$mountpoints" || "$mountpoints" == "-" ]]; then
        unmounted_devices+=("/dev/$name")
      fi
    done < <(lsblk -d -n -o NAME,MOUNTPOINTS | grep -E '^(sd[a-z]|nvme)' | grep -v nvme0n1)

    if [[ ${#unmounted_devices[@]} -eq 0 ]]; then
      echo "No unmounted USB devices found."
      return 1
    elif [[ ${#unmounted_devices[@]} -eq 1 ]]; then
      device="${unmounted_devices[0]}"
      echo "Found USB device: $device"
    else
      echo "Found ${#unmounted_devices[@]} unmounted USB devices:"
      for i in "${!unmounted_devices[@]}"; do
        echo "$((i+1)). ${unmounted_devices[$i]}"
      done
      read -p "Select device to mount (1-${#unmounted_devices[@]}): " choice
      if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#unmounted_devices[@]} )); then
        echo "Invalid selection."
        return 1
      fi
      device="${unmounted_devices[$((choice-1))]}"
    fi
  fi

  echo "Mounting $device..."
  udisksctl mount -b "$device"
}
alias mnt=mount-usb

# Unmount a USB flash drive
unmount-usb() {
  local device="$1"

  # If no device specified, detect and show mounted USB devices
  if [[ -z "$device" ]]; then
    local -a mounted_devices

    # Find all block devices that look like USB drives and are mounted
    while IFS= read -r line; do
      local name=$(echo "$line" | awk '{print $1}')
      local mountpoints=$(echo "$line" | awk '{print $2}')

      # Only include devices with mount points (mounted)
      if [[ -n "$mountpoints" && "$mountpoints" != "-" ]]; then
        mounted_devices+=("/dev/$name")
      fi
    done < <(lsblk -d -n -o NAME,MOUNTPOINTS | grep -E '^(sd[a-z])' | grep -v nvme0n1)

    if [[ ${#mounted_devices[@]} -eq 0 ]]; then
      echo "No mounted USB devices found."
      return 1
    elif [[ ${#mounted_devices[@]} -eq 1 ]]; then
      device="${mounted_devices[0]}"
      echo "Found USB device: $device"
    else
      echo "Found ${#mounted_devices[@]} mounted USB devices:"
      for i in "${!mounted_devices[@]}"; do
        echo "$((i+1)). ${mounted_devices[$i]}"
      done
      read -p "Select device to unmount (1-${#mounted_devices[@]}): " choice
      if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#mounted_devices[@]} )); then
        echo "Invalid selection."
        return 1
      fi
      device="${mounted_devices[$((choice-1))]}"
    fi
  fi

  echo "Unmounting $device..."
  udisksctl unmount -b "$device"
}
alias umnt=unmount-usb
