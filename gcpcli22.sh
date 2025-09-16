#!/bin/bash

# ---------- Colors ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
MAGENTA="\e[35m"
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
        curl https://sdk.cloud.google.com | bash
        exec -l $SHELL
    else
        echo -e "${GREEN}${BOLD}Gcloud CLI already installed.${RESET}"
    fi

    echo -e "${YELLOW}${BOLD}Now login to your Google Account:${RESET}"
    gcloud auth login
    echo -e "${GREEN}${BOLD}Setup complete!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Change Google Account ----------
change_google_account() {
    echo -e "${YELLOW}${BOLD}Logging into a new Google Account...${RESET}"
    gcloud auth login
    echo -e "${GREEN}${BOLD}Google Account changed successfully!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Auto Project + Billing (Manual Name) ----------
auto_create_projects() {
    echo -e "${YELLOW}${BOLD}Creating Projects with Manual Names + Auto Billing Link...${RESET}"
    billing_id=$(gcloud beta billing accounts list --format="value(accountId)" | head -n1)

    if [ -z "$billing_id" ]; then
        echo -e "${RED}${BOLD}No Billing Account Found!${RESET}"
        return
    fi

    read -p "How many projects do you want to create? " num
    created_projects=()

    for ((i=1; i<=num; i++)); do
        read -p "Enter Project ID (must be unique, lowercase, no spaces): " projid
        read -p "Enter Project Name (can have spaces): " projname

        echo -e "${CYAN}${BOLD}Creating Project: $projid (${projname})${RESET}"
        gcloud projects create "$projid" --name="$projname" --set-as-default --quiet

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Project $projid created.${RESET}"
            echo -e "${GREEN}${BOLD}Linking Billing Account $billing_id...${RESET}"
            gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet
            created_projects+=("$projid ($projname)")
        else
            echo -e "${RED}Failed to create project $projid${RESET}"
        fi
    done

    echo -e "${GREEN}${BOLD}Projects Created & Linked with Billing:${RESET}"
    for proj in "${created_projects[@]}"; do
        echo "- $proj"
    done

    read -p "Press Enter to continue..."
}

# ---------- Show Billing Accounts ----------
show_billing_accounts() {
    echo -e "${YELLOW}${BOLD}Available Billing Accounts:${RESET}"
    gcloud beta billing accounts list --format="table(displayName,accountId,open,masterAccountId)"
    read -p "Press Enter to continue..."
}

# ---------- Auto VM Create (API Auto Enable) ----------
auto_create_vms() {
    echo -e "${YELLOW}${BOLD}Enter your SSH Public Key (without username:, only key part):${RESET}"
    read pubkey

    zone="asia-southeast1-b"
    mtype="n2d-custom-4-25600"
    disksize="60"

    projects=$(gcloud projects list --format="value(projectId)" | head -n 3)

    if [ -z "$projects" ]; then
        echo -e "${RED}${BOLD}No projects found in your account! Please create projects first.${RESET}"
        return
    fi

    echo -e "${CYAN}${BOLD}Auto-Detected Projects:${RESET}"
    echo "$projects"

    echo -e "${CYAN}${BOLD}Enter 6 VM Names (these will also be SSH usernames)...${RESET}"
    vmnames=()
    for i in {1..6}; do
        read -p "Enter VM Name #$i: " name
        vmnames+=("$name")
    done

    count=0
    for proj in $projects; do
        gcloud config set project $proj > /dev/null 2>&1
        echo -e "${CYAN}${BOLD}Switched to Project: $proj${RESET}"

        # ✅ Auto enable Compute Engine API
        echo -e "${YELLOW}Enabling Compute Engine API for $proj...${RESET}"
        gcloud services enable compute.googleapis.com --quiet

        for j in {1..2}; do
            vmname="${vmnames[$count]}"
            echo -e "${GREEN}${BOLD}Creating VM $vmname in $proj...${RESET}"
            gcloud compute instances create $vmname \
                --zone=$zone \
                --machine-type=$mtype \
                --image-family=ubuntu-2404-lts-amd64 \
                --image-project=ubuntu-os-cloud \
                --boot-disk-size=${disksize}GB \
                --boot-disk-type=pd-balanced \
                --metadata ssh-keys="${vmname}:${pubkey}" \
                --tags=http-server,https-server \
                --quiet
            ((count++))
        done
    done

    echo -e "${GREEN}${BOLD}All 6 VMs Created Successfully Across Projects!${RESET}"
    echo
    show_all_vms
}

# ---------- Show All VMs ----------
show_all_vms() {
    echo -e "${YELLOW}${BOLD}Showing All VMs Across All Projects:${RESET}"
    echo "------------------------------------------------------"
    gcloud projects list --format="value(projectId)" | while read proj; do
        vms=$(gcloud compute instances list --project=$proj --format="value(name,EXTERNAL_IP)")
        if [ -n "$vms" ]; then
            echo -e "${CYAN}${BOLD}Project: $proj${RESET}"
            echo "VM Name        External IP        SSH Username"
            echo "-----------------------------------------------"
            echo "$vms" | while read name ip; do
                printf "%-15s %-18s %-15s\n" "$name" "$ip" "$name"
            done
            echo
        fi
    done
    echo "------------------------------------------------------"
    read -p "Press Enter to continue..."
}

# ---------- Show All Projects ----------
show_all_projects() {
    echo -e "${YELLOW}${BOLD}Listing All Projects:${RESET}"
    gcloud projects list --format="table(projectId,name,createTime)"
    read -p "Press Enter to continue..."
}

# ---------- Delete One VM ----------
delete_one_vm() {
    echo -e "${YELLOW}${BOLD}Deleting a Single VM...${RESET}"
    gcloud projects list --format="table(projectId,name)"
    read -p "Enter Project ID: " projid
    gcloud compute instances list --project=$projid --format="table(name,zone,status)"
    read -p "Enter VM Name to delete: " vmname
    zone=$(gcloud compute instances list --project=$projid --filter="name=$vmname" --format="value(zone)")
    if [ -z "$zone" ]; then
        echo -e "${RED}VM not found!${RESET}"
    else
        gcloud compute instances delete $vmname --project=$projid --zone=$zone --quiet
        echo -e "${GREEN}VM $vmname deleted successfully from project $projid.${RESET}"
    fi
    read -p "Press Enter to continue..."
}

# ---------- Auto Delete All VMs ----------
delete_all_vms() {
    echo -e "${RED}${BOLD}Deleting ALL VMs across ALL projects...${RESET}"
    for proj in $(gcloud projects list --format="value(projectId)"); do
        echo -e "${CYAN}${BOLD}Checking Project: $proj${RESET}"
        mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name)")
        for vm in "${vms[@]}"; do
            zone=$(gcloud compute instances list --project=$proj --filter="name=$vm" --format="value(zone)")
            gcloud compute instances delete $vm --project=$proj --zone=$zone --quiet
            echo -e "${GREEN}Deleted $vm from $proj${RESET}"
        done
    done
    read -p "Press Enter to continue..."
}

# ---------- Connect VM (Box Style, Yellow Borders) ----------
connect_vm() {
    if [ ! -f "$TERM_KEY_PATH" ]; then
        echo -e "${YELLOW}Enter path to Termius private key to use for VM connections:${RESET}"
        read keypath
        cp "$keypath" "$TERM_KEY_PATH"
        chmod 600 "$TERM_KEY_PATH"
        echo -e "${GREEN}Termius key saved at $TERM_KEY_PATH${RESET}"
    fi

    echo -e "${YELLOW}${BOLD}Fetching all VMs across all projects...${RESET}"

    vm_list=()
    index=1

    for proj in $(gcloud projects list --format="value(projectId)"); do
        mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name,zone,EXTERNAL_IP)")
        for vm in "${vms[@]}"; do
            name=$(echo $vm | awk '{print $1}')
            zone=$(echo $vm | awk '{print $2}')
            ip=$(echo $vm | awk '{print $3}')
            if [ -n "$name" ] && [ -n "$ip" ]; then
                echo -e "${YELLOW}${BOLD}+----------------------------------------------------+${RESET}"
                echo -e "${YELLOW}${BOLD}|${RESET} [${index}] VM: ${CYAN}${BOLD}$name${RESET}"
                echo -e "${YELLOW}${BOLD}|${RESET} IP: ${GREEN}$ip${RESET}"
                echo -e "${YELLOW}${BOLD}|${RESET} Project: ${MAGENTA}$proj${RESET}"
                echo -e "${YELLOW}${BOLD}+----------------------------------------------------+${RESET}"
                vm_list+=("$proj|$name|$zone|$ip")
                ((index++))
            fi
        done
    done

    if [ ${#vm_list[@]} -eq 0 ]; then
        echo -e "${RED}No VMs found across projects!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    echo -e "${GREEN}${BOLD}Total VMs Found: ${#vm_list[@]}${RESET}"
    echo "------------------------------------------------------"
    read -p "Enter VM number to connect: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#vm_list[@]} ]; then
        echo -e "${RED}Invalid choice!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    selected="${vm_list[$((choice-1))]}"
    proj=$(echo "$selected" | cut -d'|' -f1)
    vmname=$(echo "$selected" | cut -d'|' -f2)
    zone=$(echo "$selected" | cut -d'|' -f3)
    ip=$(echo "$selected" | cut -d'|' -f4)

    echo -e "${GREEN}${BOLD}Connecting to $vmname ($ip) in project $proj...${RESET}"
    ssh -i "$TERM_KEY_PATH" "$vmname@$ip"
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
    echo -e "${YELLOW}${BOLD}| [2] 🔄 Change / Login Google Account               |"
    echo -e "${YELLOW}${BOLD}| [3] 📁 Create Projects (Manual) + Auto Billing     |"
    echo -e "${YELLOW}${BOLD}| [4] 🚀 Auto Create 6 VMs (2 per Project)           |"
    echo -e "${YELLOW}${BOLD}| [5] 🌍 Show All VMs Across Projects                |"
    echo -e "${YELLOW}${BOLD}| [6] 📜 Show All Projects                           |"
    echo -e "${YELLOW}${BOLD}| [7] 🔗 Connect VM (Box Style)                     |"
    echo -e "${YELLOW}${BOLD}| [8] ❌ Disconnect VM                               |"
    echo -e "${YELLOW}${BOLD}| [9] 🗑️ Delete ONE VM                               |"
    echo -e "${YELLOW}${BOLD}| [10] 💣 Delete ALL VMs (ALL Projects)              |"
    echo -e "${YELLOW}${BOLD}| [11] 🚪 Exit                                       |"
    echo -e "${YELLOW}${BOLD}| [12] 💳 Show Billing Accounts                      |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose an option [1-12]: " choice

    case $choice in
        1) fresh_install ;;
        2) change_google_account ;;
        3) auto_create_projects ;;
        4) auto_create_vms ;;
        5) show_all_vms ;;
        6) show_all_projects ;;
        7) connect_vm ;;
        8) disconnect_vm ;;
        9) delete_one_vm ;;
        10) delete_all_vms ;;
        11) echo -e "${RED}Exiting...${RESET}" ; exit 0 ;;
        12) show_billing_accounts ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ; read -p "Press Enter to continue..." ;;
    esac
done
