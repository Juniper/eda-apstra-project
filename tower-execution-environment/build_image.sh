#!/bin/bash -ex

# Change to script directory
cd "${0%/*}"

# Make sure credentials are set
if [[ -z "$RH_USERNAME" || -z "$RH_PASSWORD" ]]; then
  echo "Please set RH_USERNAME and RH_PASSWORD environment variables (perhaps in .env file)"
  exit 1
fi

# Function to build the Docker image
build_image() {
  ansible-builder build -t apstra-ee -f ee-builder.yml --verbosity=3 --build-arg RH_USERNAME="$RH_USERNAME" --build-arg RH_PASSWORD="$RH_PASSWORD"
}

# Function to tag the Docker image
tag_image() {
  docker tag apstra-ee:latest "$REGISTRY_URL/apstra-ee:$TAG"
}

# Function to push the Docker image
push_image() {
  docker push "$REGISTRY_URL/apstra-ee:$TAG"
  echo "Decision environment image is pushed at $REGISTRY_URL/apstra-ee:$TAG"
}

DEFAULT_REGISTRY_URL="s-artifactory.juniper.net/atom-docker/ee"

if [ $# -eq 1 ]; then
  echo "Using registry url as $DEFAULT_REGISTRY_URL and tag $1"
  REGISTRY_URL=$DEFAULT_REGISTRY_URL
  TAG=$1
else
  echo "Using registry url as $1 and tag $2"
  REGISTRY_URL=$1
  TAG=$2
fi

# Download our local EDA dependency
rm -rf collections
# get the collection version from TAG
collection_version=$(echo $TAG | cut -d'-' -f 1)
ansible-galaxy collection download junipernetworks.apstra==$collection_version
mv collections/junipernetworks-apstra-*.tar.gz collections/junipernetworks-apstra.tar.gz

# Build the image
build_image

# Tag the image
tag_image "$REGISTRY_URL" "$TAG"

# Push the image
push_image "$REGISTRY_URL" "$TAG"
