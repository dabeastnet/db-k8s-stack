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

    # Forward the NodePort exposed by the frontend service to the host.
    # The NodePort service in k8s/frontend/service.yaml exposes the
    # frontend on port 30080 on each node.  Expose it on port 18080 on
    # your host machine so you can access the application at
    # http://localhost:18080 without running `kubectl port-forward`.
    # Forward the Kubernetes NodePort 30080 on the control plane node to port
    # 18080 on your host.  The frontend service exposes port 80 and is mapped
    # to NodePort 30080 in k8s/frontend/service.yaml.  Forwarding this port
    # allows you to access the application at http://localhost:18080.
    master.vm.network "forwarded_port", guest: 30080, host: 18080, auto_correct: true


    # Forward the Prometheus web UI from the control plane node to the host.
    # Prometheus runs in the monitoring namespace and is exposed on port 9090
    # via a ClusterIP service.  Forwarding the port here allows you to
    # access the Prometheus dashboard at http://localhost:19090 without
    # running kubectl port-forward.  If the port 19090 on your host is
    # already in use, Vagrant will auto-correct to the next available
    # port when auto_correct is true.
    # Forward the Prometheus NodePort (30090) to port 19090 on the host.
    # In k8s/monitoring/prometheus.yaml the Prometheus service is exposed
    # as a NodePort on 30090 so that it can be accessed from outside
    # the cluster.  Forwarding the NodePort here allows you to access the
    # Prometheus dashboard at http://localhost:19090 without running kubectl
    # port-forward manually.
    # Forward the Prometheus NodePort (30090) to port 19090 on the host.  In
    # k8s/monitoring/prometheus.yaml the Prometheus service is exposed as a
    # NodePort on 30090 so that it can be accessed from outside the cluster.
    # Forwarding this NodePort allows you to access the Prometheus dashboard at
    # http://localhost:19090 without using kubectl port-forward manually.
    master.vm.network "forwarded_port", guest: 30090, host: 19090, auto_correct: true
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
