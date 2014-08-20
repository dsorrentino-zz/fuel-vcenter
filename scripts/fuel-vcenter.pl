#!/usr/bin/perl -w

use strict;
use warnings;

use lib "/usr/lib/vmware-vcli/apps/";

use VMware::VIRuntime;
use VMware::VILib;
use URI::URL;
use URI::Escape;

use Switch;
use File::Copy qw(copy);


use Data::Dumper;


$Util::script_version = "1.0";

my %opts = (
        'fuel_action' => {
                type => "=s",
                help => "Action you want to take.  Valid actions are: create_fuel, start_fuel, create_nodes, start_nodes, create_config, show_config, upload_iso",
                required => 1,
        },
        'deploycfg' => {
                type => "=s",
                help => "Identify the configuration file you want to use. Default: ../deployment.cfg (OPTIONAL)",
                required => 0,
        },
);

# Declare global variables
our (%DeployConfig, $datacenter_view, $host_view);
our %required_fields = ('VCENTER_SERVER' => 'The host/IP of the vCenter Server you are connecting to', 
                        'VCENTER_USERNAME' => 'The username used to connect to vCenter', 
                        'VCENTER_PASSWORD' => 'The password used to connect to vCenter', 
                        'INSTALL_FUEL_ISO' => 'The filename of the Mirantis OpenStack ISO', 
                        'VCENTER_FUEL_VM' => 'The name to be used for the Fuel VM', 
                        'VCENTER_NODE_VM' => 'The prefix name to be used for the OpenStack node VMs',
                        'FUEL_VCPU' => 'The number of vCPUs to allocate to the Fuel Node',
                        'FUEL_MEMORY_MB' => 'The amount of memory to allocate to the Fuel Node',
                        'FUEL_DISK_MB' => 'The amount of disk space to allocate to the Fuel Node',
                        'FUEL_PUBLICPG' =>  'The portgroup in vCenter to be used for Fuel eth1 to tunnel into the VM',
                        'OPENSTACK_CONTROLLER_COUNT' => 'The number of OpenStack Controller VMs to create',
                        'OPENSTACK_CONTROLLER_VCPU' => 'The number of vCPUs to allocate to a Controller Node',
                        'OPENSTACK_CONTROLLER_MEMORY_MB' => 'The amount of memory to allocate to a Controller Node',
                        'OPENSTACK_CONTROLLER_DISK_MB' => 'The amount of disk space to allocate to a Controller Node',
                        'OPENSTACK_OTHER_COUNT' => 'The number of non-Controller OpenStack VMs to create',
                        'OPENSTACK_OTHER_VCPU' => 'The number of vCPUs to allocate to a non-Controller Node',
                        'OPENSTACK_OTHER_MEMORY_MB' => 'The amount of memory to allocate to a non-Controller Node',
                        'OPENSTACK_OTHER_DISK_MB' => 'The amount of disk space to allocate to a non-Controller Node',
                        'VCENTER_DC' => 'The datacenter in vCenter you will create the Fuel environment in', 
                        'VCENTER_HOST' => 'The host in vCenter you will create the Fuel environment on', 
                        'VCENTER_DATASTORE' => 'The datastore used to store the ISO and the Fuel environment VMDK files', 
                        'VCENTER_ADMINPG' => 'The portgroup in vCenter to be used for OpenStack Admin and PXE traffic', 
                        'VCENTER_VMPG' => 'The portgroup in vCenter to be used for private VM traffic', 
                        'VCENTER_STORAGEPG' => 'The portgroup in vCenter to be used for iSCSI Storage traffic', 
                        'VCENTER_MGMTPG' => 'The portgroup in vCenter to be used for Management Traffic'
                        );

Opts::add_options(%opts);

# validate options, and connect to the server
Opts::parse();

load_deployment_config(Opts::get_option('deploycfg'));

Opts::validate();

print "Connecting to vCenter.\n";

Util::connect();

my $action = Opts::get_option('fuel_action');

switch (Opts::get_option('fuel_action'))
{
  case ('create_config')
  {
    select_config('Datacenter');
    select_config('Host');
    select_config('Datastore');
    select_config('Portgroup', 'fuel_public');
    select_config('Portgroup', 'admin');
    select_config('Portgroup', 'vm');
    select_config('Portgroup', 'storage');
    select_config('Portgroup', 'management');
    write_config($DeployConfig{'config_file'});
  }
  case ('show_config')
  {
    show_deployment_options();
  }
  case ('create_fuel')
  {
    validate_deployment_config();
    create_fuel_vm();
  }
  case ('start_fuel')
  {
    validate_deployment_config();
    power_toggle_vm($DeployConfig{'VCENTER_FUEL_VM'}, 'on');
  }
  case ('stop_fuel')
  {
    validate_deployment_config();
    power_toggle_vm($DeployConfig{'VCENTER_FUEL_VM'}, 'off');
  }
  case ('create_nodes')
  {
    validate_deployment_config();
    create_openstack_vms($DeployConfig{'OPENSTACK_CONTROLLER_COUNT'}, $DeployConfig{'OPENSTACK_OTHER_COUNT'});
  }
  case ('start_nodes')
  {
    validate_deployment_config();
    power_toggle_nodes($DeployConfig{'OPENSTACK_CONTROLLER_COUNT'}, $DeployConfig{'OPENSTACK_OTHER_COUNT'}, 'on');
  }
  case ('stop_nodes')
  {
    validate_deployment_config();
    power_toggle_nodes($DeployConfig{'OPENSTACK_CONTROLLER_COUNT'}, $DeployConfig{'OPENSTACK_OTHER_COUNT'}, 'off');
  }
  case ('upload_iso')
  {
    validate_deployment_config();
    upload_mos_iso();
  }
}



############ SUB-ROUTINES ############

sub load_deployment_config {
  print "------------------------------------\n";
  print "Loading deployment options\n";
  print "------------------------------------\n\n";

  foreach my $required_field (keys(%required_fields))
  {
    $DeployConfig{$required_field} = '';
  }

  # Load default settings
  open (CONFIG, '../etc/default.cfg');

  while (<CONFIG>) {
    chomp;                  # no newline
    s/#.*//;                # no comments
    s/^\s+//;               # no leading white
    s/\s+$//;               # no trailing white
    next unless length;     # anything left?
    my ($var, $value) = split(/\s*=\s*/, $_, 2);
    if (index($value, ' ') != -1)
    {
      $value =~ s/^[\'\"]//g;
      $value =~ s/[\'\"]//g;
    }
    $DeployConfig{$var} = $value;
  } 
  close(CONFIG);

  my $configuration_file = Opts::get_option('deploycfg');

  if (! defined $configuration_file &&  -e '../etc/deployment.cfg')
  {
    $configuration_file = '../etc/deployment.cfg';
  }

  if (defined $configuration_file)
  {
    open (CONFIG, $configuration_file);

    while (<CONFIG>) {
      chomp;                  # no newline
      s/#.*//;                # no comments
      s/^\s+//;               # no leading white
      s/\s+$//;               # no trailing white
      next unless length;     # anything left?
      my ($var, $value) = split(/\s*=\s*/, $_, 2);
      if (index($value, ' ') != -1)
      {
        $value =~ s/^[\'\"]//g;
        $value =~ s/[\'\"]//g;
      }
      if ($value ne '')
      {
        $DeployConfig{$var} = $value;
      }
    } 
    close(CONFIG);
    $DeployConfig{'config_file'} = $configuration_file;
  }
  else
  {
    $DeployConfig{'config_file'} = '../etc/deployment.cfg';
  }

  my $user_opt = Opts::get_option('username') || '';
  my $pass_opt = Opts::get_option('password') || '';
  my $server_opt = (Opts::get_option('server') eq 'localhost') ? $DeployConfig{'VCENTER_SERVER'} : Opts::get_option('server');

  if ($user_opt eq '' && $DeployConfig{'VCENTER_USERNAME'} eq '')
  {
    print "vCenter username not provided.  Required for configuration.\n";
    while (1)
    {
      print " vCenter user: ";
      $user_opt = <STDIN>;
      chomp $user_opt;
      if ($user_opt ne '')
      {
        last;
      }
      else
      {
        print "Invalid entry.  vCenter user is a required parameter. Use CTRL-C to abort.\n";
      }
    }
  }
  else
  {
    $user_opt = ($user_opt eq '') ? $DeployConfig{'VCENTER_USERNAME'} : $user_opt;
  }
  

  if ($pass_opt eq '' && $DeployConfig{'VCENTER_PASSWORD'} eq '')
  {
    print "vCenter password not provided.  Required for configuration.\n";
    while (1)
    {
      print " vCenter password: ";
      $pass_opt = <STDIN>;
      chomp $pass_opt;
      if ($pass_opt ne '')
      {
        last;
      }
      else
      {
        print "Invalid entry.  vCenter password is a required parameter. Use CTRL-C to abort.\n";
      }
    }
  }
  else
  {
    $pass_opt = ($pass_opt eq '') ? $DeployConfig{'VCENTER_PASSWORD'} : $pass_opt;
  }

  if ($server_opt eq '' && $DeployConfig{'VCENTER_SERVER'} eq '')
  {
    print "vCenter server not provided or set to localhost.  Please re-enter it to confirm the server..\n";
    while (1)
    {
      print " vCenter server: ";
      $server_opt = <STDIN>;
      chomp $server_opt;
      if ($server_opt ne '')
      {
        last;
      }
      else
      {
        print "Invalid entry.  vCenter server is a required parameter. Use CTRL-C to abort.\n";
      }
    }
  }
  else
  {
    $server_opt = ($server_opt eq '') ? $DeployConfig{'VCENTER_SERVER'} : $server_opt;
  }

  $DeployConfig{'VCENTER_USERNAME'} = $user_opt;
  $DeployConfig{'VCENTER_PASSWORD'} = $pass_opt;
  $DeployConfig{'VCENTER_SERVER'} = $server_opt;
  Opts::set_option('username', $DeployConfig{'VCENTER_USERNAME'});
  Opts::set_option('password', $DeployConfig{'VCENTER_PASSWORD'});
  Opts::set_option('server', $DeployConfig{'VCENTER_SERVER'});
  
  if (defined $DeployConfig{'VCENTER_SERVER'} &&  $DeployConfig{'VCENTER_SERVER'} ne '')
  {
    Opts::set_option('server', $DeployConfig{'VCENTER_SERVER'});
  }
  else
  {
    print "Warning: VCENTER_SERVER not set in  $configuration_file.  Defaulting to " . Opts::get_option('server') . ".\n";
    $DeployConfig{'VCENTER_SERVER'} =  Opts::get_option('server');
  }
  print "Configuration loaded!\n";
}

sub select_config {
  my ($entity_type, $entity_info) = @_;
  print "******************************\n";
  for (my $garbage = 0; $garbage < ((19 - (length($entity_type))) / 2); $garbage++)
  {
    print ' ';
  }
  print $entity_type . " Selection\n";
  print "******************************\n";
  print "Querying vCenter, one moment please...\n\n";

  my ($entity_views, $config_setting, $config_description);

  switch ($entity_type) {
    case('Datacenter')
    {
      $config_setting = 'VCENTER_DC';
      $entity_views =  Vim::find_entity_views(view_type => 'Datacenter', properties => ['name']);
      $config_description = "This is the datacenter within vCenter that you want to deploy Fuel & OpenStack nodes\n" .
                            "to.  The user \"" .  $DeployConfig{'VCENTER_USERNAME'} . "\" should have appropriate permissions on this\n" .
                            "datacenter to create virtual machines.\n\n";
    }
    case('Host')
    {
      $config_setting = 'VCENTER_HOST';
      $entity_views =  Vim::find_entity_views(view_type => 'HostSystem', begin_entity => $datacenter_view);
      $config_description = "This is the host within vCenter that you want to deploy Fuel & OpenStack nodes\n" .
                            "to.  The user \"" .  $DeployConfig{'VCENTER_USERNAME'} . "\" should have appropriate permissions on this\n" .
                            "to create virtual machines as well as see associated networks and write permissions\n" .
                            "to associated datastores.\n\n";
    }
    case ('Datastore')
    {
      my $host_datastores = $host_view->datastore;
      my @ds_array = @$host_datastores;
      $entity_views =  Vim::get_views(mo_ref_array => \@ds_array);

      $config_setting = 'VCENTER_DATASTORE';
      $config_description = "This is the datastore within vCenter that you want to Fuel & the OpenStack nodes\n" .
                            "to store their data on.  The user " .  $DeployConfig{'VCENTER_USERNAME'} . " should have appropriate\n" .
                            "permissions on this datastore & the datastore should have enough space to store the \n" .
                            "Mirantis OpenStack ISO as well as associated VM files.\n\n";
    }
    case ('Portgroup')
    {
      my $all_entity_views;
      switch ($entity_info)
      {
        case ('admin')
        {
          $config_setting = 'VCENTER_ADMINPG';
          $config_description = "This is the portgroup within vCenter that you want Fuel & the OpenStack nodes\n" .
                                "to utilize for ADMINISTRATIVE traffic.  Please note, this network will also be\n" .
                                "used as the PXE boot network for the OpenStack nodes in your environment,\n" .
                                "ie eth0 on the Fuel node.\n\n";
        }
        case ('management')
        {
          $config_setting = 'VCENTER_MGMTPG';
          $config_description = "This is the portgroup within vCenter that you want the OpenStack Controller nodes\n" .
                                "to utilize for MANAGEMENT traffic.\n\n";
        }
        case ('vm')
        {
          $config_setting = 'VCENTER_VMPG';
          $config_description = "This is the portgroup within vCenter that you want your OpenStack environment\n" .
                                "to utilize for VM traffic. This will also be eth1 on the Fuel node.\n\n";
        }
        case ('storage')
        {
          $config_setting = 'VCENTER_STORAGEPG';
          $config_description = "This is the portgroup within vCenter that you want your OpenStack environment\n" .
                                "to utilize for STORAGE traffic.\n\n";
        }
        case ('fuel_public')
        {
          $config_setting = 'FUEL_PUBLICPG';
          $config_description = "This is the portgroup within vCenter that you want configured on eth1 of the Fuel Node.\n" .
                                "The expectation is this is connected to a network with DHCP enabled on it to give the\n" .
                                "Fuel node an IP that you can reach it on post-deployment.\n\n";
        }
      }

      my $host_networks = $host_view->network;
      foreach my $network (@$host_networks)
      {
        my $network_view =  Vim::find_entity_views(view_type => 'DistributedVirtualPortgroup', filter => {key => $network->value});
        push(@$all_entity_views, @$network_view);
      }

      # Remove UpLink ports as valid targets for NIC interfaces
      #
      # There has to be a better way to do this, in the loop above this one
      # but I couldn't get it to work without it complaining about unblessed
      # references so I will come back and revisit this if I have time.

      foreach my $entity (@$all_entity_views)
      {
        if (!defined $entity->tag)
        {
          push(@$entity_views, $entity);
        }
      }
    }
  }

  print $config_description;

  my $current_config = $DeployConfig{$config_setting} eq '' ?  @$entity_views[0]->name : $DeployConfig{$config_setting};

  my $selection_ndx = 1;
  my $selected_entity = -1;
  foreach my $entity (@$entity_views)
  {
    print "[" . $selection_ndx . "] " . $entity->name;
    if ($current_config eq $entity->name)
    {
      print ' (DEFAULT)';
      $selected_entity = $selection_ndx - 1;
    }
    print "\n";
    $selection_ndx++;
  }

  while (1)
  {
    print "\nEnter the # of the " . lc($entity_type) . " to use.  Press <ENTER> to accept the default, enter 0 to exit: ";
    my $user_entry = <STDIN>;
    chomp $user_entry;
    if ($user_entry eq '')
    {
      last;
    }
    elsif ($user_entry =~ /^[+-]?\d+$/ )
    {
      if ($user_entry < 0 || $user_entry > @$entity_views)
      {
        print "Error: Invalid selection.\n";
      }
      else
      {
        $selected_entity = $user_entry - 1;
        last;
      }
    }
  }

  if ($selected_entity < 0)
  {
    print "\nExit program selected.\n\n";
    exit(9);
  }
  switch ($entity_type)
  {
    case ('Datacenter')
    {
      $datacenter_view = @$entity_views[$selected_entity];
    }
    case ('Host')
    {
      $host_view = @$entity_views[$selected_entity];
    }
  }
  $selected_entity = @$entity_views[$selected_entity]->name;
  print "\nSelected " . lc($entity_type) . ": " . $selected_entity . "\n\n";
  $DeployConfig{$config_setting} = $selected_entity;
}

sub show_deployment_options {
  print "------------------------------------\n";
  print "Displaying loaded deployment options\n";
  print "------------------------------------\n\n";
  foreach my $key (sort(keys(%DeployConfig)))
  {
    my $details = (exists($required_fields{$key})) ? $required_fields{$key} : '';
    $details = ($details eq '') ? '' : "($details)";
    print $key . " = " . $DeployConfig{$key} . " " . $details . "\n";
  }

}
sub validate_deployment_config {
  print "------------------------------------\n";
  print "Validating loaded deployment options\n";
  print "------------------------------------\n\n";
  my ($error_flag, $error_message);
  $error_flag = 0;
  if (! -e $DeployConfig{'config_file'})
  {
    $error_flag = 1;
    $error_message .= "# You appear to be missing your configuration file:\n";
    $error_message .= "#\n";
    $error_message .= "# " . $DeployConfig{'config_file'} . "\n";
    $error_message .= "#\n";
    $error_message .= "# Please generate this file by running the following\n";
    $error_message .= "# to create a new one:\n";
    $error_message .= "#\n";
    $error_message .= "# ./fuel-vcenter.pl --fuel_action create_config\n";
  }
  else
  {
    $error_message = "# There was an issue with your configuration file\n";
    $error_message .= "#\n";
    $error_message .= "# " . $DeployConfig{'config_file'} . "\n";
    $error_message .= "#\n";
    foreach my $req_opt (keys(%required_fields))
    {
      if ($DeployConfig{$req_opt} eq '')
      {
        $error_flag = 1;
        $error_message .= "# ERROR: MISSING REQUIRED CONFIGURATION - " . $req_opt . " -> " . $required_fields{$req_opt} . "\n";
      }
    }
    $error_message .= "#\n";
    $error_message .= "# Please correct this issue either manually or generate\n";
    $error_message .= "# a new deployment configuration file by running:\n";
    $error_message .= "#\n";
    $error_message .= "# ./fuel-vcenter.pl --fuel_action create_config\n";

  }
  if ($error_flag == 1 )
  {
    print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
    print "#\n";
    print $error_message;
    print "#\n";
    print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
    print "\nExiting.\n";
    exit 1;
  }
  else
  {
    print "Loaded configuration validated!\n";
  }
}

sub write_config {
  my $configuration_file=$_[0];
  print "------------------------------------\n";
  print "Writing configuration file: $configuration_file\n";
  print "------------------------------------\n\n";

  my $file_ndx = 0;
  if ( -e $configuration_file )
  {
    while (1)
    {
      if (! -e $configuration_file . '.' . $file_ndx)
      {
        copy($configuration_file, $configuration_file . '.' . $file_ndx);
        print "\nWarning: $configuration_file exists.  Making a backup before overwriting it. Backup: $configuration_file.$file_ndx\n";
        last;
      }
      $file_ndx++;
    }
    unlink $configuration_file;
  }

  open (my $CONFIG, '>>', $configuration_file);

  print $CONFIG "######################################################\n";
  print $CONFIG "#\n";
  print $CONFIG "# This file was auto-generated by fuel-vcenter.pl\n";
  print $CONFIG "#\n";
  print $CONFIG "######################################################\n";
  print $CONFIG "\n";

  foreach my $key (sort(keys %DeployConfig))
  {
    my $value = $DeployConfig{$key};
    if (index($value, ' ') != -1)
    {
      $value = "'" . $value . "'";
    }

    print $CONFIG $key . "=" . $value . "\n";
  }
  close(CONFIG);

}

sub create_fuel_vm {
  print "------------------------------------\n";
  print "Creating Fuel VM\n";
  print "------------------------------------\n\n";
  my $vm_view = Vim::find_entity_view(view_type => 'VirtualMachine', filter =>{ 'name' => $DeployConfig{'VCENTER_FUEL_VM'}});
  if ($vm_view)
  {
     Util::trace(0, "\nError creating VM ' $DeployConfig{'VCENTER_FUEL_VM'}': "
                  . "VM ' $DeployConfig{'VCENTER_FUEL_VM'}' already exists.\n");
  }
  else
  {
    my $disksize = $DeployConfig{'FUEL_DISK_MB'} * 1024;

    create_vm($DeployConfig{'VCENTER_FUEL_VM'},$disksize, $DeployConfig{'FUEL_MEMORY_MB'}, $DeployConfig{'FUEL_VCPU'});


    print "------------------------------------\n";
    print "Configuring Fuel VM\n";
    print "------------------------------------\n\n";

    my $vm_view = Vim::find_entity_view(view_type => 'VirtualMachine', filter =>{ 'name' => $DeployConfig{'VCENTER_FUEL_VM'}});
    add_cdrom_and_attach($vm_view, $DeployConfig{'VCENTER_DATASTORE'}, 'MIRANTIS/' . $DeployConfig{'INSTALL_FUEL_ISO'});
    add_nic($vm_view, $DeployConfig{'VCENTER_ADMINPG'});  
    add_nic($vm_view, $DeployConfig{'FUEL_PUBLICPG'});  
    # Refresh view to get view with the new hardware
    $vm_view = Vim::find_entity_view(view_type => 'VirtualMachine', filter =>{ 'name' => $DeployConfig{'VCENTER_FUEL_VM'}});
    set_boot_order($vm_view, ('cdrom', 'disk', 'ethernet'));
    power_toggle_vm($vm_view->name, 'on');
  }
}

sub create_openstack_vms {
  my ($controller_count, $node_count) = @_;
  print "------------------------------------\n";
  print "Creating OpenStack Nodes\n";
  print "------------------------------------\n\n";

  print "Creating the following VM's on host \"" . $DeployConfig{'VCENTER_HOST'} . "\":\n";
  print " Controller VM's: " . $controller_count . "\n";
  print " Node VM's: " . $node_count . "\n\n";

  my $node_type = 'CTRL';
  for (my $build_count = 1; $build_count <= ($controller_count + $node_count); $build_count++)
  {
    if ($build_count > $controller_count)
    {
      $node_type = 'NODE';
    }
    my $vmname = $DeployConfig{'VCENTER_NODE_VM'} . '-' . $node_type . '-' . $build_count;
    my $disksize =  ($node_type eq 'CTRL') ? $DeployConfig{'OPENSTACK_CONTROLLER_DISK_MB'} : $DeployConfig{'OPENSTACK_OTHER_DISK_MB'};
    $disksize = $disksize * 1024;
    my $memory =  ($node_type eq 'CTRL') ? $DeployConfig{'OPENSTACK_CONTROLLER_MEMORY_MB'} : $DeployConfig{'OPENSTACK_OTHER_MEMORY_MB'};
    my $vcpu =  ($node_type eq 'CTRL') ? $DeployConfig{'OPENSTACK_CONTROLLER_VCPU'} : $DeployConfig{'OPENSTACK_OTHER_VCPU'};

    my $vm_view = Vim::find_entity_view(view_type => 'VirtualMachine', filter =>{ 'name' => $vmname});
    if ($vm_view)
    {
       Util::trace(0, "\nError creating VM '$vmname': "
                    . "VM '$vmname' already exists.\n");
    }
    else
    {
    create_vm($vmname, $disksize, $memory, $vcpu);

        $vm_view = Vim::find_entity_view(view_type => 'VirtualMachine', filter =>{ 'name' => $vmname});
        add_nic($vm_view, $DeployConfig{'VCENTER_ADMINPG'});  
        add_nic($vm_view, $DeployConfig{'VCENTER_VMPG'});  
        add_nic($vm_view, $DeployConfig{'VCENTER_STORAGEPG'});  
        add_nic($vm_view, $DeployConfig{'VCENTER_MGMTPG'});  
        # Refresh view to get view with the newly added hardware
        $vm_view = Vim::find_entity_view(view_type => 'VirtualMachine', filter =>{ 'name' => $vmname});
        set_boot_order($vm_view, ('ethernet','disk'));
        print "Successfully created and configured VM \"" . $vmname . "\".\n\n";
        power_toggle_vm($vm_view->name, 'on');
    }
  }
}

# create a virtual machine
sub create_vm {
  my ($vmname, $disksize, $memory_mb, $vcpu_count) = @_;
  
  my @vm_devices;
  my $host_view = Vim::find_entity_view(view_type => 'HostSystem', filter => {'name' => $DeployConfig{'VCENTER_HOST'}});
  if (!$host_view) 
  {
  Util::trace(0, "\nError creating VM ' $vmname': " . "Host '$DeployConfig{'VCENTER_HOST'}' not found\n");
       return;
  }

  my $datastore_path = "[" . $DeployConfig{'VCENTER_DATASTORE'} . "]";

  my $controller_vm_dev_conf_spec = create_controller_conf_spec();
  my $disk_vm_dev_conf_spec = create_virtual_disk($datastore_path, $disksize);

  push(@vm_devices, $controller_vm_dev_conf_spec);
  push(@vm_devices, $disk_vm_dev_conf_spec);

  my $files = VirtualMachineFileInfo->new(logDirectory => undef,
                                          snapshotDirectory => undef,
                                          suspendDirectory => undef,
                                          vmPathName => $datastore_path);

  my $vm_config_spec = VirtualMachineConfigSpec->new(
                                            name => $vmname,
                                            memoryMB => $memory_mb,
                                            files => $files,
                                            numCPUs => $vcpu_count,
                                            guestId => 'rhel6guest',
                                            deviceChange => \@vm_devices);
                                             
   my $datacenter_view =
        Vim::find_entity_views (view_type => 'Datacenter',
                                filter => { name => $DeployConfig{'VCENTER_DC'}});

   my $datacenter = shift @$datacenter_view;

   my $vm_folder_view = Vim::get_view(mo_ref => $datacenter->vmFolder);

   my $comp_res_view = Vim::get_view(mo_ref => $host_view->parent);

   eval {
      print "Creating VM \"" . $vmname . "\" on host \"" . $DeployConfig{'VCENTER_HOST'} . "\"...\n";
      $vm_folder_view->CreateVM(config => $vm_config_spec, pool => $comp_res_view->resourcePool);
      Util::trace(0, "  Successfully created virtual machine: '" . $vmname . "' under host " . $DeployConfig{'VCENTER_HOST'} . "\n");
    };
    if ($@) {
       Util::trace(0, "\nError creating VM '" . $vmname . "': ");
       if (ref($@) eq 'SoapFault') {
          if (ref($@->detail) eq 'PlatformConfigFault') {
             Util::trace(0, "Invalid VM config: "
                            . ${$@->detail}{'text'} . "\n");
          }
          elsif (ref($@->detail) eq 'InvalidDeviceSpec') {
             Util::trace(0, "Invalid Device config: "
                            . ${$@->detail}{'property'} . "\n");
          }
           elsif (ref($@->detail) eq 'DatacenterMismatch') {
             Util::trace(0, "DatacenterMismatch, the input arguments had entities "
                          . "that did not belong to the same datacenter\n");
          }
           elsif (ref($@->detail) eq 'HostNotConnected') {
             Util::trace(0, "Unable to communicate with the remote host,"
                         . " since it is disconnected\n");
          }
          elsif (ref($@->detail) eq 'InvalidState') {
             Util::trace(0, "The operation is not allowed in the current state\n");
          }
          elsif (ref($@->detail) eq 'DuplicateName') {
             Util::trace(0, "Virtual machine already exists.\n");
          }
          else {
             Util::trace(0, "\n" . $@ . "\n");
          }
       }
       else {
          Util::trace(0, "\n" . $@ . "\n");
       }
   }
}


# create controller configuration spec
sub create_controller_conf_spec {
   my $controller =
      ParaVirtualSCSIController->new(key => 0,
                                     device => [0],
                                     busNumber => 0,
                                     sharedBus => VirtualSCSISharing->new('noSharing'));

   my $controller_vm_dev_conf_spec =
      VirtualDeviceConfigSpec->new(device => $controller,
         operation => VirtualDeviceConfigSpecOperation->new('add'));
   return $controller_vm_dev_conf_spec;
}


# create device config spec for a disk
sub create_virtual_disk {
  my ($datastore_path, $disksize) = @_;

  my $disk_backing_info =
      VirtualDiskFlatVer2BackingInfo->new(diskMode => 'persistent',
                                          fileName => $datastore_path,
                                          thinProvisioned => 1);

  my $disk = VirtualDisk->new(backing => $disk_backing_info,
                              controllerKey => 0,
                              key => 0,
                              unitNumber => 0,
                              capacityInKB => $disksize);

  my $disk_vm_dev_conf_spec =
     VirtualDeviceConfigSpec->new(device => $disk,
              fileOperation => VirtualDeviceConfigSpecFileOperation->new('create'),
              operation => VirtualDeviceConfigSpecOperation->new('add'));
  return $disk_vm_dev_conf_spec;
}

sub add_nic {
  my ($vm_view, $portgroup) = @_;

  my $vmname = $vm_view->name;

  my $config_spec_operation = VirtualDeviceConfigSpecOperation->new('add');

  my $dvportgroup_view = Vim::find_entity_view( view_type => 'DistributedVirtualPortgroup',
                                                filter => { 'name' => $portgroup },
                                              );
  my $port_group_key = $dvportgroup_view->key;

  # Retrieve DVS uuid
  my $dvs_entity_key = $dvportgroup_view->config->distributedVirtualSwitch;
  my $dvs_entity = Vim::get_view(mo_ref => $dvs_entity_key);
  my $dvs_uuid = $dvs_entity->uuid;
  my $nic_connection = new DistributedVirtualSwitchPortConnection(switchUuid => $dvs_uuid, portgroupKey => $port_group_key);
  my $backing_info = VirtualEthernetCardDistributedVirtualPortBackingInfo->new(port => $nic_connection);

  my $device = VirtualVmxnet3->new(key => -1, backing => $backing_info);

  if($device)
  {
    my $devspec = VirtualDeviceConfigSpec->new(operation => $config_spec_operation, device => $device);
    my $vm_change_spec = VirtualMachineConfigSpec->new(deviceChange => [ $devspec ] );
    my ($task_ref,$message);

    eval
    {
      print "Adding new VMXNet3 vNic to \"$vmname\" and connecting it to portgroup \"$portgroup\"...\n";
      $task_ref = $vm_view->ReconfigVM_Task(spec => $vm_change_spec);
      $message = "  Successfully reconfigured \"$vmname\"";
      &get_task_status($task_ref, $message);
    };
    if($@)
    {
      print "Error: " . $@ . "\n";
    }

  }
}

sub get_task_status {
  my ($task_ref,$message) = @_;

  my $task_view = Vim::get_view(mo_ref => $task_ref);
  my $taskinfo = $task_view->info->state->val;
  while (1) 
  {
    my $info = $task_view->info;
    if ($info->state->val eq 'success') 
    {
      print $message,"\n";
      last;
    } 
    elsif ($info->state->val eq 'error') 
    {
      my $soap_fault = SoapFault->new;
      $soap_fault->name($info->error->fault);
      $soap_fault->detail($info->error->fault);
      $soap_fault->fault_string($info->error->localizedMessage);
      die "$soap_fault\n";
    }
    sleep 5;
    $task_view->ViewBase::update_view_data();
  }
}

sub add_cdrom_and_attach
{
  my ($vm_view, $datastore, $iso) = @_;
  my $iso_path = "[" . $datastore . "] " . $iso;
  my $ds;
  my $host = Vim::get_view(mo_ref => $vm_view->runtime->host);
  my $datastores =  Vim::get_views(mo_ref_array => $host->datastore);
  foreach(@$datastores)
  {
    if($_->summary->name eq $datastore)
    {
      $ds = $_;
    }
  }

  my $vmname = $vm_view->name;
  my $name = 'CD-ROM';

  my $config_spec_operation = VirtualDeviceConfigSpecOperation->new('add');
  my $controller = find_ide_controller_device(vm => $vm_view);
  my $controllerKey = $controller->key;
  my $unitNumber = (defined $controller->device) ? $#{$controller->device} + 1 : 0;

  my $cd_backing_info = VirtualCdromIsoBackingInfo->new(datastore => $ds, fileName => $iso_path);

  my $description = Description->new(label => $name, summary => '111');
  my $dev_con_info = VirtualDeviceConnectInfo->new(startConnected => 'true', connected => 'true', allowGuestControl => 'false');

  my $cd = VirtualCdrom->new(controllerKey => $controllerKey,
                             connectable => $dev_con_info,
                             unitNumber => $unitNumber,
                             key => -1,
                             deviceInfo => $description,
                             backing => $cd_backing_info);
  if($cd)
  {
    my $devspec = VirtualDeviceConfigSpec->new(operation => $config_spec_operation, device => $cd);
    my $vm_change_spec = VirtualMachineConfigSpec->new(deviceChange => [ $devspec ] );
    my ($task_ref,$msg);

    eval
    {
      print "Adding new CD-ROM to \"$vmname\"...\n";
      $task_ref = $vm_view->ReconfigVM_Task(spec => $vm_change_spec);
      $msg = "  Successfully reconfigured \"$vmname\"";
      &get_task_status($task_ref,$msg);
    };
    if($@)
    {
      print "Error: " . $@ . "\n";
    }
  }
}

sub find_ide_controller_device {
   my %args = @_;
   my $vm = $args{vm};
   my $devices = $vm->config->hardware->device;
   foreach my $device (@$devices) {
      my $class = ref $device;
      if($class->isa('VirtualIDEController')) {
         return $device;
      }
   }
   return undef;
}

sub set_boot_order
{
  my ($vm_view, @requested_boot_order) = @_;
  my $vmname = $vm_view->name;

  my $network_view =  Vim::find_entity_views(view_type => 'DistributedVirtualPortgroup',  filter => {name => $DeployConfig{'VCENTER_ADMINPG'}});
  my $pxe_network =  @$network_view[0]->key;

  my $disk_key = ''; 
  my $nic_key = ''; 


  my $vm_devices = $vm_view->config->hardware->device;
  foreach my $vm_device (@$vm_devices)
  {
    if ($disk_key eq '' && $vm_device->isa('VirtualDisk'))
    {
      $disk_key = $vm_device->key;
    }
    if ($nic_key eq '' && $vm_device->isa('VirtualEthernetCard'))
    {
      if ($vm_device->backing->port->portgroupKey eq $pxe_network)
      {
        $nic_key = $vm_device->key;
      }
    }
  }
  my @boot_order;
  foreach my $boot_device (@requested_boot_order)
  {
    switch ($boot_device)
    {
      case ('cdrom')
      {
        $boot_device = VirtualMachineBootOptionsBootableCdromDevice->new();
      }
      case ('disk')
      {
        $boot_device =  VirtualMachineBootOptionsBootableDiskDevice->new(deviceKey => $disk_key);
      }
      case ('ethernet')
      {
        if ($nic_key ne '')
        {
          $boot_device = VirtualMachineBootOptionsBootableEthernetDevice->new(deviceKey => $nic_key);
        }
      }
    }
    push (@boot_order, $boot_device);
  }

  my $boot_options = VirtualMachineBootOptions->new(bootOrder => \@boot_order);
  my $config_spec = VirtualMachineConfigSpec->new(bootOptions => $boot_options);

  my ($task_ref, $message);
  eval
  {
    print "Updating boot order on \"$vmname\"...\n";
    $task_ref = $vm_view->ReconfigVM_Task(spec => $config_spec);
    $message = "  Successfully reconfigured \"$vmname\"";
    &get_task_status($task_ref,$message);
  };
  if($@)
  {
    print "Error: " . $@ . "\n";
  }
}

sub power_toggle_nodes
{
  my ($controller_count, $node_count, $power_state) = @_;
  print "------------------------------------\n";
  print (($power_state eq 'on') ? "Starting" : "Stopping");
  print " Nodes\n";
  print "------------------------------------\n\n";

  print " Controller VM's: " . $controller_count . "\n";
  print " Node VM's: " . $node_count . "\n\n";

  my $node_type = 'CTRL';
  for (my $build_count = 1; $build_count <= ($controller_count + $node_count); $build_count++)
  {
    if ($build_count > $controller_count)
    {
      $node_type = 'NODE';
    }
    my $vmname = $DeployConfig{'VCENTER_NODE_VM'} . '-' . $node_type . '-' . $build_count;
    power_toggle_vm($vmname, $power_state);
  }
}

sub power_toggle_vm
{
  my ($vmname, $power_state) = @_;

  my $vm_view = Vim::find_entity_view(view_type => 'VirtualMachine', filter =>{ 'name' => $vmname});
  my $current_power_state = $vm_view->runtime->powerState->val;

  if ($vm_view)
  {
    my $task_ref;
    switch ($power_state)
    {
      case ('on')
      {
        if ($current_power_state ne 'poweredOn')
        {
          print "Powering on VM: " . $vmname . "\n";
          $task_ref = $vm_view->PowerOnVM_Task();
        }
        else
        {
          print "Warning: VM " . $vmname . " is already powered on. Nothing to do.\n";
        }
      }
      case ('off')
      {
        if ($current_power_state ne 'poweredOff')
        {
          print "Powering off VM: " . $vmname . "\n";
          $task_ref = $vm_view->PowerOffVM_Task();
        }
        else
        {
          print "Warning: VM " . $vmname . " is already powered off. Nothing to do.\n";
        }
      }
      case ('suspend')
      {
        if ($current_power_state ne 'suspended')
        {
          print "Suspending VM: " . $vmname . "\n";
          $task_ref = $vm_view->SuspendVM_Task();
        }
        else
        {
          print "Warning: VM " . $vmname . " is already suspended. Nothing to do.\n";
        }
      }
    }
    if ($task_ref)
    {
      &get_task_status($task_ref,"  Successfully changed power state of $vmname.");
    }
  }
}

sub upload_mos_iso
{

  my $service = Vim::get_vim_service();
  my $service_url = URI::URL->new($service->{vim_soap}->{url});
  my $user_agent = $service->{vim_soap}->{user_agent};

  $service_url =~ s/\/sdk\/webService//g;
  my $url_string = $service_url . "/folder/MIRANTIS/" . $DeployConfig{'INSTALL_FUEL_ISO'} . "?dcPath=" . $DeployConfig{'VCENTER_DC'} . "&dsName=" . $DeployConfig{'VCENTER_DATASTORE'};
  utf8::downgrade($url_string);
  my $url = URI::URL->new($url_string);
  my $request = HTTP::Request->new("PUT", $url);

  print "Uploading file ISO/" . $DeployConfig{'INSTALL_FUEL_ISO'} . " to [" . $DeployConfig{'VCENTER_DATASTORE'} . "] MIRANTIS/" . $DeployConfig{'INSTALL_FUEL_ISO'} . "\n";
  print "Start: " . `date` . "\n";
  $request->header('Content-Type', 'application/octet-stream');
  $request->header('Content-Length', -s "../ISO/" . $DeployConfig{'INSTALL_FUEL_ISO'});


  open(CONTENT, '< :raw', "../ISO/" . $DeployConfig{'INSTALL_FUEL_ISO'});
  sub content_source {
      my $buffer;
      my $num_read = read(CONTENT, $buffer, 102400);
      if ($num_read == 0) {
         return "";
      } else {
         return $buffer;
      }
  }
  $request->content(\&content_source);
  my $response = $user_agent->request($request);

  close(CONTENT);
  print "End: " . `date` . "\n";
}
