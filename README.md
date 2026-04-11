# SD-WAN OPEN SOURCE

## Requirements

### CONTROLLER MACHINE

If your controller machine is Debian yo must install these requeriments:
```bash
sudo apt update
sudo apt install -y ansible python3 python3-pip python3-paramiko ansible-pylibssh wireguard-tools
pip3 install ansible-pylibssh --break-system-packages
git clone https://github.com/4ntoniomj/sd-wan
```

### VyOS MACHINES

In the VyOS machines must be configured ssh service and IP with gateway if you are in LAN network.
```bash
# Commands for configuration
configure # This command enters in configuration mode
set service ssh port 22
# THE NEXT commands only if you are in LAN network
set interfaces ethernet eth0 address <IP/CIDR>
set interfaces ethernet eth1 address <IP/CIDR>
set protocols static route 0.0.0.0/0 next-hop <IP_Gateway> 
commit # Apply
save # In disk
```

---
## Start-up and explanation

### Inventory

First edit the file called hosts.
```txt
[headquarters]
hq ansible_ssh_host=<ip>
sede1 ansible_ssh_host=<ip>
sede2 ansible_ssh_host=<ip>
sede3 ansible_ssh_host=<ip>
sede4 ansible_ssh_host=<ip>

[headquartersbck]
hq-bck ansible_ssh_host=<ip2>
sede1-bck ansible_ssh_host=<ip2>
sede2-bck ansible_ssh_host=<ip2>
sede3-bck ansible_ssh_host=<ip2>
sede4-bck ansible_ssh_host=<ip2>

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_user=vyos
ansible_connection=network_cli
ansible_network_os=vyos
ansible_ssh_pass="<password>"
```

### SSH PUBLIC KEY

Later edit the file called sshkey.pub.
```txt
AAAAB3NzaC1yc2EAAAADAQABAAABAQCoDgfhQJuJRFWJijHn7ZinZ3NWp4hWVrt7HFcvn0kgtP/5PeCtMt
```
ONLY THE PUBLIC KEY EXACTLY.

And edit the file called GlobalConfigurationHub.yml with your correct parameters.

### ANSIBLE CONFIG

The file ansible.conf contains the following lines
```txt
[defaults]
host_key_checking = no # Avoid fingerprinting when connecting via ssh
retry_files_enabled = False # Does not create files with failed hosts in the playbook
```

### VARIABLE
In all locations it is necessary to agree on some variables, but for the first playbook only the lan_ip variable is necessary where the LAN network must be defined.

```bash
mkdir host_vars # DIR FOR ANSIBLE VARIABLE
touch sede{1..4}.yml hq.yml # SAME NAME AS IN THE INVENTORY FILE
```

```yml
lan_ip: "192.168.0.1/23"
```

### EXEC FIRST PLAYBOOK

Once this configuration is in place, you can run the first Ansible playbook. This playbook applies the basic system configuration, including the hostname, SSH key-based access for VyOS, timezone settings, and other initial parameters.
For full details, please refer to the playbook file itself.
```bash
ansible-playbook -i hosts GlobalConfigurationHub.yml
```

I want to explain these lines from playbook:
```txt
gather_facts: 'no' # Required for compatibility and performance
connection: network_cli # Indicates that you are connecting to a network device
save: true # Save in disk 
```
`gather_facts` Performance because it avoids scanning and compatibility because the scan is done on Linux systems and therefore does not support VyOS.

### WIREGUARD

We have to have two tunnels, one will be the main one and the other will act as a failover.

It needs create the wireguard keys in the controller machine because the keys cannot be handled correctly if they are created next to the playbook execution, at least I have not been able to.
This script can help you.
```bash
#!/bin/bash
cd files
# SAME NAMES AS IN THE INVENTORY FILE
names=("hq" "sede1" "sede2" "sede3" "sede4")
for i in ${names[@]}; do
	wg genkey | tee "${i}".key | wg pubkey > "${i}.pub"
done

for i in ${names[@]}; do
	wg genkey | tee "${i}".2.key | wg pubkey > "${i}.2.pub"
done
```

It is also necessary to define the variables that will contain the wireguard IPs for the headquarters.
```bash
mkdir host_vars # DIR FOR ANSIBLE VARIABLE
touch sede{1..4}.yml # SAME NAME AS IN THE INVENTORY FILE
```

```yml
wg_ip: "10.10.10.1/24" # wg0
wg_ip_bck: "10.10.20.1/24" # wg1
```

The playbook is responsible for assigning only the private keys, since only with this wireguard key is it able to obtain the public key, this is done to all locations.
```yml
---
- name: Wireguard autoconfiguration
  hosts: headquarters
  gather_facts: 'no'
  connection: network_cli

  tasks:
    - name: Global configuration wireguard
      vyos_config:
        lines:
          - set interfaces wireguard wg0 private-key "{{ lookup('file', inventory_hostname ~ '.key') }}"
          - set interfaces wireguard wg0 description 'SDWAN'
          - set interfaces wireguard wg0 port 51820
        save: true
```

In the "hq" headquarters a wireguard IP and the respective public keys and IPs allowed for the clients (the other headquarters) are assigned, while in the other headquarters their IP is assigned (defined in the files within the host_vars), It also configures the "hq" headquarters as a client providing public IP, port and public key and finally the range of destination IPs allowed in the VPN in addition to a keepalive 
```yml
- name: Wireguard HQ
  hosts: hq
  gather_facts: 'no'
  connection: network_cli

  tasks:
    - name: Global configuration wireguard
      vyos_config:
        lines:
          - set interfaces wireguard wg0 address 10.10.10.1/24
          - set interfaces wireguard wg0 peer sede1 allowed-ips 10.10.10.2/32
          - set interfaces wireguard wg0 peer sede1 public-key "{{ lookup('file', 'sede1.pub' ) }}"
          - set interfaces wireguard wg0 peer sede2 allowed-ips 10.10.10.3/32
          - set interfaces wireguard wg0 peer sede2 public-key "{{ lookup('file', 'sede2.pub' ) }}"
          - set interfaces wireguard wg0 peer sede3 allowed-ips 10.10.10.4/32
          - set interfaces wireguard wg0 peer sede3 public-key "{{ lookup('file', 'sede3.pub' ) }}"
          - set interfaces wireguard wg0 peer sede4 allowed-ips 10.10.10.5/32
          - set interfaces wireguard wg0 peer sede4 public-key "{{ lookup('file', 'sede4.pub' ) }}"
        save: true

- name: Wireguard headquarters1
  hosts: sede1, sede2, sede3, sede4
  gather_facts: 'no'
  connection: network_cli

  tasks:
    - name: Global configuration wireguard
      vyos_config:
        lines:
          - set interfaces wireguard wg0 address {{ wg_ip }}
          - set interfaces wireguard wg0 peer hq public-key '{{ lookup('file', 'hq.pub') }}'
          - set interfaces wireguard wg0 peer hq address 192.168.1.230
          - set interfaces wireguard wg0 peer hq port 51820
          - set interfaces wireguard wg0 peer hq persistent-keepalive 25
          - set interfaces wireguard wg0 peer hq allowed-ips 10.10.10.0/24
        save: true
```

Exec.
```bash
ansible-playbook -i hosts WireguardConfigurtion.yml
ansible-playbook -i hosts WireguardConfigurtion2.yml
```