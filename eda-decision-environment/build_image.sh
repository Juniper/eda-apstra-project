#!/bin/bash -ex

# Change to script directory
cd "${0%/*}"

# Function to build the Docker image
build_image() {
  ansible-builder build -t apstra-eda-de -f de-builder.yml --verbosity=3
}

# Function to tag the Docker image
tag_image() {
  docker tag apstra-eda-de:latest "$REGISTRY_URL/apstra-eda-de:$TAG"
}

# Function to push the Docker image
push_image() {
  docker push "$REGISTRY_URL/apstra-eda-de:$TAG"
  echo "Decision environment image is pushed at $REGISTRY_URL/apstra-eda-de:$TAG"
}

DEFAULT_REGISTRY_URL="s-artifactory.juniper.net/atom-docker/eda"

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
ansible-galaxy collection download junipernetworks.eda==$collection_version
mv collections/junipernetworks-eda-*.tar.gz collections/junipernetworks-eda.tar.gz

# Build the image
build_image

# Tag the image
tag_image "$REGISTRY_URL" "$TAG"

# Push the image
push_image "$REGISTRY_URL" "$TAG"
