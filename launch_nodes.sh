#!/bin/sh

START_DIRECTORY=$(pwd)
DEPLOYMENT_SCRIPT=fuel-vcenter.pl

# Clean previous deployments

echo "##########################"
echo "# CREATE OPENSTACK NODES #"
echo "##########################"

cd scripts
./${DEPLOYMENT_SCRIPT} --fuel_action create_nodes
cd ${START_DIRECTORY}
