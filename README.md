# Post-Install deploiement script
A simple Bash script to install different apps and setup the network.

## How to install :

**Using wget :**

 

    wget -O post-install.sh https://github.com/Hurstone/Post-Install-Debian/blob/main/post-install.sh
    
**Using git :**

    sudo apt install git
    git clone https://github.com/Hurstone/Post-Install-Debian.git

## How to run :

    cd Post-Install-Debian/
    chmod +x post-install.sh
    sudo ./post-install.sh

## Argument
-   `-n` **or** `--network` Allow to configure the network
