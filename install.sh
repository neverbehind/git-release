#!/bin/bash

## Install the latest git release tool into the zshell profile.

curl https://raw.githubusercontent.com/neverbehind/git-release/master/git-release -o ~/bin/git-release
 
chmod +x ~/bin/git-release 
 
touch ~/.zshrc && echo "PATH=$PATH:~/bin" >> ~/.zshrc 
 
source ~/.zshrc  
