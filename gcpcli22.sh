#!/bin/bash

# ---------- Colors ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD='\033[1m'
RESET="\e[0m"

# ---------- Files ----------
SSH_INFO_FILE="$HOME/.gcp_vm_info"
TERM_KEY_PATH="$HOME/.ssh/termius_vm_key"

# ---------- Fresh Install ----------
fresh_install() {
    echo -e "${CYAN}${BOLD}Running Fresh Install + CLI Setup...${RESET}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget git unzip python3 python3-pip docker.io
    sudo systemctl enable docker --now

    if ! command -v gcloud &> /dev/null
    then
        echo -e "${YELLOW}${BOLD}Gcloud CLI not found. Installing...${RESET}"
        curl https://sdk.cloud.com | bash
        exec -l $SHELL
    else
        echo -e "${GREEN}${BOLD}Gcloud CLI already installed.${RESET}"
    fi

    echo -e "${YELLOW}${BOLD}Now login to your Google Account:${RESET}"
    gcloud auth login
    echo -e "${GREEN}${BOLD}Setup complete!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Create VM ----------
create_vm() {
    echo -e "${YELLOW}${BOLD}Create a new VM:${RESET}"
    read -p "Enter VM Name: " vmname
    read -p "Enter SSH Public Key (username:ssh-rsa ...): " sshkey

    zone="asia-southeast1-b"
    mtype="n2d-custom-4-25600"
    disksize="60"

    echo -e "${GREEN}${BOLD}Creating VM $vmname in zone $zone...${RESET}"
    gcloud compute instances create $vmname \
        --zone=$zone \
        --machine-type=$mtype \
        --image-family=ubuntu-2404-lts-amd64 \
        --image-project=ubuntu-os-cloud \
        --boot-disk-size=${disksize}GB \
        --boot-disk-type=pd-balanced \
        --metadata ssh-keys="$sshkey" \
        --tags=http-server,https-server

    echo -e "${GREEN}${BOLD}VM $vmname created successfully!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Create Project ----------
create_project() {
    echo -e "${YELLOW}${BOLD}Create a new GCP Project:${RESET}"
    read -p "Enter Project Name: " projname
    baseid=$(echo "$projname" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    projid="${baseid}-$(shuf -i 100-999 -n 1)"
    gcloud projects create "$projid" --name="$projname" --set-as-default
    echo -e "${GREEN}${BOLD}Project created successfully!${RESET}"
    echo "Project ID: $projid"
    echo "Project Name: $projname"

    echo -e "${YELLOW}${BOLD}Do you want to link a billing account now? (y/n):${RESET}"
    read choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        link_billing $projid
    fi
    read -p "Press Enter to continue..."
}

# ---------- Switch Project ----------
switch_project() {
    echo -e "${YELLOW}${BOLD}Available Projects:${RESET}"
    gcloud projects list --format="table(projectId,name)"
    read -p "Enter PROJECT_ID to switch: " projid
    gcloud config set project $projid
    echo -e "${GREEN}${BOLD}Project switched to $projid${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- List VMs ----------
list_vms() {
    echo -e "${YELLOW}${BOLD}Listing all VMs in current project:${RESET}"
    gcloud compute instances list --format="table(name,zone,machineType,STATUS,INTERNAL_IP,EXTERNAL_IP)"
    read -p "Press Enter to continue..."
}

# ---------- Show SSH Metadata ----------
show_ssh_metadata() {
    echo -e "${YELLOW}${BOLD}SSH Keys Metadata:${RESET}"
    gcloud compute project-info describe --format="value(commonInstanceMetadata.items)"
    read -p "Press Enter to continue..."
}

# ---------- Show Entire SSH Key ----------
show_ssh_key() {
    echo -e "${YELLOW}${BOLD}Enter VM Name to show entire SSH Key:${RESET}"
    read -p "VM Name: " vmname
    zone=$(gcloud compute instances list --filter="name=$vmname" --format="value(zone)")
    if [ -z "$zone" ]; then
        echo -e "${RED}${BOLD}VM not found!${RESET}"
    else
        echo -e "${GREEN}${BOLD}SSH Key for $vmname:${RESET}"
        gcloud compute instances describe $vmname --zone $zone --format="get(metadata.ssh-keys)"
    fi
    read -p "Press Enter to continue..."
}

# ---------- Billing ----------
show_billing_accounts() {
    echo -e "${YELLOW}${BOLD}Available Billing Accounts:${RESET}"
    gcloud beta billing accounts list
    read -p "Press Enter to continue..."
}

link_billing() {
    project_id=$1
    echo -e "${YELLOW}${BOLD}Link a billing account to project $project_id:${RESET}"
    gcloud beta billing accounts list --format="table(name,accountId)"
    read -p "Enter ACCOUNT_ID to link: " account_id
    gcloud beta billing projects link $project_id --billing-account $account_id
    echo -e "${GREEN}${BOLD}Billing linked successfully!${RESET}"
    read -p "Press Enter to continue..."
}

delete_vm() {
    read -p "Enter VM Name to delete: " vmname
    zone=$(gcloud compute instances list --filter="name=$vmname" --format="value(zone)")
    if [ -z "$zone" ]; then
        echo -e "${RED}${BOLD}VM not found!${RESET}"
    else
        gcloud compute instances delete $vmname --zone $zone --quiet
        echo -e "${GREEN}${BOLD}VM $vmname deleted successfully!${RESET}"
    fi
    read -p "Press Enter to continue..."
}

check_credit() {
    echo -e "${YELLOW}${BOLD}Checking remaining Free Trial credit:${RESET}"
    gcloud alpha billing accounts list --format="table(displayName,name,open,creditAmount,creditBalance)"
    read -p "Press Enter to continue..."
}

# ---------- Connect VM using Termius Key ----------
connect_vm() {
    # Ensure Termius private key exists
    if [ ! -f "$TERM_KEY_PATH" ]; then
        echo -e "${YELLOW}Enter path to Termius private key to use for VM connections:${RESET}"
        read keypath
        cp "$keypath" "$TERM_KEY_PATH"
        chmod 600 "$TERM_KEY_PATH"
        echo -e "${GREEN}Termius key saved at $TERM_KEY_PATH${RESET}"
    fi

    echo -e "${YELLOW}${BOLD}Available VMs in current project:${RESET}"
    mapfile -t vms < <(gcloud compute instances list --format="value(name)")
    if [ ${#vms[@]} -eq 0 ]; then
        echo -e "${RED}No VMs found!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    for i in "${!vms[@]}"; do
        echo "$((i+1))) ${vms[$i]}"
    done

    read -p "Select VM to connect [number]: " vmnum
    vmindex=$((vmnum-1))
    if [[ -z "${vms[$vmindex]}" ]]; then
        echo -e "${RED}Invalid selection!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    vmname="${vms[$vmindex]}"
    zone=$(gcloud compute instances list --filter="name=$vmname" --format="value(zone)")
    ext_ip=$(gcloud compute instances describe $vmname --zone $zone --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
    ssh_user=$(gcloud compute instances describe $vmname --zone $zone --format="get(metadata.ssh-keys)" | awk -F':' '{print $1}')

    # Save SSH info
    echo "$vmname|$ssh_user|$ext_ip|$TERM_KEY_PATH" > "$SSH_INFO_FILE"

    echo -e "${GREEN}Connecting to $vmname using Termius private key...${RESET}"
    ssh -i "$TERM_KEY_PATH" "$ssh_user@$ext_ip"
    read -p "Press Enter to continue..."
}

# ---------- Disconnect VM ----------
disconnect_vm() {
    if [ -f "$SSH_INFO_FILE" ]; then
        rm "$SSH_INFO_FILE"
        echo -e "${GREEN}VM disconnected and SSH info cleared.${RESET}"
    else
        echo -e "${YELLOW}No active VM session found.${RESET}"
    fi
    read -p "Press Enter to continue..."
}

# ---------- Main Menu ----------
while true; do
    clear
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${CYAN}${BOLD}|     GCP CLI BENGAL AIRDROP (MADE BY PRODIP)       |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] 🛠️ Fresh Install + CLI Setup                   |"
    echo -e "${YELLOW}${BOLD}| [2] 🔄 Change Google Account                        |"
    echo -e "${YELLOW}${BOLD}| [3] 📁 Create New Project                          |"
    echo -e "${YELLOW}${BOLD}| [4] ➡️ Switch Project                             |"
    echo -e "${YELLOW}${BOLD}| [5] 🖥️ List VMs                                   |"
    echo -e "${YELLOW}${BOLD}| [6] 🔑 Show SSH Keys Metadata                       |"
    echo -e "${YELLOW}${BOLD}| [7] 🔍 Show Entire SSH Key for a VM                 |"
    echo -e "${YELLOW}${BOLD}| [8] 🚀 Create VM (pre-filled defaults)             |"
    echo -e "${YELLOW}${BOLD}| [9] 🗑️ Delete VM                                  |"
    echo -e "${YELLOW}${BOLD}| [10] 💰 Show Billing Accounts / Link Billing       |"
    echo -e "${YELLOW}${BOLD}| [11] 💳 Check Free Trial Credit                    |"
    echo -e "${YELLOW}${BOLD}| [12] 🚪 Exit                                       |"
    echo -e "${YELLOW}${BOLD}| [13] 🔗 Connect VM                                 |"
    echo -e "${YELLOW}${BOLD"| [14] ❌ Disconnect VM                               |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose an option [1-14]: " choice

    case $choice in
        1) fresh_install ;;
        2)
            echo -e "${YELLOW}Logging into new Google Account...${RESET}"
            gcloud auth login
            read -p "Press Enter to continue..."
            ;;
        3) create_project ;;
        4) switch_project ;;
        5) list_vms ;;
        6) show_ssh_metadata ;;
        7) show_ssh_key ;;
        8) create_vm ;;
        9) delete_vm ;;
        10)
            echo -e "${CYAN}1) Show Billing Accounts"
            echo "2) Link Billing to Project"
            read -p "Choose an option [1-2]: " subchoice
            case $subchoice in
                1) show_billing_accounts ;;
                2)
                    read -p "Enter Project ID to link billing: " projid
                    link_billing $projid
                    ;;
                *) echo -e "${RED}Invalid choice!${RESET}" ; read -p "Press Enter to continue..." ;;
            esac
            ;;
        11) check_credit ;;
        12) echo -e "${RED}Exiting...${RESET}" ; exit 0 ;;
        13) connect_vm ;;
        14) disconnect_vm ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ; read -p "Press Enter to continue..." ;;
    esac
done
