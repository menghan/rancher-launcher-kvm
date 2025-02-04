#!/bin/bash

IMAGEROOT=/media/sda9/libvirt/images
add_node_to_cluster() {
  local VM_IP=$((110 + $1))

  echo "    - address: "192.168.123.$VM_IP"
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
  sed -i 's/TMPL_PSWD/rootPASSWORD/g' $VM_KS
  sed -i 's/TMPL_HOSTNAME/'$SRV_HOSTNAME_PREFIX-$VM_NB'/g' $VM_KS
  sed -i 's/TMPL_IP/192.168.123.'$VM_IP'/g' $VM_KS
  sed -i "s;TMPL_SSH_KEY;$SSH_KEY;g" $VM_KS

  echo "Creating disc image..."
  qemu-img create -f qcow2 $IMAGEROOT/$SRV_HOSTNAME_PREFIX-$VM_NB.qcow2 20G

  echo "Creating virtual machine and running installer..."
  virt-install --name $SRV_HOSTNAME_PREFIX-$VM_NB \
    --autostart \
    --description 'Ubuntu 18 - Kubernetes '$VM_NB \
    --ram 3072 \
    --vcpus 1 \
    --disk path=$IMAGEROOT/$SRV_HOSTNAME_PREFIX-$VM_NB.qcow2,size=15 \
    --os-type linux \
    --os-variant ubuntu18.04 \
    --network network=kvmnat1 \
    --graphics vnc \
    --location 'http://mirror.nus.edu.sg/ubuntu/dists/bionic/main/installer-amd64/' \
    --initrd-inject $VM_KS \
    --extra-args="ks=file:/$VM_KS"

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


echo "nodes:" > cluster.yml
echo "Creating $SRV_NB of servers..."

for i in $( seq 1 $SRV_NB )
do
  echo "Creating VM $i"
  create_vm $i & 
  add_node_to_cluster $i
done

echo "
network:
    plugin: flannel" >> cluster.yml

wait
