#!/bin/sh

# Load variables for this installation

# Clean previous deployments

#rm -f etc/deployment.cfg*

START_DIRECTORY=$(pwd)
DEPLOYMENT_SCRIPT=fuel-vcenter.pl

##########################################
# Generate deployment configuration file
##########################################

cd scripts
#./${DEPLOYMENT_SCRIPT} --fuel_action create_config
RC=$?
cd ${START_DIRECTORY}

if [[ ${RC} -ne 0 ]]
then
  exit ${RC}
fi

############################
# Upload Fuel ISO to vCenter
############################

if [[ -r etc/deployment.cfg ]]
then
  . etc/deployment.cfg

  echo "##### UPLOAD ISO #####"
  echo "Uploading ${FUEL_ISO} to [${VCENTER_DATASTORE}] MIRANTIS/${FUEL_ISO}"
  echo "This may take a couple minutes..."

  cd scripts
#  ./${DEPLOYMENT_SCRIPT} --fuel_action upload_iso
  RC=$?
  cd ${START_DIRECTORY}

  if [[ ${RC} -ne 0 ]]
  then
    exit ${RC}
  fi

  echo "#####################"
  echo "##### CREATE VM #####"
  echo "#####################"
  echo "Creating virtual machine: ${FUEL_VM}"

  cd scripts
  ./${DEPLOYMENT_SCRIPT} --fuel_action create_fuel
  RC=$?
  cd ${START_DIRECTORY}

  if [[ ${RC} -ne 0 ]]
  then
    exit ${RC}
  fi
else
  echo "Error: The deployment.cfg file was not generated.  Check credentials and permissions in vCenter then try again."
fi
