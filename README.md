fuel-vcenter
============

Scripts to deploy Fuel onto a vCenter environment

Summary
=======

Within Mirantis, there has been a need to be able to deploy Mirantis OpenStack onto a vCenter deployment.
Due to this, I have written the scripts in this directory to accomplish this task.

The scripts have been run/tested from a CentOS VM on VirtualBox on my Macbook Pro against a vCenter V5.1 installation.

Currently there is a set of scripts to perform a Fuel deployment on a VirtualBox environment.  Unfortunately, there’s
a bit more to launching Fuel on a vCenter installation than there is to launch it on a VirtualBox configuration.
There’s no “run it and walk away” scenarios that I could envision here so the installation script does prompt for 
configuration details for the deployment. 

The good part is, all of those configuration details are pulled from vCenter so there’s no real guess work or 
typo’s involved when setting the configuration.

Current Known Limitations
=========================

The following are current known limitations of these scripts.  If anyone has solutions to these limitations, please feel free
to contribute.

Issue 1: Pre-establish networking

All networking that will be used for the Fuel deployment should already exist in vCenter.  The expectation is that
Distributed vSwitch Portgroups are used for all networks used in this setup. Might consider altering at a later date 
to allow the creation of the networking components, however, there’s alot of dependencies to do this and probably 
alot of work for very little reward since I don't know how often it would be used.

Issue 2: Determine when Fuel deployment completes

There is no current way to know if the Fuel node is completely booted and configured when doing the VMware deployment.  
See Issue 3 to understand why.  When the launch_fuel.sh script completes, you should login to vCenter and open a console
to the Fuel VM and watch the installation complete.  When the login appears, you can continue and execute the 
launch_nodes.sh script.

Issue 3: FuelWeb & PXE both on eth0 by default

The Fuel node deploys using eth0 as both an access interface for reaching FuelWeb as well as leveraging that 
network as a PXE boot network.  In a VMware environment this is a less than ideal configuration.  This can 
obviously be changed by entering the Fuel setup on first boot from the console, but not in an automated fashion.  
For this automated deployment, eth0 gets attached to the ADMIN portgroup.  The portgroup for eth1 is configurable 
and prompted for during configuration.

WORKAROUND: The workaround that I was using is to add a second interface is on the Fuel node VM and attach it to 
a publicly reachable network. This allowed me to SSH into the Fuel Node and then tunnel my HTTP web traffic from
port 8000 on my local machine to port 8000 on the Fuel Node. Details of this can be found below

Directory Contents
==================

setup_sdk.sh - This script is used to install the vCenter Perl SDK on your system.  It will install pre-requisite 
Linux packages and deploy the SDK.  Unfortunately I didn't see a way to automatically accept the license agreement 
of the SDK so you will need to hit the space bar through it and accept it at the end.  It is expected the CentOS 
system you are installing this on does have access to a package repository to install pre-requisites from as well 
as internet access since the SDK needs to install Perl modules from CPAN. Everything else should be automated. 

launch_fuel.sh - This script is the first script you would run after getting the SDK installed.  It leverages the 
scripts/fuel-vcenter.pl script.  This script will create the necessary deployment configuration by looking at vCenter 
and prompting you for selection items to deploy the Fuel environment to.  Next, it will upload the Mirantis OpenStack 
ISO located in the ISO/ directory. Lastly it will create and configure the Fuel Node VM in vCenter then start it.  Running 
this script again will re-load the configuration that you entered previously and you can just hit enter through the 
configuration part as all of your previous selections will be the default settings.

launch_nodes.sh - This script will create and start the nodes that Fuel can then configure as Mirantis OpenStack nodes.

etc/default.cfg - This has base default configurations for the environment.  You should edit this file first and set the 
necessary parameters in it.  If you do not provide the username, password or server, you will be prompted for this information 
the first time you run the fuel-vcenter.pl script.  This is the DEFAULT configuration settings. Once the environment is configured, 
you will also have a deployment.cfg file in the etc/ directory which contains all configuration settings specific to your environment.

scripts/fuel-vcenter.pl - This is the script that is used to perform all of the function in vCenter.  This script accesses files relative to it’s location in the directory structure (ie ..\etc\deployment.cfg or ..\ISO\MirantisOpenstack-5.0.iso, etc) so it should be executed from within the scripts directory.

ISO/ - This is the directory to contain is the MOS image used to boot the Fuel node.  The name of the file must match what you
have configured in etc/default.cfg for the INSTALL_FUEL_ISO parameter.

vSphere_SDK/ - This is the directory to contain the .tar.gz of the Perl SDK.  The name of the file must match what you have
configured in etc/default.cfg for the INSTALL_SDK_TGZ paramter.  These scripts were tested with 
VMware-vSphere-Perl-SDK-5.5.0-1384587.x86_64.tar.gz against a V5.1 vCenter Server.  The latest Perl SDK can be obtained
from here:

     https://www.vmware.com/support/developer/viperltoolkit/

Configuration
=============

The initial base configuration is stored in etc/default.cfg.  You should not remove any lines from this file, however, 
you can configure properties as necessary. The file is commented for documentation.

When you run through the configuration by executing launch_fuel.sh it will produce a runtime configuration file in the 
etc/ directory called deployment.cfg.  This file will have all of the above parameters as well as ones you are prompted to 
configure.  The options from the prompts come directly from vCenter to minimize the possibility of typo’s and/or permission issues.

Script Usage
============

Here’s a basic run down of the process:

Copy all of the files in this directory (and sub-directories) to a CentOS machine that can reach the vCenter server over 
the network.  Maintain existing file/directory structure.

Login to the CentOS machine and change into the base directory that contains the setup_sdk.sh, launch_fuel.sh 
and launch_nodes.sh script.

Next, edit the etc/default.cfg file and configure the options listed in that file. File is commented so it shouldn’t be 
too difficult to figure out.

You need to install the SDK execute the setup_sdk.sh script. When you do this, the CentOS machine should have internet 
access since it needs to pull down Perl Modules from CPAN:

./setup_sdk.sh

Next, execute the launch_fuel.sh script to configure the environment and create/start the fuel node:

./launch_fuel.sh

Login to vCenter and open a console window to the Fuel VM that was just created and monitor the Fuel install.  
When it reaches the login prompt, leave the console window up and continue.

Go back to your CentOS session and execute the launch_nodes.sh script to create and start the OpenStack nodes to be used by Fuel.

While the MOS nodes are booting, get access to the FuelWeb by utilizing the workaround detailed below.

Now you should have a Fuel environment on vCenter that you can use.

Workaround to access FuelWeb
============================

Open a console onto the deployed Fuel VM and bring up eth1:

ifup eth1

Once the interface comes up and gets assigned an IP from DHCP, use the following to see what the IP address is:

ifconfig eth1

You can then use Putty to SSH into the Fuel Node and tunnel access to your local 8000 port to the Fuel node.  
To do this, in Putty expand Connection -> SSH -> Tunnels and populate the source and destination ports:

Source Port: 8000
Destination: 10.20.0.2:8000

Click Add.

Go back to the Session setting and put in the IP address assigned to eth1 on your Fuel Node, click Open and you will connect to Fuel. 

Login with the root credentials and then you can open a browser to port 8000 on your local machine and view the FuelWeb interface:

http://127.0.0.1:8000

Additional Notes
================

The same Datastore is used to store the ISO as well as all of the VM images.  This could be changed if needed but I did 
not code for this in the current version.

There’s no test to ensure enough storage exists on the selected Datastore. This could be changed if needed but I did 
not code for this in the current version.

The Mirantis OpenStack ISO will get uploaded to the Datastore specified.  When it does, it will create a folder called 
MIRANTIS on that datastore and stick the ISO in there. This is currently hard coded.  I can change this to a variable in a 
future version if desired.

During the configuration if you are expecting to see a particular Host and it is not listed, ensure you selected the proper 
Datacenter during the previous prompt.  The list of Hosts is generated from the Hosts in the Datacenter you selected.

During the configuration if you are expecting to see a particular Datastore and it is not listed, ensure you selected the 
proper Host during the previous prompt. The list of Datastores is generated from the Datastores that the Host you selected can use.

During the configuration if you are expecting to see a particular Portgroup and it is not listed, ensure you selected the 
proper Host during the previous prompt. The list of Portgroups is generated from the Portgroups that the Host you selected 
has access to.

All VM’s are created with VMXNet3 Interfaces, Thin Provisioned Storage and Paravirtual SCSI controllers.

If a node doesn’t show up in Fuel, open a console to it.  In all my testing, I only had this happen once and I had to hit 
enter on the console for it to re-try to PXE which it did successfully.  I don’t know if it was because I was overloading 
the host I was using since this is a really, really small setup in my house.

Credits
=======

As references, on how to accomplish various tasks with the vCenter Perl SDK, I have analyzed, read the sample
script that ship with the SDK as well as reviewed the work of William Lam located here:

https://github.com/lamw/vghetto-scripts/tree/master/perl
