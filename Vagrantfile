# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Base box
  config.vm.box = "ubuntu/focal64"

  # Sync the repo into /vagrant inside each VM (default)
  config.vm.synced_folder ".", "/vagrant"

  # Use common provisioner for all nodes
  config.vm.provision "shell", path: "vagrant/provision-common.sh"

  # Control plane node
  config.vm.define "cp1" do |master|
    master.vm.hostname = "cp1"
    master.vm.network "private_network", ip: "192.168.56.10"
    master.vm.provider "virtualbox" do |vb|
      vb.memory = 4096
      vb.cpus = 2
    end
    master.vm.provision "shell", path: "vagrant/provision-master.sh"
  end

  # Worker node 1
  config.vm.define "worker1" do |worker|
    worker.vm.hostname = "worker1"
    worker.vm.network "private_network", ip: "192.168.56.20"
    worker.vm.provider "virtualbox" do |vb|
      vb.memory = 4096
      vb.cpus = 2
    end
    worker.vm.provision "shell", path: "vagrant/provision-worker.sh"
  end

  # Worker node 2
  config.vm.define "worker2" do |worker|
    worker.vm.hostname = "worker2"
    worker.vm.network "private_network", ip: "192.168.56.21"
    worker.vm.provider "virtualbox" do |vb|
      vb.memory = 4096
      vb.cpus = 2
    end
    worker.vm.provision "shell", path: "vagrant/provision-worker.sh"
  end
end
