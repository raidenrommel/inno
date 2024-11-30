#!/bin/bash

# Variables
DISK_NAME="innovehealth-vm"  # Changed to the new disk name
ZONE="asia-east2-c"
DATE=$(date +%Y%m%d)  # Current date in YYYYMMDD format
SNAPSHOT_NAME="innovehealth-snapshot-$DATE"
IMAGE_NAME="innovehealth-image-$DATE"
INSTANCE_TEMPLATE_NAME="innovehealth-instance-template-$DATE"
INSTANCE_GROUP_NAME="innovehealth-instance-group"
PROJECT="agitechnikapp-71f9d"
SERVICE_ACCOUNT_KEY="/home/rommel/innovehealth-1c7bb0fbd008.json"  # Path to service account key

# Ensure the service account key exists
if [ ! -f "$SERVICE_ACCOUNT_KEY" ]; then
    echo "Service account key file not found at $SERVICE_ACCOUNT_KEY. Exiting."
    exit 1
fi

# Authenticate with gcloud using the service account
echo "Authenticating with Google Cloud using service account..."
gcloud auth activate-service-account --key-file="$SERVICE_ACCOUNT_KEY"
if [ $? -ne 0 ]; then
    echo "Failed to authenticate with service account. Exiting."
    exit 1
fi

# Set the Google Cloud project
echo "Setting the project to: $PROJECT"
gcloud config set project $PROJECT

# Check if the snapshot already exists
echo "Checking if snapshot $SNAPSHOT_NAME already exists..."

SNAPSHOT_EXISTS=$(gcloud compute snapshots list --filter="name=$SNAPSHOT_NAME" --format="value(name)")

if [ -n "$SNAPSHOT_EXISTS" ]; then
    echo "Snapshot $SNAPSHOT_NAME already exists. Skipping snapshot creation."
else
    # Create the snapshot of the disk if it doesn't exist
    echo "Creating snapshot of disk: $DISK_NAME in zone $ZONE..."
    gcloud compute disks snapshot $DISK_NAME \
        --zone=$ZONE \
        --snapshot-names=$SNAPSHOT_NAME

    # Check if the snapshot was created successfully
    if [ $? -eq 0 ]; then
        echo "Snapshot $SNAPSHOT_NAME created successfully."
    else
        echo "Error occurred while creating snapshot."
        exit 1
    fi
fi

# Create an image from the snapshot
echo "Creating image from snapshot: $SNAPSHOT_NAME..."
gcloud compute images create $IMAGE_NAME \
    --source-snapshot=$SNAPSHOT_NAME \
    --project=$PROJECT 

# Check if the image was created successfully
if [ $? -eq 0 ]; then
    echo "Image $IMAGE_NAME created successfully from snapshot."
else
    echo "Error occurred while creating image."
    exit 1
fi

# Now let's create the instance template based on the newly created image
echo "Creating instance template: $INSTANCE_TEMPLATE_NAME..."

gcloud compute instance-templates create $INSTANCE_TEMPLATE_NAME \
    --image=$IMAGE_NAME \
    --image-project=$PROJECT \
    --machine-type="e2-standard-2" \
    --network="default" \
    --tags="innovehealth" \
    --metadata=startup-script='#!/bin/bash
      # Install Java 17
      echo "Installing Java 17..."
      sudo apt update -y
      sudo apt install -y openjdk-17-jdk
      # Change SSH port to 8734 (or another custom setup)
      sed -i "s/^#Port 22/Port 8734/" /etc/ssh/sshd_config
      # Allow traffic on port 8734 through the firewall
      ufw allow 8734/tcp
      # Restart SSH service to apply changes
      systemctl restart sshd'

# Check if the instance template was created successfully
if [ $? -eq 0 ]; then
    echo "Instance template $INSTANCE_TEMPLATE_NAME created successfully."
else
    echo "Error occurred while creating instance template."
    exit 1
fi

# Create the instance group with a min of 1 replica and max of 2 replicas
echo "Creating instance group: $INSTANCE_GROUP_NAME..."

gcloud compute instance-groups managed create $INSTANCE_GROUP_NAME \
    --base-instance-name="innovehealth-instance" \
    --template=$INSTANCE_TEMPLATE_NAME \
    --size=2 \
    --zone=$ZONE

# Check if the instance group was created successfully
if [ $? -eq 0 ]; then
    echo "Instance group $INSTANCE_GROUP_NAME created successfully."
else
    echo "Error occurred while creating instance group."
    exit 1
fi

# Set auto-scaling with a minimum of 1 replica and maximum of 2 replicas
echo "Setting up auto-scaling for the instance group..."

gcloud compute instance-groups managed set-autoscaling $INSTANCE_GROUP_NAME \
    --max-num-replicas=2 \
    --min-num-replicas=1 \
    --target-cpu-utilization=0.65 \
    --zone=$ZONE

# Verify the instance group setup
echo "Instance group $INSTANCE_GROUP_NAME setup complete. Checking the status..."
gcloud compute instance-groups managed describe $INSTANCE_GROUP_NAME --zone=$ZONE

