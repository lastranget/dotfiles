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
    eval "$cmd $* | tee out.out && push_to_mobile $(basename $PWD) done"
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
alias cfg='/usr/bin/git --git-dir=/home/txl25/.cfg/ --work-tree=/home/txl25'

cfg-stage() {
  local files
  files=$(config ls-files --others --exclude-standard -- .)
  
  if [[ -z "$files" ]]; then
    echo "No untracked files in current directory"
    return 0
  fi
  
  echo "Untracked files to be staged:"
  echo "$files"
  echo
  read -rp "Stage these files? [y/n] " response
  
  if [[ "$response" == "y" ]]; then
    echo "$files" | xargs config add
    echo "Files staged"
  else
    echo "Cancelled"
  fi
}

# claude dangerous alias
alias clauded='claude --dangerously-skip-permissions'

# open neovim with a server
alias svim='nvim --listen /tmp/nvim'
