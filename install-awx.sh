#!/bin/bash

set -e  # Exit on error

echo "🚀 Starting AWX Installation on Minikube (Fedora)"

# Step 1: Install Docker
echo "🔹 Installing Docker..."
sudo dnf install -y docker docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
docker info

# Step 2: Install Minikube
echo "🔹 Installing Minikube..."
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Step 3: Start Minikube with Docker
echo "🔹 Starting Minikube..."
minikube start --driver=docker --memory=6g --cpus=4 --addons=ingress

# Step 4: Install kubectl
echo "🔹 Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/
kubectl version --client

# Step 5: Deploy AWX Operator
echo "🔹 Deploying AWX Operator..."
mkdir -p awx
cat <<EOF > awx/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=2.19.1
images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.19.1
namespace: awx
EOF
kubectl apply -k awx/
kubectl config set-context --current --namespace=awx

# Step 6: Wait for AWX Operator to be ready
echo "⏳ Waiting for AWX Operator to start..."
kubectl wait --for=condition=available --timeout=600s deployment/awx-operator-controller-manager -n awx

# Step 7: Deploy AWX Instance
echo "🔹 Deploying AWX Instance..."
cat <<EOF > awx/awx.yaml
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
spec:
  service_type: nodeport
EOF
echo "🔹 Updating Kustomization file..."
cat <<EOF > awx/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=2.19.1
  - awx.yaml
images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.19.1
namespace: awx
EOF
kubectl apply -k awx/

# Step 8: Wait for AWX Deployment
echo "⏳ Waiting for AWX to be ready..."
kubectl wait --for=condition=available --timeout=1200s deployment/awx-web -n awx || echo "⚠️ AWX may still be starting, check manually with: kubectl get pods -n awx"

# Step 9: Get AWX Web URL
echo "🔹 Fetching AWX Web Interface URL..."
MINIKUBE_IP=$(minikube ip)
NODEPORT=$(kubectl get svc awx-service -n awx -o jsonpath='{.spec.ports[0].nodePort}')
AWX_URL="http://${MINIKUBE_IP}:${NODEPORT}"

echo "🎉 AWX is available at: $AWX_URL"

# Step 10: Get Admin Password
echo "🔹 Fetching AWX Admin Password..."
ADMIN_PASSWORD=$(kubectl get secret awx-admin-password -o jsonpath="{.data.password}" | base64 --decode)
echo "🔑 AWX Admin Password: $ADMIN_PASSWORD"

echo "✅ Installation complete! Login at $AWX_URL with username: admin and password: $ADMIN_PASSWORD"

