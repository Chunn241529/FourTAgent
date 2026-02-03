#!/bin/bash

# Definition of colors and styles
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Helper function for printing headers
print_header() {
    echo -e "\n${BLUE}${BOLD}======================================================${NC}"
    echo -e "${BLUE}${BOLD}   $1${NC}"
    echo -e "${BLUE}${BOLD}======================================================${NC}\n"
}

# Helper function for printing success
print_success() {
    echo -e "${GREEN}${BOLD}✓ $1${NC}"
}

# Helper function for printing warning
print_warning() {
    echo -e "${YELLOW}${BOLD}⚠ $1${NC}"
}

clear
print_header "Starting CUDA Toolkit 13.1 Installation"

# 1. Download pin file
print_warning "Step 1/5: Downloading configuration pin file..."
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin
sudo mv cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600
print_success "Configuration pin file installed."

# 2. Download local repo deb
print_warning "Step 2/5: Downloading CUDA repository package (Heavy file)..."
wget https://developer.download.nvidia.com/compute/cuda/13.1.1/local_installers/cuda-repo-ubuntu2404-13-1-local_13.1.1-590.48.01-1_amd64.deb
print_success "Download complete."

# 3. Install repository package
print_warning "Step 3/5: Installing repository package..."
sudo dpkg -i cuda-repo-ubuntu2404-13-1-local_13.1.1-590.48.01-1_amd64.deb
sudo cp /var/cuda-repo-ubuntu2404-13-1-local/cuda-*-keyring.gpg /usr/share/keyrings/
print_success "Repository package installed and keyring updated."

# 4. Update apt
print_warning "Step 4/5: Updating package lists..."
sudo apt-get update
print_success "Package lists updated."

# 5. Install CUDA Toolkit
print_warning "Step 5/5: Installing CUDA Toolkit 13-1 (This may take a while)..."
sudo apt-get -y install cuda-toolkit-13-1
print_success "CUDA Toolkit 13-1 installed successfully!"

print_header "Installation Completed Successfully!"

# Ask for reboot
echo -e "${YELLOW}Updates generally require a system reboot to take full effect.${NC}"
read -p "Do you want to restart your computer now? (y/n): " choice

case "$choice" in 
  y|Y ) 
    echo -e "${RED}Rebooting system...${NC}"
    sudo reboot
    ;;
  n|N ) 
    echo -e "${GREEN}You chose not to restart. Please restart manually later.${NC}"
    ;;
  * ) 
    echo -e "${GREEN}Invalid input. Proceeding without restart.${NC}"
    ;;
esac
