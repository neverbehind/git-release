#!/bin/bash

## Install the latest git release tool into the zshell profile.
mkdir -p ~/bin
curl https://raw.githubusercontent.com/neverbehind/git-release/master/git-release -o ~/bin/git-release
 
chmod +x ~/bin/git-release 

## Add local bin path
[ "$SHELL" = "/bin/zsh" ] && touch ~/.zshrc && echo "PATH=$PATH:~/bin" >> ~/.zshrc && source ~/.zshrc  
[ "$SHELL" = "/bin/bash" ] && touch ~/.bashrc && echo "PATH=$PATH:~/bin" >> ~/.bashrc && source ~/.bashrc  
