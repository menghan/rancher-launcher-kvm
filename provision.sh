#!/bin/bash

IMAGEROOT=/media/sda9/libvirt/images
add_node_to_cluster() {
  local VM_IP=$((110 + $1))

  echo "    - address: "192.168.122.$VM_IP"
      user: rke
      ssh_key_path: ~/.ssh/id_rsa
      role:
        - controlplane
        - etcd
        - worker" >> cluster.yml
}

create_vm () {
  local VM_NB=$1
  local VM_KS="ks-$VM_NB.cfg"
  local VM_IP=$((110 + $VM_NB))
  local VM_PORT=$((5900 + $VM_NB))

  echo "Using port $VM_PORT"

  echo "Cleaning up old kickstart file..."
  rm -f $VM_KS

  echo "Creating new ks.cfg file..."
  cp ks.cfg.template $VM_KS
  sed -i 's/TMPL_PSWD/praqma/g' $VM_KS
  sed -i 's/TMPL_HOSTNAME/'$SRV_HOSTNAME_PREFIX-$VM_NB'/g' $VM_KS
  sed -i 's/TMPL_IP/192.168.122.'$VM_IP'/g' $VM_KS
  sed -i "s;TMPL_SSH_KEY;$SSH_KEY;g" $VM_KS

  echo "Creating disc image..."
  qemu-img create -f qcow2 $IMAGEROOT/$SRV_HOSTNAME_PREFIX-$VM_NB.qcow2 20G

  echo "Creating virtual machine and running installer..."
  virt-install --name $SRV_HOSTNAME_PREFIX-$VM_NB \
    --description 'Ubuntu 18 - Kubernetes '$VM_NB \
    --ram 2048 \
    --vcpus 1 \
    --disk path=$IMAGEROOT/$SRV_HOSTNAME_PREFIX-$VM_NB.qcow2,size=15 \
    --os-type linux \
    --os-variant ubuntu1804 \
    --network bridge=virbr0 \
    --graphics vnc,listen=0.0.0.0,port=$VM_PORT \
    --location /media/sda9/libvirt/images/bionic-server-cloudimg-amd64.img \
    --initrd-inject $VM_KS --extra-args="ks=file:/$VM_KS" 

}

SRV_HOSTNAME_PREFIX="k8s-prod"

if [ -f ~/.ssh/id_rsa.pub ]; then
  SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
else
  echo "Public key not found. It will be left black..."
  SSH_KEY=""
fi

SRV_NB=$1
if [ -z "$SRV_NB" ]; then
  SRV_NB=1
fi


echo "" > hosts_entries
echo "nodes:" > cluster.yml
echo "Creating $SRV_NB of servers..."

for i in $( seq 1 $SRV_NB )
do
  echo "Creating VM $i"
  create_vm $i & 
  add_node_to_cluster $i
  echo "192.168.122.$((110 + $i)) $SRV_HOSTNAME_PREFIX-$i" >> hosts_entries
done

echo "
network:
    plugin: flannel" >> cluster.yml

wait
echo "

Add these entries to your hosts /etc/hosts"
cat hosts_entries
