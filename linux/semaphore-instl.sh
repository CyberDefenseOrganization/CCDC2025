#!/bin/bash

#############
# HOW TO RUN
# ./sempahore_install user password
#############

read -p "Username: " user
read -s -p "Password: " password

# 1. Check if Docker is installed via snap
if dpkg -l | grep -q docker.io; then
    echo "Docker is already installed."
else
    echo "Docker not found. Installing..."
    sudo apt update
    sudo apt install -y docker.io
    echo "Docker installation complete."
fi

# 2. Check if Semaphore container is already running
if [ "$(sudo docker ps -q -f name=semaphore)" ]; then
    echo "Semaphore is already running."
elif [ "$(sudo docker ps -aq -f name=semaphore)" ]; then
    echo "Semaphore container exists but is stopped. Starting it..."
    sudo docker start semaphore
else
    echo "Semaphore not found. Deploying new container..."
    # Deploying with your custom credentials
    sudo docker run -d \
      --name semaphore \
      -p 3000:3000 \
      -e SEMAPHORE_ADMIN=$user \
      -e SEMAPHORE_ADMIN_PASSWORD=$password \
      -e SEMAPHORE_ADMIN_NAME="CDO Admin" \
      -e SEMAPHORE_ADMIN_EMAIL=admin@localhost \
      -e SEMAPHORE_DB_DIALECT=bolt \
      semaphoreui/semaphore:latest
    
    echo "Semaphore deployed! Access it at http://localhost:3000"
    echo "Username: $user"
    echo "Password: $password"
fi
