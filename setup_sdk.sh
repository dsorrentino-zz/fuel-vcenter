#!/bin/sh

function install_packages 
{
  local RETURN_CODE=0
  echo "Installing pre-requisite packages:"
  echo ""
  yum install ${INSTALL_LINUX_PACKAGES} -y
  echo ""

  for PKG in ${INSTALL_LINUX_PACKAGES}
  do
    rpm -q ${PKG} >/dev/null 2>&1
    if [[ $? -ne 0 ]]
    then
      echo "Error: There was a problem installing package: ${PKG}"
      echo "       Investigate/correct the issue and try re-running $0."
      (( RETURN_CODE=${RETURN_CODE} + 1 ))
    fi
  done

  if [[ ${RETURN_CODE} -ne 0 ]]
  then
    echo "Unable to continue installation."
  fi

  return ${RETURN_CODE}
}

function install_perl_modules
{
  local RETURN_CODE=0
  for MODULE in ${PERL_MODULES}
  do
    echo "Installing CPAN Module: ${MODULE}"
    cpan ${MODULE}
    (( RETURN_CODE=${RETURN_CODE} + $? ))
  done

  if [[ ${RETURN_CODE} -ne 0 ]]
  then
    echo "Unable to continue installation."
  fi

  return ${RETURN_CODE}
}

function extract_SDK
{
  local RETURN_CODE=0
  echo "Extracting ${INSTALL_SDK_TGZ}"
  tar -zxvf vSphere_SDK/${INSTALL_SDK_TGZ} >/dev/null 2>&1
  RETURN_CODE=$?

  if [[ ${RETURN_CODE} -ne 0 ]]
  then
    echo "Error: Extracting the SDK failed."
  fi

  return ${RETURN_CODE}
}

function install_SDK
{
  local RETURN_CODE=0
  echo ""
  echo "Starting installation, but you will need to hit enter and space through the user agreement."
  echo ""
  START_DIRECTORY=$(pwd)
  cd vmware-vsphere-cli-distrib

  ./vmware-install.pl -d
  RETURN_CODE=$?

  cd ${START_DIRECTORY}

  if [[ ${RETURN_CODE} -ne 0 ]]
  then
    echo "Error: Installing the SDK failed."
  fi
  return ${RETURN_CODE}
}

function clean_up
{
  echo "Cleaning up installer."
  rm -rf vmware-vsphere-cli-distrib
  return 0
}

function success
{
  echo "vSphere Perl SDK installed successfully."
  return 0
}

###############################################################

. etc/default.cfg

if [[ "$(whoami)" != 'root' ]]
then
  echo "Error:  Must be run as root."
  exit 1
fi

install_packages && extract_SDK && install_SDK && clean_up && success

exit
