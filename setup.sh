#!/bin/bash

# Fuction Hardening
harden_system() {
    echo "Performing Comprehensive Hardening..."
    sudo apt-get update -y && sudo apt-get upgrade -y
    sudo apt-get install -y vim nano net-tools git wget curl
    sudo apt-get install -y ufw fail2ban apparmor apparmor-utils
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw allow http
    sudo ufw allow https
    sudo ufw enable
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
    sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo systemctl restart sshd
    sudo systemctl enable apparmor
    sudo systemctl start apparmor
    sudo bash -c 'cat <<EOF >> /etc/sysctl.conf
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1
# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5
EOF'
    sudo sysctl -p

    # Password Policy
    sudo apt-get install -y libpam-pwquality cracklib-runtime
    sudo bash -c 'cat <<EOF >> /etc/pam.d/common-password
password requisite pam_pwquality.so retry=3 minlen=8 maxrepeat=3 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1 difok=3 gecoscheck=1 reject_username enforce_for_root
EOF'
    sudo bash -c 'cat <<EOF >> /etc/login.defs
PASS_MAX_DAYS   30
EOF'
    echo "System hardening completed."
}

install_docker_swarm_master() {
    echo "Installing Docker Swarm Master..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y docker.io
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo apt install -y docker-compose

    # Check network interface
    ip addr show
    read -p "Enter the network interface (e.g., eth0): " net_interface
    ip_address=$(ip -o -f inet addr show $net_interface | awk '{print $4}' | cut -d/ -f1)
    echo "Using IP address: $ip_address"

    sudo docker swarm init --advertise-addr $ip_address
    echo "Docker Swarm Master installation completed."

    # Add user to docker group
    sudo usermod -aG docker $USER
    echo "Added $USER to docker group."

    # Change group without logout
    newgrp docker

    # Test Docker installation
    docker ps -a
}

# Fuction Install Kubernetes Cluster Master Node
install_kubernetes_cluster_master() {
    read -p "Enter the new hostname: " new_hostname
    echo "Changing hostname to $new_hostname..."
    sudo hostnamectl set-hostname $new_hostname
    sudo sed -i "s/127.0.1.1.*/127.0.1.1 $new_hostname/" /etc/hosts

    echo "Checking if containerd is installed..."
    if ! command -v containerd &> /dev/null; then
        echo "containerd is not installed. Installing containerd..."
        # apt-transport-https may be a dummy package; if so, you can skip that package
        sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg
        sudo apt-get install -y containerd
        sudo mkdir -p /etc/containerd
        sudo containerd config default | sudo tee /etc/containerd/config.toml
        sudo systemctl restart containerd

        # Configure cgroup driver for containerd
        
        sudo systemctl restart containerd
        sudo sysctl -w net.ipv4.ip_forward=1
        echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
        sudo sysctl -p

    else
        echo "containerd is already installed."
    fi

    echo "Installing Kubernetes Cluster Master Node..."
    # If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
    sudo mkdir -p -m 755 /etc/apt/keyrings
    sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    sudo systemctl enable --now kubelet
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab


    # Configure cgroup driver for kubelet
    sudo sed -i 's/^KUBELET_EXTRA_ARGS=.*/KUBELET_EXTRA_ARGS=--cgroup-driver=systemd/' /etc/default/kubelet
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet
    sudo rm /etc/containerd/config.toml
    sudo systemctl restart containerd


    # Check network interface
    ip addr show
    read -p "Enter the network interface (e.g., eth0): " net_interface
    cidr=$(ip -o -f inet addr show "$net_interface" | awk '{print $4}')
    echo "Using CIDR: $cidr"
    sudo kubeadm init --pod-network-cidr=$cidr
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.1/manifests/calico.yaml
    sudo sed -i 's/^\(.*\)systemd_cgroup = false/\1systemd_cgroup = true/' /etc/containerd/config.toml
    echo "Kubernetes Cluster Master Node installation complete."

    # Test Kubernetes installation
    kubectl get node -A
}


# Fuction Install Docker Standalone
install_docker_standalone() {
    echo "Installing Docker Standalone..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y docker.io
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo apt install -y docker-compose
    echo "Docker Standalone installation completed."
}

# Fuction Install Kubernetes Standalone
install_kubernetes_standalone() {
    echo "Installing Kubernetes Standalone..."
    
    # Check if containerd is already installed
    if ! command -v containerd &> /dev/null; then
        echo "containerd not found, installing..."
        sudo apt-get update && sudo apt-get install -y containerd
        
        # Create containerd configuration file
        sudo mkdir -p /etc/containerd
        containerd config default | sudo tee /etc/containerd/config.toml
        
        # Start and enable containerd
        sudo systemctl restart containerd
        sudo systemctl enable containerd
    else
        echo "containerd is already installed."
    fi
    
    # Set cgroup driver for containerd
    sudo sed -i 's/^SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sudo systemctl restart containerd
    
    # Install Kubernetes
    # apt-transport-https may be a dummy package; if so, you can skip that package
    sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg
    # If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
    sudo mkdir -p -m 755 /etc/apt/keyrings
    sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    
    # Set cgroup driver for kubelet
    echo 'KUBELET_EXTRA_ARGS="--cgroup-driver=systemd"' | sudo tee /etc/default/kubelet
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet
    
    echo "Kubernetes Standalone installation completed."
}

# Fuction Install Docker Worker
install_docker_worker() {
    read -p "Enter the IP address of the master node: " MASTER_IP
    echo "Installing Docker Worker..."
    
    # Install ipcalc if not already installed
    if ! command -v ipcalc &> /dev/null; then
        echo "ipcalc not found, installing..."
        sudo apt update
        sudo apt install -y ipcalc
    fi
    
    # Get the IP address and subnet mask of the current machine
    CURRENT_IP=$(hostname -I | awk '{print $1}')
    CURRENT_SUBNET=$(ip -o -f inet addr show | awk '/scope global/ {print $4}')
    
    # Extract the network part of the IP address and subnet mask
    MASTER_NETWORK=$(ipcalc -n $MASTER_IP $CURRENT_SUBNET | grep Network | awk '{print $2}')
    CURRENT_NETWORK=$(ipcalc -n $CURRENT_IP $CURRENT_SUBNET | grep Network | awk '{print $2}')
    
    # Check if the current machine is on the same network and subnet as the master node
    if [ "$MASTER_NETWORK" == "$CURRENT_NETWORK" ]; then
        echo "Current machine is on the same network and subnet as the master node."
        sudo apt update && sudo apt upgrade -y
        sudo apt install -y docker.io
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo apt install -y docker-compose
        echo "Docker Worker installation completed."
        
        # Generate SSH key if not already present
        if [ ! -f ~/.ssh/id_rsa ]; then
            echo "Generating SSH key..."
            ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
        fi
        
        # Copy SSH key to master node
        echo "Copying SSH key to master node..."
        ssh-copy-id $(whoami)@$MASTER_IP
        
        # Request join command from the master node
        echo "Requesting join command from the master node..."
        JOIN_COMMAND=$(ssh $(whoami)@$MASTER_IP "sudo docker swarm join-token worker -q")
        
        # Join the cluster
        if [ -n "$JOIN_COMMAND" ]; then
            sudo docker swarm join --token $JOIN_COMMAND $MASTER_IP:2377
            echo "Successfully joined the Docker Swarm cluster."
        else
            echo "Failed to retrieve join command from the master node."
        fi
    else
        echo "Current machine is NOT on the same network and subnet as the master node. Aborting installation."
    fi
}

# Fuction Install Kubernetes Worker
install_kubernetes_worker() {
    read -p "Enter the IP address of the master node: " MASTER_IP
    echo "Installing containerd and Kubernetes Worker..."
    
    # Install ipcalc if not already installed
    if ! command -v ipcalc &> /dev/null; then
        echo "ipcalc not found, installing..."
        sudo apt update
        sudo apt install -y ipcalc
    fi
    
    # Get the current machine's IP address and subnet mask
    CURRENT_IP=$(hostname -I | awk '{print $1}')
    CURRENT_SUBNET=$(ip -o -f inet addr show | awk '/scope global/ {print $4}')
    
    # Calculate the network part of the IP address and subnet mask
    MASTER_NETWORK=$(ipcalc -n $MASTER_IP $CURRENT_SUBNET | grep Network | awk '{print $2}')
    CURRENT_NETWORK=$(ipcalc -n $CURRENT_IP $CURRENT_SUBNET | grep Network | awk '{print $2}')
    
    # Check if the current machine is on the same network and subnet as the master node
    if [ "$MASTER_NETWORK" == "$CURRENT_NETWORK" ]; then
        echo "Current machine is on the same network and subnet as the master node."
        
        # Check if containerd is already installed
        if ! command -v containerd &> /dev/null; then
            echo "containerd not found, installing..."
            sudo apt-get update && sudo apt-get install -y containerd
            
            # Create containerd configuration file
            sudo mkdir -p /etc/containerd
            containerd config default | sudo tee /etc/containerd/config.toml
            
            # Start and enable containerd
            sudo systemctl restart containerd
            sudo systemctl enable containerd
        else
            echo "containerd is already installed."
        fi
        
        
        
        # Install Kubernetes Worker
        sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg
        # If the directory `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
        sudo mkdir -p -m 755 /etc/apt/keyrings
        sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
        sudo apt-get update
        sudo apt-get install -y kubelet kubeadm kubectl
        sudo apt-mark hold kubelet kubeadm kubectl
        sudo swapoff -a
        sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
        echo "Kubernetes Worker installation completed."
        
        # Set cgroup driver for kubelet
        sudo sed -i 's/^KUBELET_EXTRA_ARGS=.*/KUBELET_EXTRA_ARGS=--cgroup-driver=systemd/' /etc/default/kubelet
        
        # Restart kubelet
        sudo systemctl daemon-reload
        sudo systemctl restart kubelet
        
        # Generate SSH key if not already present
        if [ ! -f ~/.ssh/id_rsa ]; then
            echo "Generating SSH key..."
            ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
        fi
        
        # Copy SSH key to master node
        echo "Copying SSH key to master node..."
        ssh-copy-id $(whoami)@$MASTER_IP
        
        # Request join command from the master node
        echo "Requesting join command from the master node..."
        JOIN_COMMAND=$(ssh $(whoami)@$MASTER_IP "sudo kubeadm token create --print-join-command")
        
        # Join the cluster
        if [ -n "$JOIN_COMMAND" ]; then
            sudo $JOIN_COMMAND
            echo "Successfully joined the Kubernetes cluster."
            # Set cgroup driver for containerd
            sudo sed -i 's/^SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
            sudo systemctl restart containerd
        else
            echo "Failed to retrieve join command from the master node."
        fi
    else
        echo "Current machine is NOT on the same network and subnet as the master node. Aborting installation."
    fi
}
# mylogo
echo "
  ____             _             __  __                  
 |  _ \ ___  _ __ | |_ ___ _ __ |  \/  | ___ _ __  _   _ 
 | |_) / _ \| '_ \| __/ _ \ '_ \| |\/| |/ _ \ '_ \| | | |
 |  _ < (_) | |_) | ||  __/ | | | |  | |  __/ | | | |_| |
 |_| \_\___/| .__/ \__\___|_| |_|_|  |_|\___|_| |_|\__,_|
            |_|                                         
"
echo "========================================================="
echo "====                 Hi Everyone                     ===="
echo "====         Create by Phone RapterxCode             ===="
echo "========================================================="

# Menu
echo "Please select an option:"
echo "1. Install Docker Swarm Master"
echo "2. Install Kubernetes Cluster Master Node"
echo "3. Install Docker Standalone"
echo "4. Install Kubernetes Standalone"
echo "5. Install Docker Worker"
echo "6. Install Kubernetes Worker"
echo "7. Harden System"
read -p "Enter your choice [1-7]: " choice


case $choice in
    1)
        harden_system
        install_docker_swarm_master
        ;;
    2)
        harden_system
        install_kubernetes_cluster_master
        ;;
    3)
        harden_system
        install_docker_standalone
        ;;
    4)
        harden_system
        install_kubernetes_standalone
        ;;
    5)
        harden_system
        install_docker_worker
        ;;
    6)
        harden_system
        install_kubernetes_worker
        ;;
    7)
        harden_system
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

# Check command if install Kubernetes
if [ "$choice" -eq 2 ] || [ "$choice" -eq 4 ]; then
    kubectl get nodes
    kubectl get pods --all-namespaces
fi
