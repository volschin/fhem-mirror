################################################################
#
#  Copyright notice
#
#  (c) 2013 Alexander Schulz
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################

# $Id$

package main;

use strict;
use warnings;

my $VERSION = "1.5.0";

use constant {
  DATE            => "date",
  UPTIME          => "uptime",
  UPTIME_TEXT     => "uptime_text",
  FHEMUPTIME      => "fhemuptime",
  FHEMUPTIME_TEXT => "fhemuptime_text",
  IDLETIME        => "idletime",
  IDLETIME_TEXT   => "idletime_text"
};

use constant {
  CPU_FREQ     => "cpu_freq",
  CPU1_FREQ     => "cpu1_freq",
  CPU_BOGOMIPS => "cpu_bogomips",
  CPU_TEMP     => "cpu_temp",
  CPU_TEMP_AVG => "cpu_temp_avg",
  LOADAVG      => "loadavg"
};

use constant {
  RAM  => "ram",
  SWAP => "swap"
};

use constant {
  ETH0        => "eth0",
  WLAN0       => "wlan0",
  DIFF_SUFFIX => "_diff",
  FB_WLAN_STATE       => "wlan_state",
  FB_WLAN_GUEST_STATE => "wlan_guest_state",
  FB_INET_IP          => "internet_ip",
  FB_INET_STATE       => "internet_state",
  FB_N_TIME_CTRL      => "night_time_ctrl",
  FB_NUM_NEW_MESSAGES => "num_new_messages",
  FB_FW_VERSION       => "fw_version_info",
  FB_DECT_TEMP        => "dect_temp",
};

use constant FS_PREFIX => "~ ";
#use constant FS_PREFIX_N => "fs_";
my $DEFAULT_INTERVAL_BASE = 60;

sub
SYSMON_Initialize($)
{
  my ($hash) = @_;

  Log 5, "SYSMON Initialize";

  $hash->{DefFn}    = "SYSMON_Define";
  $hash->{UndefFn}  = "SYSMON_Undefine";
  $hash->{GetFn}    = "SYSMON_Get";
  $hash->{SetFn}    = "SYSMON_Set";
  $hash->{AttrFn}   = "SYSMON_Attr";
  $hash->{AttrList} = "filesystems network-interfaces user-defined disable:0,1 ".
                       $readingFnAttributes;
}
### attr NAME user-defined osUpdates:1440:Aktualisierungen:cat ./updates.txt [,<readingsName>:<Interval_Minutes>:<Comment>:<Cmd>]

sub
SYSMON_Define($$)
{
  my ($hash, $def) = @_;

  logF($hash, "Define", "$def");

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> SYSMON [M1 [M2 [M3 [M4]]]]"  if(@a < 2);

  if(int(@a)>=3)
  {
    my @na = @a[2..scalar(@a)-1];
  	SYSMON_setInterval($hash, @na);
  } else {
    SYSMON_setInterval($hash, undef);
  }

  $hash->{STATE} = "Initialized";

  #$hash->{DEF_TIME} = time() unless defined($hash->{DEF_TIME});

  SYSMON_updateCurrentReadingsMap($hash);

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{INTERVAL_BASE}, "SYSMON_Update", $hash, 0);

  #$hash->{LOCAL} = 1;
  #SYSMON_Update($hash); #-> so nicht. hat im Startvorgang gelegentlich (oft) den Server 'aufgehaengt'
  #delete $hash->{LOCAL};
  
  return undef;
}

sub
SYSMON_setInterval($@)
{
	my ($hash, @a) = @_;

	my $interval = $DEFAULT_INTERVAL_BASE;
	$hash->{INTERVAL_BASE} = $interval;

	my $p1=1;
	my $p2=1;
	my $p3=1;
	my $p4=10;

	if(defined($a[0]) && int($a[0]) eq $a[0]) {$p1 = $a[0];}
	if(defined($a[1]) && int($a[1]) eq $a[1]) {$p2 = $a[1];} else {$p2 = $p1;}
	if(defined($a[2]) && int($a[2]) eq $a[2]) {$p3 = $a[2];} else {$p3 = $p1;}
	if(defined($a[3]) && int($a[3]) eq $a[3]) {$p4 = $a[3];} else {$p4 = $p1*10;}

	$hash->{INTERVAL_MULTIPLIERS} = $p1." ".$p2." ".$p3." ".$p4;
}


my $cur_readings_map;
sub
SYSMON_updateCurrentReadingsMap($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
  my $rMap;
  
  # Map aktueller Namen erstellen
	
	# Feste Werte
	$rMap->{+DATE}               = "Date";
	$rMap->{+CPU_BOGOMIPS}       = "BogoMIPS";
	if(SYSMON_isCPUFreqRPiBBB($hash)) {
	  #$rMap->{"cpu_freq"}       = "CPU Frequenz";
	  $rMap->{"cpu_freq"}        = "CPU frequency";
	  $rMap->{"cpu1_freq"}        = "CPU frequency (second core)";
	}
	if(SYSMON_isCPUTempRPi($hash) || SYSMON_isCPUTempBBB($hash)) {
    #$rMap->{+CPU_TEMP}       = "CPU Temperatur";
    #$rMap->{"cpu_temp_avg"}  = "Durchschnittliche CPU Temperatur";
    $rMap->{+CPU_TEMP}        = "CPU temperature";
    $rMap->{"cpu_temp_avg"}   = "Average CPU temperature";
  }
  
  if(SYSMON_isSysPowerAc($hash)) {
  	#$rMap->{"power_ac_online"}  = "AC-Versorgung Status";
		#$rMap->{"power_ac_present"} = "AC-Versorgung vorhanden";
		#$rMap->{"power_ac_current"} = "AC-Versorgung Strom";
		#$rMap->{"power_ac_voltage"} = "AC-Versorgung Spannung";
		$rMap->{"power_ac_stat"}    = "AC-Versorgung Info";
		$rMap->{"power_ac_text"}    = "AC-Versorgung Info";
  }

  if(SYSMON_isSysPowerUsb($hash)) {
  	#$rMap->{"power_usb_online"}  = "USB-Versorgung Status";
		#$rMap->{"power_usb_present"} = "USB-Versorgung vorhanden";
		#$rMap->{"power_usb_current"} = "USB-Versorgung Strom";
		#$rMap->{"power_usb_voltage"} = "USB-Versorgung Spannung";
		$rMap->{"power_usb_stat"}    = "USB-Versorgung Info";
		$rMap->{"power_usb_text"}    = "USB-Versorgung Info";
  }
  
  if(SYSMON_isSysPowerBat($hash)) {
  	#$rMap->{"power_battery_online"}  = "Batterie-Versorgung Status";
		#$rMap->{"power_battery_present"} = "Batterie-Versorgung vorhanden";
		#$rMap->{"power_battery_current"} = "Batterie-Versorgung Strom";
		#$rMap->{"power_battery_voltage"} = "Batterie-Versorgung Spannung";
		$rMap->{"power_battery_stat"}    = "Batterie-Versorgung Info";
		$rMap->{"power_battery_text"}    = "Batterie-Versorgung  Info";
		$rMap->{"power_battery_info"}    = "Batterie-Versorgung  Zusatzinfo";
  }

  #$rMap->{"fhemuptime"}      = "Betriebszeit FHEM";
  #$rMap->{"fhemuptime_text"} = "Betriebszeit FHEM";
  #$rMap->{"idletime"}        = "Leerlaufzeit";
  #$rMap->{"idletime_text"}   = "Leerlaufzeit";
  #$rMap->{"loadavg"}         = "Durchschnittliche Auslastung";
  #$rMap->{"ram"}             = "RAM";
  #$rMap->{"swap"}            = "Swap";
  #$rMap->{"uptime"}          = "Betriebszeit";
  #$rMap->{"uptime_text"}     = "Betriebszeit";
  $rMap->{"fhemuptime"}      = "System up time";
  $rMap->{"fhemuptime_text"} = "FHEM up time";
  $rMap->{"idletime"}        = "Idle time";
  $rMap->{"idletime_text"}   = "Idle time";
  $rMap->{"loadavg"}         = "Load average";
  $rMap->{"loadavg_1"}       = "Load average 1";
  $rMap->{"loadavg_5"}       = "Load average 5";
  $rMap->{"loadavg_15"}      = "Load average 15";
  
  $rMap->{"ram"}             = "RAM";
  $rMap->{"ram_total"}       = "RAM total";
  $rMap->{"ram_used"}        = "RAM used";
  $rMap->{"ram_free"}        = "RAM free";
  $rMap->{"ram_free_percent"}= "RAM free %";
  
  $rMap->{"swap"}            = "swap";
  $rMap->{"swap_total"}      = "swap total";
  $rMap->{"swap_used"}       = "swap used";
  $rMap->{"swap_free"}       = "swap free";
  $rMap->{"swap_used_percent"}= "swap used %";
  
  $rMap->{"uptime"}          = "System up time";
  $rMap->{"uptime_text"}     = "System up time";

  # Werte fuer GesamtCPU
  $rMap->{"stat_cpu"}          = "CPU statistics";
  $rMap->{"stat_cpu_diff"}     = "CPU statistics (diff)";
  $rMap->{"stat_cpu_percent"}  = "CPU statistics (diff, percent)";
  $rMap->{"stat_cpu_text"}     = "CPU statistics (text)";
  
  $rMap->{"stat_cpu_user_percent"} = "CPU statistics user %";
  $rMap->{"stat_cpu_nice_percent"} = "CPU statistics nice %";
  $rMap->{"stat_cpu_sys_percent"}  = "CPU statistics sys %";
  $rMap->{"stat_cpu_idle_percent"} = "CPU statistics idle %";
  $rMap->{"stat_cpu_io_percent"}   = "CPU statistics io %";
  $rMap->{"stat_cpu_irq_percent"}  = "CPU statistics irq %";
  $rMap->{"stat_cpu_sirq_percent"} = "CPU statistics sirq %";
  
  # CPU 0-7 (sollte reichen)
  for my $i (0..7) { 
    $rMap->{"stat_cpu".$i}            = "CPU".$i." statistics";
    $rMap->{"stat_cpu".$i."_diff"}    = "CPU".$i." statistics (diff)";
    $rMap->{"stat_cpu".$i."_percent"} = "CPU".$i." statistics (diff, percent)";
    $rMap->{"stat_cpu".$i."_text"} = "CPU".$i." statistics (text)";
  }
  
	# Filesystems <readingName>[:<mountPoint>[:<Comment>]]
	my $filesystems = AttrVal($name, "filesystems", undef);
  if(defined $filesystems) {
    my @filesystem_list = split(/,\s*/, trim($filesystems));
    foreach (@filesystem_list) {
      my($fName, $fDef, $nComment) = split(/:/, $_);
      my $fPt; 
      if(defined $nComment) {
      	$fPt = $nComment;
      } else {
	      if(defined $fDef) {
	    	  # Benannte
	    	  $fPt = "Filesystem ".$fDef;
	      } else {
	    	  # Unbenannte
	    	  $fPt = "Mount point ".$fName;
	      }
	    }
	    
	    $rMap->{$fName}         =  $fPt;
	    $rMap->{$fName."_used"} =  $fPt." (used)";
	    $rMap->{$fName."_used_percent"} =  $fPt." (used %)";
	    $rMap->{$fName."_free"} =  $fPt." (free)";
	    
    }
  } else {
  	$rMap->{"root"}     = "Filesystem /";
  }

	# Networkadapters: <readingName>[:<interfaceName>[:<Comment>]]
	my $networkadapters = AttrVal($name, "network-interfaces", undef);
  if(defined $networkadapters) {
  	my @networkadapters_list = split(/,\s*/, trim($networkadapters));
    foreach (@networkadapters_list) {
      my($nName, $nDef, $nComment) = split(/:/, $_);
      my $nPt; 
      if(defined $nComment) {
      	$nPt = $nComment;
      } else {
	      if(defined $nDef) {
	    	  # Benannte
	    	  $nPt = "Network ".$nDef;
	      } else {
	    	  # Unbenannte
	    	  $nPt = "Network adapter ".$nName;
	      }
	    }
	    
	    $rMap->{$nName}           =  $nPt;
      $rMap->{$nName."_diff"}   =  $nPt." (diff)";
	    $rMap->{$nName."_rx"}     =  $nPt." (RX)";
	    $rMap->{$nName."_tx"}     =  $nPt." (TX)";
	    
    }
  } else {
  	# Default Networkadapters
  	# Wenn nichts definiert, werden Default-Werte verwendet
  	if(SYSMON_isFB($hash)) {
  		my $nName = "ath0";
		  $rMap->{$nName}         = "Network adapter ".$nName;
	    $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
	    $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
	    $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
	    
	    $nName = "ath1";
		  $rMap->{$nName}         = "Network adapter ".$nName;
	    $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
	    $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
	    $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
	    
	    $nName = "cpmac0";
		  $rMap->{$nName}         = "Network adapter ".$nName;
	    $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
	    $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
	    $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
	    
	    $nName = "dsl";
      $rMap->{$nName}         = "Network adapter ".$nName;
	    $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
	    $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
	    $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
	    
	    $nName = ETH0;
		  $rMap->{$nName}         = "Network adapter ".$nName;
	    $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
	    $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
	    $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
	    
	    $nName = "guest";
	  	$rMap->{$nName}         = "Network adapter ".$nName;
	    $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
	    $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
	    $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
	    
	    $nName = "hotspot";
    	$rMap->{$nName}         = "Network adapter ".$nName;
	    $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
	    $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
	    $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
	    
	    $nName = "lan";
		  $rMap->{$nName}         = "Network adapter ".$nName;
	    $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
	    $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
	    $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
	    
	    $nName = "vdsl";
		  $rMap->{$nName}         = "Network adapter ".$nName;
	    $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
	    $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
	    $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
	    
	  } else {
	  	my $nName = ETH0;
	  	$rMap->{$nName}         = "Network adapter ".$nName;
	    $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
      $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
	    $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
	    
      $nName = WLAN0;
      $rMap->{$nName}         = "Network adapter ".$nName;
	    $rMap->{$nName."_diff"} = "Network adapter ".$nName." (diff)";
	    $rMap->{$nName."_rx"} = "Network adapter ".$nName." (RX)";
	    $rMap->{$nName."_tx"} = "Network adapter ".$nName." (TX)";
    }
  }
  
  if(SYSMON_isFB($hash)) {
    # FB WLAN state
	  $rMap->{+FB_WLAN_STATE}       = "WLAN State";
	  $rMap->{+FB_WLAN_GUEST_STATE} = "WLAN Guest State";
	  $rMap->{+FB_INET_IP}          = "Internet IP";
	  $rMap->{+FB_INET_STATE}       = "Internet connection state";
	  $rMap->{+FB_N_TIME_CTRL}      = "night time control";
	  $rMap->{+FB_NUM_NEW_MESSAGES} = "new messages";
	  $rMap->{+FB_FW_VERSION}       = "firmware info";
	  $rMap->{+FB_DECT_TEMP}        = "DECT temperatur";
  }
  
	# User defined
	my $userdefined = AttrVal($name, "user-defined", undef);
  if(defined $userdefined) {
  	my @userdefined_list = split(/,\s*/, trim($userdefined));
    foreach (@userdefined_list) {
       # <readingName>:<Interval_Minutes>:<Comment>:<Cmd>
	     my($uName, $uInterval, $uComment, $uCmd) = split(/:/, $_);
	     if(defined $uComment) {
	    	# Nur gueltige
		    $rMap->{$uName} = $uComment;
	    }
    }
  }

# TEST: TODO
$rMap->{"io_sda_raw"}         = "TEST";
$rMap->{"io_sda_diff"}         = "TEST";
$rMap->{"io_sda"}         = "TEST";

  $cur_readings_map = $rMap;
  return $rMap;
}

sub
SYSMON_getObsoleteReadingsMap($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $rMap; 
	
	#return $rMap; # TODO TEST
	
	if(!defined($cur_readings_map)) {
	  SYSMON_updateCurrentReadingsMap($hash);
  }

	# alle READINGS durchgehen
	my @cKeys=keys (%{$defs{$name}{READINGS}});
  foreach my $aName (@cKeys) {
    if(defined ($aName)) {
    	# alles hinzufuegen, was nicht in der Aktuellen Liste ist
    	if(!defined($cur_readings_map->{$aName})) {
    		#Log 3, "SYSMON>>>>>>>>>>>>>>>>> SYSMON_getObsoleteReadingsMap >>> $aName";
    		$rMap->{$aName} = 1;
    	}
    }
  }
	
	return $rMap;
}

sub
SYSMON_Undefine($$)
{
  my ($hash, $arg) = @_;

  logF($hash, "Undefine", "");

  RemoveInternalTimer($hash);
  return undef;
}

sub
SYSMON_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];

  if(@a < 2)
  {
  	logF($hash, "Get", "@a: get needs at least one parameter");
    return "$name: get needs at least one parameter";
  }

  my $cmd= $a[1];

  logF($hash, "Get", "@a");

  if($cmd eq "update")
  {
  	#$hash->{LOCAL} = 1;
  	SYSMON_Update($hash, 1);
  	#delete $hash->{LOCAL};
  	return undef;
  }

  if($cmd eq "list") {
    my $map = SYSMON_obtainParameters($hash, 1);
    my $ret = "";
    foreach my $name (keys %{$map}) {
  	  my $value = $map->{$name};
  	  $ret = "$ret\n".sprintf("%-20s %s", $name, $value);
    }
    return $ret;
  }

  if($cmd eq "version")
  {
  	return $VERSION;
  }

  if($cmd eq "interval_base")
  {
  	return $hash->{INTERVAL_BASE};
  }

  if($cmd eq "interval_multipliers")
  {
  	return $hash->{INTERVAL_MULTIPLIERS};
  }

  return "Unknown argument $cmd, choose one of list:noArg update:noArg interval_base:noArg interval_multipliers:noArg version:noArg";
}

sub
SYSMON_Set($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];

  if(@a < 2)
  {
  	logF($hash, "Set", "@a: set needs at least one parameter");
    return "$name: set needs at least one parameter";
  }

  my $cmd= $a[1];

  logF($hash, "Set", "@a");

  if($cmd eq "interval_multipliers")
  {
  	if(@a < 3) {
  		logF($hash, "Set", "$name: not enought parameters");
      return "$name: not enought parameters";
  	}

  	my @na = @a[2..scalar(@a)-1];
  	SYSMON_setInterval($hash, @na);
  	return $cmd ." set to ".($hash->{INTERVAL_MULTIPLIERS});
  }

  if($cmd eq "clean") {    
    # Nicht mehr benoetigte Readings loeschen
    my $omap = SYSMON_getObsoleteReadingsMap($hash);
    foreach my $aName (keys %{$omap}) {
    	delete $defs{$name}{READINGS}{$aName};
	  }
    return;
  }
  
  if($cmd eq "clear")
  {
  	my $subcmd = my $cmd= $a[2];
  	if(defined $subcmd) {
  		delete $defs{$name}{READINGS}{$subcmd};
  		return;
    }
    
    return "missing parameter. use clear <reading name>";
  }

  return "Unknown argument $cmd, choose one of interval_multipliers clean:noArg clear";
}

sub
SYSMON_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  Log 5, "SYSMON Attr: $cmd $name $attrName $attrVal";

  $attrVal= "" unless defined($attrVal);
  my $orig = AttrVal($name, $attrName, "");

  if( $cmd eq "set" ) {# set, del
    if( $orig ne $attrVal ) {

      my $hash = $main::defs{$name};
    	if($attrName eq "disable")
      {
        RemoveInternalTimer($hash);
      	if($attrVal ne "0")
      	{
      		InternalTimer(gettimeofday()+$hash->{INTERVAL_BASE}, "SYSMON_Update", $hash, 0);
      	}
       	#$hash->{LOCAL} = 1;
  	    SYSMON_Update($hash);
  	    #delete $hash->{LOCAL};
      }

      $attr{$name}{$attrName} = $attrVal;
      
      SYSMON_updateCurrentReadingsMap($hash);
      
      #return $attrName ." set to ". $attrVal;
      return undef;
    }
  }
  return;
}

my $u_first_mark = undef;

sub
SYSMON_Update($@)
{
  my ($hash, $refresh_all) = @_;

  logF($hash, "Update", "");

  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL_BASE}, "SYSMON_Update", $hash, 1);
  }

  readingsBeginUpdate($hash);

  if( AttrVal($name, "disable", "") eq "1" )
  {
  	logF($hash, "Update", "disabled");
  	$hash->{STATE} = "Inactive";
  } else {
	  # Beim ersten mal alles aktualisieren!
	  if(!$u_first_mark) {
	    $refresh_all = 1;
	  }

	  # Parameter holen
    my $map = SYSMON_obtainParameters($hash, $refresh_all);

    # Mark setzen 
    if(!$u_first_mark) {
	    $u_first_mark = 1;
	  }
	  
    $hash->{STATE} = "Active";
    #my $state = $map->{LOADAVG};
    #readingsBulkUpdate($hash,"state",$state);

    foreach my $aName (keys %{$map}) {
  	  my $value = $map->{$aName};
  	  # Nur aktualisieren, wenn ein gueltiges Value vorliegt
  	  if(defined $value) {
  	    readingsBulkUpdate($hash,$aName,$value);
  	  }

    }
    
    # Nicht mehr benoetigte Readings loeschen
    my $omap = SYSMON_getObsoleteReadingsMap($hash);
    foreach my $aName (keys %{$omap}) {
    	delete $defs{$name}{READINGS}{$aName};
	  }
    
  }

  readingsEndUpdate($hash,defined($hash->{LOCAL}) ? 0 : 1);
}

# Schattenmap mit den zuletzt gesammelten Werten (merged)
my %shadow_map;
sub
SYSMON_obtainParameters($$)
{
	my ($hash, $refresh_all) = @_;
	my $name = $hash->{NAME};

	my $map;

	my $base=$DEFAULT_INTERVAL_BASE; 
	my $im = "1 1 1 10";
	# Wenn wesentliche Parameter nicht definiert sind, soll aktualisierung immer vorgenommen werden
	if((defined $hash->{INTERVAL_BASE})) {
  	$base = $hash->{INTERVAL_BASE};
  }
  if((defined $hash->{INTERVAL_MULTIPLIERS})) {
  	$im = $hash->{INTERVAL_MULTIPLIERS};
  }

  my $ref =  int(time()/$base);
	my ($m1, $m2, $m3, $m4) = split(/\s+/, $im);
	 
	# Einmaliges
	if(!$u_first_mark) {
	  $map = SYSMON_getCPUBogoMIPS($hash, $map);
	
	  if(SYSMON_isFB($hash)) {
	    $map = SYSMON_FBVersionInfo($hash, $map);
    }
  }

	# immer aktualisieren: uptime, uptime_text, fhemuptime, fhemuptime_text, idletime, idletime_text
  $map = SYSMON_getUptime($hash, $map);
  $map = SYSMON_getFHEMUptime($hash, $map);

  if($m1 gt 0) { # Nur wenn > 0
    # M1: cpu_freq, cpu_temp, cpu_temp_avg, loadavg, procstat, iostat
    if($refresh_all || ($ref % $m1) eq 0) {
    	#Log 3, "SYSMON -----------> DEBUG: read CPU-Temp"; 
    	if(SYSMON_isCPUTempRPi($hash)) { # Rasp
    		 $map = SYSMON_getCPUTemp_RPi($hash, $map);
      } 
      if (SYSMON_isCPUTempBBB($hash)) {
        $map = SYSMON_getCPUTemp_BBB($hash, $map);
      }
      if(SYSMON_isCPUFreqRPiBBB($hash)) {
        $map = SYSMON_getCPUFreq($hash, $map);
      }
      if(SYSMON_isCPU1Freq($hash)) {
        $map = SYSMON_getCPU1Freq($hash, $map);
      }
      $map = SYSMON_getLoadAvg($hash, $map);
      $map = SYSMON_getCPUProcStat($hash, $map);
      #$map = SYSMON_getDiskStat($hash, $map);
      
      # Power info (cubietruck)
      if(SYSMON_isSysPowerAc($hash)) {
      	$map = SYSMON_PowerAcInfo($hash, $map);
      }
      if(SYSMON_isSysPowerUsb($hash)) {
      	$map = SYSMON_PowerUsbInfo($hash, $map);
      }
      if(SYSMON_isSysPowerBat($hash)) {
      	$map = SYSMON_PowerBatInfo($hash, $map);
      }
    }
  }

  if($m2 gt 0) { # Nur wenn > 0
    # M2: ram, swap
    if($refresh_all || ($ref % $m2) eq 0) {
      $map = SYSMON_getRamAndSwap($hash, $map);
    }
  }

  if($m3 gt 0) { # Nur wenn > 0
    # M3: eth0, eth0_diff, wlan0, wlan0_diff, wlan_on (FritzBox)
    my $update_ns = ($refresh_all || ($ref % $m3) eq 0);
    #if($refresh_all || ($ref % $m3) eq 0) {
    my $networks = AttrVal($name, "network-interfaces", undef);
    if($update_ns) {
      if(defined $networks) {
      	my @networks_list = split(/,\s*/, trim($networks));
        foreach (@networks_list) {
	        $map = SYSMON_getNetworkInfo($hash, $map, $_);
        }
      } else {
      	# Wenn nichts definiert, werden Default-Werte verwendet
      	#Log 3, "SYSMON>>>>>>>>>>>>>>>>>>>>>>>>> NETWORK";
      	if(SYSMON_isFB($hash)) {
    		  $map = SYSMON_getNetworkInfo($hash, $map, "ath0");
    		  $map = SYSMON_getNetworkInfo($hash, $map, "ath1");
    		  $map = SYSMON_getNetworkInfo($hash, $map, "cpmac0");
          $map = SYSMON_getNetworkInfo($hash, $map, "dsl");
    		  $map = SYSMON_getNetworkInfo($hash, $map, "eth0");
    	  	$map = SYSMON_getNetworkInfo($hash, $map, "guest");
        	$map = SYSMON_getNetworkInfo($hash, $map, "hotspot");
    		  $map = SYSMON_getNetworkInfo($hash, $map, "lan");
    		  $map = SYSMON_getNetworkInfo($hash, $map, "vdsl");
    	  } else {
    	  	#Log 3, "SYSMON>>>>>>>>>>>>>>>>>>>>>>>>> ".ETH0;
          $map = SYSMON_getNetworkInfo($hash, $map, ETH0);
          #Log 3, "SYSMON>>>>>>>>>>>>>>>>>>>>>>>>> ".$map->{+ETH0};
          #Log 3, "SYSMON>>>>>>>>>>>>>>>>>>>>>>>>> ".WLAN0;
          $map = SYSMON_getNetworkInfo($hash, $map, WLAN0);
          #Log 3, "SYSMON>>>>>>>>>>>>>>>>>>>>>>>>> ".$map->{+WLAN0};
        }
      }
      if(SYSMON_isFB($hash)) {
      	$map = SYSMON_getFBWLANState($hash, $map);
      	$map = SYSMON_getFBWLANGuestState($hash, $map);
      	$map = SYSMON_getFBInetIP($hash, $map);
      	$map = SYSMON_getFBInetConnectionState($hash, $map);
      	$map = SYSMON_getFBNightTimeControl($hash, $map);
      	$map = SYSMON_getFBNumNewMessages($hash, $map);
      	$map = SYSMON_getFBDECTTemp($hash, $map);
      }
    }
  }
  
  if($m4 gt 0) { # Nur wenn > 0
    # M4: Filesystem-Informationen
    my $update_fs = ($refresh_all || ($ref % $m4) eq 0);
    my $filesystems = AttrVal($name, "filesystems", undef);
    if($update_fs) {
      if(defined $filesystems)
      {
        my @filesystem_list = split(/,\s*/, trim($filesystems));
        foreach (@filesystem_list)
        {
        	$map = SYSMON_getFileSystemInfo($hash, $map, $_);
        }
      } else {
        $map = SYSMON_getFileSystemInfo($hash, $map, "root:/");
      }
    } else {
    	# Workaround: Damit die Readings zw. den Update-Punkten nicht geloescht werden, werden die Schluessel leer angelegt
    	# Wenn noch keine Update notwendig, dan einfach alte Schluessel (mit undef als Wert) angeben,
    	# damit werden die Readings in der Update-Methode nicht geloescht.
    	# Die ggf. notwendige Loeschung findet nur bei tatsaechlichen Update statt.
    	my @cKeys=keys (%{$defs{$name}{READINGS}});
      foreach my $aName (@cKeys) {
    	  #if(defined ($aName) && (index($aName, FS_PREFIX) == 0 || index($aName, FS_PREFIX_N) == 0)) {
    	  if(defined ($aName) && (index($aName, FS_PREFIX) == 0 )) {
          $map->{$aName} = undef;
        }
      }
    }
  }
  
  #Log 3, "SYSMON >>> USER_DEFINED >>>>>>>>>>>>>>> START";
  my $userdefined = AttrVal($name, "user-defined", undef);
  if(defined $userdefined) {
  	my @userdefined_list = split(/,\s*/, trim($userdefined));
    foreach (@userdefined_list) {
       # <readingName>:<Interval_Minutes>:<Comment>:<Cmd>
       my $ud = $_;
	     my($uName, $uInterval, $uComment, $uCmd) = split(/:/, $ud);
	     logF($hash, "User-Defined Reading", "[$uName][$uInterval][$uComment][$uCmd]");
	     if(defined $uCmd) { # Also, wenn alle Parameter vorhanden
	     	 my $iInt = int($uInterval);
	     	 if($iInt>0) {
	     	   my $update_ud = ($refresh_all || ($ref % $iInt) eq 0);
	     	   if($update_ud) {
	     	 	   $map = SYSMON_getUserDefined($hash, $map, $uName, $uCmd);
	     	   }
	       }
	    }
    }
  }
  
  # Aktuelle Werte in ShattenHash mergen
  my %hashT = %{$map};
  @shadow_map{ keys %hashT } = values %hashT;

  return $map;
}

#------------------------------------------------------------------------------
# Liefert gesammelte Werte ( = Readings)
# Parameter: array der gewuenschten keys (Readings names)
# Beispiele:
#   {(SYSMON_getValues())->{'fs_root'}}
#   {(SYSMON_getValues(("cpu_freq","cpu_temp")))->{"cpu_temp"}}
#   {join(" ", keys (SYSMON_getValues()))}
#   {join(" ", keys (SYSMON_getValues(("cpu_freq","cpu_temp"))))}
#------------------------------------------------------------------------------
sub
SYSMON_getValues(;@)
{
	my @filter_keys = @_;
	if(scalar(@filter_keys)>0) {
		my %clean_hash;
    @clean_hash{ @filter_keys } = @shadow_map{ @filter_keys };
    return \%clean_hash;
	}
	# alles liefern
  return \%shadow_map;
}

#------------------------------------------------------------------------------
# Liest Benutzerdefinierte Eintraege
#------------------------------------------------------------------------------
sub
SYSMON_getUserDefined($$$$)
{
	my ($hash, $map, $uName, $uCmd) = @_;
	logF($hash, "SYSMON_getUserDefined", "Name=[$uName] Cmd=[$uCmd]");
	
	my $out_str = SYSMON_execute($hash, $uCmd);
	$map->{$uName} = $out_str;
	
	return $map;
}

#------------------------------------------------------------------------------
# leifert Zeit seit dem Systemstart
#------------------------------------------------------------------------------
sub
SYSMON_getUptime($$)
{
	my ($hash, $map) = @_;

	#my $uptime_str = qx(cat /proc/uptime );
	my $uptime_str = SYSMON_execute($hash, "cat /proc/uptime");
  my ($uptime, $idle) = split(/\s+/, trim($uptime_str));
  my $idle_percent = $idle/$uptime*100;

	$map->{+UPTIME}=sprintf("%d",$uptime);
	#$map->{+UPTIME_TEXT} = sprintf("%d days, %02d hours, %02d minutes, %02d seconds",SYSMON_decode_time_diff($uptime));
	$map->{+UPTIME_TEXT} = sprintf("%d days, %02d hours, %02d minutes",SYSMON_decode_time_diff($uptime));

  $map->{+IDLETIME}=sprintf("%d %.2f %%",$idle, $idle_percent);
	$map->{+IDLETIME_TEXT} = sprintf("%d days, %02d hours, %02d minutes",SYSMON_decode_time_diff($idle)).sprintf(" (%.2f %%)",$idle_percent);
	#$map->{+IDLETIME_PERCENT} = sprintf ("%.2f %",$idle_percent);

	return $map;
}

#------------------------------------------------------------------------------
# leifert Zeit seit FHEM-Start
#------------------------------------------------------------------------------
sub
SYSMON_getFHEMUptime($$)
{
	my ($hash, $map) = @_;

	#if(defined ($hash->{DEF_TIME})) {
	if(defined($fhem_started)) {
	  #my $fhemuptime = time()-$hash->{DEF_TIME};
	  my $fhemuptime = time()-$fhem_started;
	  $map->{+FHEMUPTIME} = sprintf("%d",$fhemuptime);
	  $map->{+FHEMUPTIME_TEXT} = sprintf("%d days, %02d hours, %02d minutes",SYSMON_decode_time_diff($fhemuptime));
  }

	return $map;
}

#------------------------------------------------------------------------------
# leifert CPU-Auslastung
#------------------------------------------------------------------------------
sub
SYSMON_getLoadAvg($$)
{
	my ($hash, $map) = @_;

	#my $la_str = qx(cat /proc/loadavg );
	my $la_str = SYSMON_execute($hash, "cat /proc/loadavg");
  my ($la1, $la5, $la15, $prc, $lastpid) = split(/\s+/, trim($la_str));

	$map->{+LOADAVG}="$la1 $la5 $la15";
  #$map->{"load"}="$la1";
	#$map->{"load5"}="$la5";
	#$map->{"load15"}="$la15";

	return $map;
}

#------------------------------------------------------------------------------
# leifert CPU Temperature (Raspberry Pi)
#------------------------------------------------------------------------------
sub
SYSMON_getCPUTemp_RPi($$)
{
	
	my ($hash, $map) = @_;
  my $val = SYSMON_execute($hash, "cat /sys/class/thermal/thermal_zone0/temp 2>&1");  
  $val = int($val);
  if($val>1000) { # Manche Systeme scheinen die Daten verschieden zu skalieren (z.B. utilite)...
    $val = $val/1000;
  }
  my $val_txt = sprintf("%.2f", $val);
  $map->{+CPU_TEMP}="$val_txt";
  my $t_avg = sprintf( "%.1f", (3 * ReadingsVal($hash->{NAME},CPU_TEMP_AVG,$val_txt) + $val_txt ) / 4 );
  $map->{+CPU_TEMP_AVG}="$t_avg";
	return $map;
}

#------------------------------------------------------------------------------
# leifert CPU Temperature (BeagleBone Black)
#------------------------------------------------------------------------------
sub
SYSMON_getCPUTemp_BBB($$)
{
	my ($hash, $map) = @_;
 	my $val = SYSMON_execute($hash, "cat /sys/class/hwmon/hwmon0/device/temp1_input 2>&1");
 	$val = int($val);
  my $val_txt = sprintf("%.2f", $val/1000);
  $map->{+CPU_TEMP}="$val_txt";
  my $t_avg = sprintf( "%.1f", (3 * ReadingsVal($hash->{NAME},CPU_TEMP_AVG,$val_txt) + $val_txt ) / 4 );
  $map->{+CPU_TEMP_AVG}="$t_avg";  
	return $map;
}

#------------------------------------------------------------------------------
# leifert CPU Frequenz (Raspberry Pi, BeagleBone Black, Cubietruck, etc.)
#------------------------------------------------------------------------------
sub
SYSMON_getCPUFreq($$)
{
	my ($hash, $map) = @_;
	my $val = SYSMON_execute($hash, "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>&1");
	$val = int($val);
	my $val_txt = sprintf("%d", $val/1000);
  $map->{+CPU_FREQ}="$val_txt";
	return $map;
}

#------------------------------------------------------------------------------
# leifert CPU Frequenz f�r 2te CPU (Cubietruck, etc.)
#------------------------------------------------------------------------------
sub
SYSMON_getCPU1Freq($$)
{
	my ($hash, $map) = @_;
	my $val = SYSMON_execute($hash, "cat /sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq 2>&1");
	$val = int($val);
	my $val_txt = sprintf("%d", $val/1000);
  $map->{+CPU1_FREQ}="$val_txt";
	return $map;
}

#------------------------------------------------------------------------------
# leifert CPU Speed in BogoMIPS
#------------------------------------------------------------------------------
sub
SYSMON_getCPUBogoMIPS($$)
{
	my ($hash, $map) = @_;
	my $old_val = ReadingsVal($hash->{NAME},CPU_BOGOMIPS,undef);
	# nur einmalig ermitteln (wird sich ja nicht aendern
	if(!defined $old_val) {
    my $val = SYSMON_execute($hash, "cat /proc/cpuinfo | grep -m 1 'BogoMIPS'");
    #Log 3,"SYSMON -----------> DEBUG: read BogoMIPS = $val"; 
    my ($dummy, $val_txt) = split(/:\s+/, $val);
    $val_txt = trim($val_txt);
    $map->{+CPU_BOGOMIPS}="$val_txt";
  } else {
  	$map->{+CPU_BOGOMIPS}=$old_val;
  }
  
	return $map;
}

#------------------------------------------------------------------------------
# leifert Werte aus /proc/diskstat
# Werte:
# 1 - major number
# 2 - minor mumber
# 3 - device name
# Dann Datenwerte:
#   Field  1 -- # of reads issued
#   Field  2 -- # of reads merged
#   Field  3 -- # of sectors read
#   Field  4 -- # of milliseconds spent reading
#   Field  5 -- # of writes completed
#   Field  6 -- # of writes merged
#   Field  7 -- # of sectors written
#   Field  8 -- # of milliseconds spent writing
#   Field  9 -- # of I/Os currently in progress
#   Field 10 -- # of milliseconds spent doing I/Os
#   Field 11 -- weighted # of milliseconds spent doing I/Os
# Interessant sind eigentlich "nur" Feld 2 (readin), Feld 5 (write)
# Wenn es eher "um die zeit" geht, Feld 4 (reading), Feld 8 (writing), Feld 10 (Komplett)
# Kleiner Hinweis, Fled 1 ist das 4. der Liste, das 3. Giebt den Namen an. 
# Es giebt fuer jedes Devine und jede Partition ein Eintrag. 
# A /proc/diskstats continuously updated and all that is necessary for us - 
# make measurements for "second field" and "fourth field" in two different moment of time, 
# receiving a difference of values and dividing it into an interval of time, 
# we shall have Disk I/O stats in sectors/sec. Multiply this result on 512 (number of bytes in one sector) 
# we shall have Disk I/O stats in bytes/sec. 
#
# ...
# https://www.kernel.org/doc/Documentation/iostats.txt
#   Field  1 -- # of reads completed
#       This is the total number of reads completed successfully.
#   Field  2 -- # of reads merged, field 6 -- # of writes merged
#       Reads and writes which are adjacent to each other may be merged for
#       efficiency.  Thus two 4K reads may become one 8K read before it is
#       ultimately handed to the disk, and so it will be counted (and queued)
#       as only one I/O.  This field lets you know how often this was done.
#   Field  3 -- # of sectors read
#       This is the total number of sectors read successfully.
#   Field  4 -- # of milliseconds spent reading
#       This is the total number of milliseconds spent by all reads (as
#       measured from __make_request() to end_that_request_last()).
#   Field  5 -- # of writes completed
#       This is the total number of writes completed successfully.
#   Field  6 -- # of writes merged
#       See the description of field 2.
#   Field  7 -- # of sectors written
#       This is the total number of sectors written successfully.
#   Field  8 -- # of milliseconds spent writing
#       This is the total number of milliseconds spent by all writes (as
#       measured from __make_request() to end_that_request_last()).
#   Field  9 -- # of I/Os currently in progress
#       The only field that should go to zero. Incremented as requests are
#       given to appropriate struct request_queue and decremented as they finish.
#   Field 10 -- # of milliseconds spent doing I/Os
#       This field increases so long as field 9 is nonzero.
#   Field 11 -- weighted # of milliseconds spent doing I/Os
#       This field is incremented at each I/O start, I/O completion, I/O
#       merge, or read of these stats by the number of I/Os in progress
#       (field 9) times the number of milliseconds spent doing I/O since the
#       last update of this field.  This can provide an easy measure of both
#       I/O completion time and the backlog that may be accumulating.
#
# 
#   Disks vs Partitions
#   -------------------
#   
#   There were significant changes between 2.4 and 2.6 in the I/O subsystem.
#   As a result, some statistic information disappeared. The translation from
#   a disk address relative to a partition to the disk address relative to
#   the host disk happens much earlier.  All merges and timings now happen
#   at the disk level rather than at both the disk and partition level as
#   in 2.4.  Consequently, you'll see a different statistics output on 2.6 for
#   partitions from that for disks.  There are only *four* fields available
#   for partitions on 2.6 machines.  This is reflected in the examples above.
#   
#   Field  1 -- # of reads issued
#       This is the total number of reads issued to this partition.
#   Field  2 -- # of sectors read
#       This is the total number of sectors requested to be read from this
#       partition.
#   Field  3 -- # of writes issued
#       This is the total number of writes issued to this partition.
#   Field  4 -- # of sectors written
#       This is the total number of sectors requested to be written to
#       this partition.
#------------------------------------------------------------------------------
sub
SYSMON_getDiskStat($$)
{
	my ($hash, $map) = @_;
	my @values = SYSMON_execute($hash, "cat /proc/diskstats");

  for my $entry (@values){
	  $map = SYSMON_getDiskStat_intern($hash, $map, $entry);
	  #Log 3, "SYSMON-DEBUG-IOSTAT:   ".$entry;
  }

  return $map;
}

sub
SYSMON_getDiskStat_intern($$$) 
{
	my ($hash, $map, $entry) = @_;
	
	my ($d1, $d2, $pName, $nf1, $nf2, $nf3, $nf4, $nf5, $nf6, $nf7, $nf8, $nf9, $nf10, $nf11) = split(/\s+/, trim($entry));
	
	Log 3, "SYSMON-DEBUG-IOSTAT:   ".$pName." = ".$nf1." ".$nf2." ".$nf3." ".$nf4." ".$nf5." ".$nf6." ".$nf7." ".$nf8." ".$nf9." ".$nf10." ".$nf11;
	
	# Nur nicht-null-Werte
	if($nf1 eq "0") {
		return $map;
	} 
	
	$pName = "io_".$pName;
	#Log 3, "SYSMON-DEBUG-IOSTAT:   ".$pName;
	
	# Partition and 2.6-Kernel?
	if(defined($nf5)) {
	  # no
	  $map->{$pName."_raw"}=$nf1." ".$nf2." ".$nf3." ".$nf4." ".$nf5." ".$nf6." ".$nf7." ".$nf8." ".$nf9." ".$nf10." ".$nf11;
  } else {
    $map->{$pName."_raw"}=$nf1." ".$nf2." ".$nf3." ".$nf4;
  }
  #$map->{"iostat_test"}="TEST";
	my $lastVal = ReadingsVal($hash->{NAME},$pName."_raw",undef);
	if(defined($lastVal)) {
  	Log 3, "SYSMON-DEBUG-IOSTAT:   lastVal: $pName=".$lastVal;
  }
	if(defined $lastVal) {
		# Diff. ausrechnen, falls vorherigen Werte vorhanden sind.
		my($af1, $af2, $af3, $af4, $af5, $af6, $af7, $af8, $af9, $af10, $af11) = split(/\s+/, $lastVal);
	  
	  Log 3, "SYSMON-DEBUG-IOSTAT:   X: ".$pName." = ".$af1." ".$af2." ".$af3." ".$af4." ".$af5." ".$af6." ".$af7." ".$af8." ".$af9." ".$af10." ".$af11;
	  
	  my $sectorsRead;
	  my $sectorsWritten;
	
	  my $df1 = $nf1-$af1;
	  my $df2 = $nf2-$af2;
	  my $df3 = $nf3-$af3;
	  my $df4 = $nf4-$af4;
	  # Partition and 2.6-Kernel?
	  if(defined($nf5)) {
	  	# no
	    my $df5 = $nf5-$af5;
	    my $df6 = $nf6-$af6;
	    my $df7 = $nf7-$af7;
	    my $df8 = $nf8-$af8;
	    my $df9 = $nf9-$af9;
	    my $df10 = $nf10-$af10;
	    my $df11 = $nf11-$af11;
	    $map->{$pName."_diff"}=$df1." ".$df2." ".$df3." ".$df4." ".$df5." ".$df6." ".$df7." ".$df8." ".$df9." ".$df10." ".$df11;
	    
      $sectorsRead = $df3;
      $sectorsWritten = $df7;
	  } else {
	    $map->{$pName."_diff"}=$df1." ".$df2." ".$df3." ".$df4;	  	
	    
	    $sectorsRead = $df2;
      $sectorsWritten = $df4;
	  }
	  
	  my $sectorBytes = 512;
	  
	  my $BytesRead    = $sectorsRead*$sectorBytes;
	  my $BytesWritten = $sectorsWritten*$sectorBytes;
	  
	  # TODO: Summenwerte
	  $map->{$pName.""}=sprintf("bytes read: %d bytes written: %d",$BytesRead, $BytesWritten);
  }

	return $map;
}


#------------------------------------------------------------------------------
# leifert Werte aus /proc/stat
# Werte:
#   neuCPUuser, neuCPUnice, neuCPUsystem, neuCPUidle, neuCPUiowait, neuCPUirq, neuCPUsoftirq
# Differenzberechnung:
#   CPUuser = neuCPUuser - altCPUuser (fuer alle anderen analog)
#   GesammtCPU = CPUuser + CPUnice + CPUsystem + CPUidle + CPUiowait + CPUirq + CPUsoftirq
# Belastung in %:
#   ProzCPUuser = (CPUuser / GesammtCPU) * 100
#------------------------------------------------------------------------------
sub
SYSMON_getCPUProcStat($$)
{
	my ($hash, $map) = @_;
	my @values = SYSMON_execute($hash, "cat /proc/stat");
	
	for my $entry (@values){
	  if (index($entry, "cpu") < 0){
      last;
    }
    $map = SYSMON_getCPUProcStat_intern($hash, $map, $entry);
  }
  
  # Wenn nur eine CPU vorhanden ist, loeschen Werte fuer CPU0 (nur Gesamt belassen)
  if(!defined($map->{"stat_cpu1"})){
  	delete $map->{"stat_cpu0"};
  	delete $map->{"stat_cpu0_diff"};
  	delete $map->{"stat_cpu0_percent"};
  }
	
	return $map;
}

sub
SYSMON_getCPUProcStat_intern($$$) 
{
	my ($hash, $map, $entry) = @_;
	
	my($pName, $neuCPUuser, $neuCPUnice, $neuCPUsystem, $neuCPUidle, $neuCPUiowait, $neuCPUirq, $neuCPUsoftirq) = split(/\s+/, trim($entry));
	$pName = "stat_".$pName;
	$map->{$pName}=$neuCPUuser." ".$neuCPUnice." ".$neuCPUsystem." ".$neuCPUidle." ".$neuCPUiowait." ".$neuCPUirq." ".$neuCPUsoftirq;
	
	my $lastVal = ReadingsVal($hash->{NAME},$pName,undef);
	if(defined $lastVal) {
		# Diff. ausrechnen, falls vorherigen Werte vorhanden sind.
	  my($altCPUuser, $altCPUnice, $altCPUsystem, $altCPUidle, $altCPUiowait, $altCPUirq, $altCPUsoftirq) = split(/\s+/, $lastVal);
    
    my $CPUuser    = $neuCPUuser    - $altCPUuser;
    my $CPUnice    = $neuCPUnice    - $altCPUnice;
    my $CPUsystem  = $neuCPUsystem  - $altCPUsystem;
    my $CPUidle    = $neuCPUidle    - $altCPUidle;
    my $CPUiowait  = $neuCPUiowait  - $altCPUiowait;
    my $CPUirq     = $neuCPUirq     - $altCPUirq;
    my $CPUsoftirq = $neuCPUsoftirq - $altCPUsoftirq;
    $map->{$pName."_diff"}=$CPUuser." ".$CPUnice." ".$CPUsystem." ".$CPUidle." ".$CPUiowait." ".$CPUirq." ".$CPUsoftirq;
	  
    my $GesammtCPU = $CPUuser + $CPUnice + $CPUsystem + $CPUidle + $CPUiowait + $CPUirq + $CPUsoftirq;
    my $PercentCPUuser    = ($CPUuser    / $GesammtCPU) * 100;
    my $PercentCPUnice    = ($CPUnice    / $GesammtCPU) * 100;
    my $PercentCPUsystem  = ($CPUsystem  / $GesammtCPU) * 100;
    my $PercentCPUidle    = ($CPUidle    / $GesammtCPU) * 100;
    my $PercentCPUiowait  = ($CPUiowait  / $GesammtCPU) * 100;
    my $PercentCPUirq     = ($CPUirq     / $GesammtCPU) * 100;
    my $PercentCPUsoftirq = ($CPUsoftirq / $GesammtCPU) * 100;
    
    $map->{$pName."_percent"}=sprintf ("%.2f %.2f %.2f %.2f %.2f %.2f %.2f",$PercentCPUuser,$PercentCPUnice,$PercentCPUsystem,$PercentCPUidle,$PercentCPUiowait,$PercentCPUirq,$PercentCPUsoftirq);
    $map->{$pName."_text"}=sprintf ("user: %.2f %%, nice: %.2f %%, sys: %.2f %%, idle: %.2f %%, io: %.2f %%, irq: %.2f %%, sirq: %.2f %%",$PercentCPUuser,$PercentCPUnice,$PercentCPUsystem,$PercentCPUidle,$PercentCPUiowait,$PercentCPUirq,$PercentCPUsoftirq);
  }

	return $map;
}

#------------------------------------------------------------------------------
# Liefert Werte fuer RAM und SWAP (Gesamt, Verwendet, Frei).
#------------------------------------------------------------------------------
sub SYSMON_getRamAndSwap($$)
{
  my ($hash, $map) = @_;

  #my @speicher = qx(free -m);
  my @speicher = SYSMON_execute($hash, "free");

  shift @speicher;
  my ($fs_desc, $total, $used, $free, $shared, $buffers, $cached) = split(/\s+/, trim($speicher[0]));
  shift @speicher;
  my ($fs_desc2, $total2, $used2, $free2, $shared2, $buffers2, $cached2) = split(/\s+/, trim($speicher[0]));

  if($fs_desc2 ne "Swap:")
  {
    shift @speicher;
    ($fs_desc2, $total2, $used2, $free2, $shared2, $buffers2, $cached2) = split(/\s+/, trim($speicher[0]));
  }

  my $ram;
  my $swap;
  #my $percentage_ram;
  #my $percentage_swap;
  
  $total   = $total / 1024;
  $used    = $used / 1024;
  $free    = $free / 1024;
  $buffers = $buffers / 1024;
  if(defined($cached)) {
    $cached  = $cached / 1024;
  } else {
  	# Bei FritzBox wird dieser Wert nicht ausgageben
  	$cached  = 0;
  }

  $ram = sprintf("Total: %.2f MB, Used: %.2f MB, %.2f %%, Free: %.2f MB", $total, ($used - $buffers - $cached), (($used - $buffers - $cached) / $total * 100), ($free + $buffers + $cached));

  $map->{+RAM} = $ram;

  # wenn kein swap definiert ist, ist die Groesse (total2) gleich Null. Dies wuerde eine Exception (division by zero) ausloesen
  if($total2 > 0)
  {
  	$total2   = $total2 / 1024;
    $used2    = $used2 / 1024;
    $free2    = $free2 / 1024;
  
    $swap = sprintf("Total: %.2f MB, Used: %.2f MB,  %.2f %%, Free: %.2f MB", $total2, $used2, ($used2 / $total2 * 100), $free2);
  }
  else
  {
    $swap = "n/a"
  }

  $map->{+SWAP} = $swap;

  return $map;
}

#------------------------------------------------------------------------------
# Liefert Fuellstand fuer das angegebene Dateisystem (z.B. '/dev/root', '/dev/sda1' (USB stick)).
# Eingabeparameter: HASH; MAP; FS-Bezeichnung
#------------------------------------------------------------------------------
sub SYSMON_getFileSystemInfo ($$$)
{
	my ($hash, $map, $fs) = @_;
	
	logF($hash, "SYSMON_getFileSystemInfo", "get $fs");
	
	# Neue Syntax: benannte Filesystems: <name>:<definition>
	my($fName, $fDef, $fComment) = split(/:/, $fs);
	if(defined $fDef) {
		$fs = $fDef;
	}

  #my $disk = "df ".$fs." -m 2>&1"; # in case of failure get string from stderr
  my $disk = "df ".$fs." -m 2>/dev/null";
  
  logF($hash, "SYSMON_getFileSystemInfo", "exec $disk");

  #my @filesystems = qx($disk);
  my @filesystems = SYSMON_execute($hash, $disk);
  
  logF($hash, "SYSMON_getFileSystemInfo", "recieved ".scalar(scalar(@filesystems))." lines");
  
  # - DEBUG -
  #if($fs eq "/test") {
  #  @filesystems=(
  #    "Filesystem           1M-blocks      Used Available Use% Mounted on",
  #    "/dev/mapper/n40l-root",
  #    "                        226741     22032    193192  11% /"
  #  );
  #  $fs = "/";
  #}
  #- DEBUG -
  
  
  #if(!defined @filesystems) { return $map; } # Ausgabe leer
  #if(scalar(@filesystems) == 0) { return $map; } # Array leer

  if(defined($filesystems[0])) {
  	logF($hash, "SYSMON_getFileSystemInfo", "recieved line0 $filesystems[0]");
  } else {
  	logF($hash, "SYSMON_getFileSystemInfo", "recieved empty line");
  }

  shift @filesystems;
  
  # Falls kein Eintrag gefunden (z.B: kein Medium im Laufwerk), mit Nullen fuellen (damit die Plots richtig funktionieren).
  if(defined $fDef) {
  	$map->{$fName} = "Total: 0 MB, Used: 0 MB, 0 %, Available: 0 MB at ".$fs." (not available)";
  } else {
    $map->{+FS_PREFIX.$fs} = "Total: 0 MB, Used: 0 MB, 0 %, Available: 0 MB at ".$fs." (not available)";
  }
  
  if(!defined $filesystems[0]) { return $map; } # Ausgabe leer
  
  logF($hash, "SYSMON_getFileSystemInfo", "analyse line $filesystems[0] for $fs");
  
  #if (!($filesystems[0]=~ /$fs\s*$/)){ shift @filesystems; }
  if (!($filesystems[0]=~ /$fs$/)){ 
    shift @filesystems; 
    logF($hash, "SYSMON_getFileSystemInfo", "analyse line $filesystems[0] for $fs");
  } else {
  	logF($hash, "SYSMON_getFileSystemInfo", "pattern ($fs) found");
  }
  #if (index($filesystems[0], $fs) < 0) { shift @filesystems; } # Wenn die Bezeichnung so lang ist, dass die Zeile umgebrochen wird...
  #if (index($filesystems[0], $fs) >= 0) # check if filesystem available -> gives failure on console
  if ($filesystems[0]=~ /$fs$/)
  {
  	logF($hash, "SYSMON_getFileSystemInfo", "use line $filesystems[0]");
  	
    my ($fs_desc, $total, $used, $available, $percentage_used, $mnt_point) = split(/\s+/, $filesystems[0]);
    $percentage_used =~ /^(.+)%$/;
    $percentage_used = $1;
    my $out_txt = "Total: ".$total." MB, Used: ".$used." MB, ".$percentage_used." %, Available: ".$available." MB at ".$mnt_point;
    if(defined $fDef) {
    	$map->{$fName} = $out_txt;
    } else {
      $map->{+FS_PREFIX.$mnt_point} = $out_txt;
    }
  }
  # else {
  #	if(defined $fDef) {
  #		$map->{$fName} = "not available";
  #	} else {
  #	  $map->{+FS_PREFIX.$fs} = "not available";
  #	}
  #}

  return $map;
}

#------------------------------------------------------------------------------
# Liefert Netztwerkinformationen
# Parameter: HASH; MAP; DEVICE (eth0 or wlan0)
#------------------------------------------------------------------------------
sub SYSMON_getNetworkInfo ($$$)
{
	my ($hash, $map, $device) = @_;
	logF($hash, "SYSMON_getNetworkInfo", "get $device");
	my($nName, $nDef) = split(/:/, $device);
	if(!defined $nDef) {
	  $nDef = $nName;
	}
	$device = $nDef;

  # in case of network not present get failure from stderr (2>&1)
  my $cmd="ifconfig ".$device." 2>&1";

  #my @dataThroughput = qx($cmd);
  my @dataThroughput = SYSMON_execute($hash, $cmd);
  #Log 3, "SYSMON>>>>>>>>>>>>>>>>> ".$dataThroughput[0];
  
  #--- DEBUG ---
  if($device eq "_test_") {
  	@dataThroughput = (
  	"enp4s0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1492",
  	"        inet 192.168.2.7  netmask 255.255.255.0  broadcast 192.168.2.255",
  	"        ether 00:21:85:5a:0d:e0  txqueuelen 1000  (Ethernet)",
  	"        RX packets 1553313  bytes 651891540 (621.6 MiB)",
  	"        RX errors 0  dropped 0  overruns 0  frame 0",
  	"        TX packets 1915387  bytes 587386206 (560.1 MiB)",
  	"        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0");
  }
  #--- DEBUG ---

  # check if network available
  if (index($dataThroughput[0], 'Fehler') < 0 && index($dataThroughput[0], 'error') < 0)
  {
  	#Log 3, "SYSMON>>>>>>>>>>>>>>>>> OK >>>".$dataThroughput[0];
    my $dataThroughput = undef;
    
    # Suche nach der Daten in Form:
    # eth0      Link encap:Ethernet  Hardware Adresse b8:27:eb:a5:e0:85
    #           inet Adresse:192.168.0.10  Bcast:192.168.0.255  Maske:255.255.255.0
    #           UP BROADCAST RUNNING MULTICAST  MTU:1500  Metrik:1
    #           RX packets:339826 errors:0 dropped:45 overruns:0 frame:0
    #           TX packets:533293 errors:0 dropped:0 overruns:0 carrier:0
    #           Kollisionen:0 Sendewarteschlangenlaenge:1000
    #           RX bytes:25517384 (24.3 MiB)  TX bytes:683970999 (652.2 MiB)

    foreach (@dataThroughput) {
      if(index($_, 'RX bytes') >= 0) {
        $dataThroughput = $_;
        last;
      }
    }

    my $rxRaw = -1;
    my $txRaw = -1;
    
    if(defined $dataThroughput) {
      # remove RX bytes or TX bytes from string
      $dataThroughput =~ s/RX bytes://;
      $dataThroughput =~ s/TX bytes://;
      $dataThroughput = trim($dataThroughput);

      @dataThroughput = split(/ /, $dataThroughput); # return of split is array
      $rxRaw = $dataThroughput[0] if(defined $dataThroughput[0]);
      $txRaw = $dataThroughput[4] if(defined $dataThroughput[4]);
    } else {
    	#
    	# an manchen Systemen kann die Ausgabe leider auch anders aussehen:
    	# enp4s0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1492
      #         inet 192.168.2.7  netmask 255.255.255.0  broadcast 192.168.2.255
      #         ether 00:21:85:5a:0d:e0  txqueuelen 1000  (Ethernet)
      #         RX packets 1553313  bytes 651891540 (621.6 MiB)
      #         RX errors 0  dropped 0  overruns 0  frame 0
      #         TX packets 1915387  bytes 587386206 (560.1 MiB)
      #         TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
    	#
    	my $d;
    	foreach $d (@dataThroughput) {
    		if($d =~ m/RX\s.*\sbytes\s(\d*)\s/) {
	        $rxRaw = $1;
        }
        if($d =~ m/TX\s.*\sbytes\s(\d*)\s/) {
	        $txRaw = $1;
        }
      }
    }
    
    if($rxRaw<0) {
    	# Daten nicht gefunden / Format unbekannt
    	$map->{$nName} = "unexpected format";
  	  $map->{$nName.DIFF_SUFFIX} = "unexpected format";
    } else {
      $rxRaw = $rxRaw / 1048576; # Bytes in MB
      $txRaw = $txRaw / 1048576;
    	
      my $rx = sprintf ("%.2f", $rxRaw);
      my $tx = sprintf ("%.2f", $txRaw);
      my $totalRxTx = $rx + $tx;

      my $out_txt = "RX: ".$rx." MB, TX: ".$tx." MB, Total: ".$totalRxTx." MB";
      $map->{$nName} = $out_txt;

      my $lastVal = ReadingsVal($hash->{NAME},$device,"RX: 0 MB, TX: 0 MB, Total: 0 MB");
      my ($d0, $o_rx, $d1, $d2, $o_tx, $d3, $d4, $o_tt, $d5) = split(/\s+/, trim($lastVal));

      my $d_rx = $rx-$o_rx;
      if($d_rx<0) {$d_rx=0;}
      my $d_tx = $tx-$o_tx;
      if($d_tx<0) {$d_tx=0;}
      my $d_tt = $totalRxTx-$o_tt;
      if($d_tt<0) {$d_tt=0;}
      my $out_txt_diff = "RX: ".sprintf ("%.2f", $d_rx)." MB, TX: ".sprintf ("%.2f", $d_tx)." MB, Total: ".sprintf ("%.2f", $d_tt)." MB";
      $map->{$nName.DIFF_SUFFIX} = $out_txt_diff;
    }
  } else {
  	#Log 3, "SYSMON>>>>>>>>>>>>>>>>> NOK ";
  	#Log 3, "SYSMON>>>>>>>>>>>>>>>>> >>> ".$nName;
  	$map->{$nName} = "not available";
  	$map->{$nName.DIFF_SUFFIX} = "not available";
  }

  return $map;
}

#------------------------------------------------------------------------------
# Liefert Informationen, ob WLAN an oder aus ist (nur FritzBox)
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBWLANState($$)
{
	my ($hash, $map) = @_;
	
	#logF($hash, "SYSMON_getFBWLANState", "");
	
	$map->{+FB_WLAN_STATE}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r wlan settings/ap_enabled",1);
	
	return $map;
}

#------------------------------------------------------------------------------
# Liefert Informationen, ob WLAN-Gastzugang an oder aus ist (nur FritzBox)
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBWLANGuestState($$)
{
	my ($hash, $map) = @_;
	
	#logF($hash, "SYSMON_getFBWLANGuestState", "");
	
	$map->{+FB_WLAN_GUEST_STATE}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r wlan settings/guest_ap_enabled",1);
	
	return $map;
}

#------------------------------------------------------------------------------
# Liefert IP Adresse im Internet (nur FritzBox)
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBInetIP($$)
{
	my ($hash, $map) = @_;
	
	$map->{+FB_INET_IP}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r dslstatistic status/ifacestat0/ipaddr");
	
	return $map;
}

#------------------------------------------------------------------------------
# Liefert Status Internet-Verbindung (nur FritzBox)
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBInetConnectionState($$)
{
	my ($hash, $map) = @_;
	
	$map->{+FB_INET_STATE}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r dslstatistic status/ifacestat0/connection_status");
	
	return $map;
}

#------------------------------------------------------------------------------
# Liefert Status Klingelsperre (nur FritzBox)
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBNightTimeControl($$)
{
	my ($hash, $map) = @_;
	
	$map->{+FB_N_TIME_CTRL}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r box settings/night_time_control_enabled",1);
	
	return $map;
}

#------------------------------------------------------------------------------
# Liefert Anzahl der nicht abgehoerten Nachrichten auf dem Anrufbeantworter (nur FritzBox)
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBNumNewMessages($$)
{
	my ($hash, $map) = @_;
	
	$map->{+FB_NUM_NEW_MESSAGES}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r tam status/NumNewMessages");
	
	return $map;
}

#------------------------------------------------------------------------------
# Liefert DECT-Temperatur einer FritzBox.
# Parameter: HASH; MAP
#------------------------------------------------------------------------------
sub SYSMON_getFBDECTTemp($$)
{
	my ($hash, $map) = @_;
	
	$map->{+FB_DECT_TEMP}=SYSMON_acquireInfo_intern($hash, "ctlmgr_ctl r dect status/Temperature");
	
	return $map;
}

# TODO: FritzBox-Infos: Dateien /var/env oder /proc/sys/urlader/environment. 

#------------------------------------------------------------------------------
# Liefert Informationen zu verschiedenen Eigenschaften durch Aufruf von entsprechenden Befehlen
# Parameter: HASH; cmd; Art (Interpretieren als: 1=on/off)
#------------------------------------------------------------------------------
sub SYSMON_acquireInfo_intern($$;$)
{
	my ($hash, $cmd, $art) = @_;
	
	logF($hash, "SYSMON_acquireInfo_intern", "cmd: ".$cmd);
	
	my $str = trim(SYSMON_execute($hash, $cmd));
	my $ret;
	
	if(!defined($art)) { $art= 0; }

  $ret = $str;
  no warnings;
  if($art == 1) {
    if($str+0 == 1) {
	   $ret="on";
    } else {
      if($str+0 == 0) {
        $ret="off";
	    }	else {
	  	  $ret="unknown";
	    }
    }
  }
  use warnings;
	return $ret;
}

sub SYSMON_FBVersionInfo($$)
{
	my ($hash, $map) = @_;
	
  my $data = SYSMON_execute($hash, "/etc/version --version --date");
  
  my($v, $d, $t) = split(/\s+/, $data);
  
  my $version = "";
  if(defined($v)) { $version = $v; }
  if(defined($d)) { $version.= " ".$d; }
  if(defined($t)) { $version.= " ".$t; }
  
  #if(defined($data[0])) {
  #	#Version
  #	$version = $data[0];
  #}
  #if(defined($data[1])) {
  #	#Date
  #	$version = $version." ".$data[1];
  #}
  
  if($version ne "") {
  	$map->{+FB_FW_VERSION}=$version;
  }
  
  return $map;
}

#------------------------------------------------------------------------------
# Systemparameter als HTML-Tabelle ausgeben
# Parameter: Name des SYSMON-Geraetes (muss existieren), dessen Daten zur Anzeige gebracht werden sollen.
# (optional) Liste der anzuzeigenden Werte (ReadingName[:Comment:[Postfix]],...)
# Beispiel: define sysv weblink htmlCode {SYSMON_ShowValuesHTML('sysmon', ('date:Datum', 'cpu_temp:CPU Temperatur: �C', 'cpu_freq:CPU Frequenz: MHz'))}
#------------------------------------------------------------------------------
sub SYSMON_ShowValuesHTML ($;@)
{
	my ($name, @data) = @_;
	return SYSMON_ShowValuesFmt($name, 1, @data);
}

#------------------------------------------------------------------------------
# Systemparameter im Textformat ausgeben
# Parameter: Name des SYSMON-Geraetes (muss existieren), dessen Daten zur Anzeige gebracht werden sollen.
# (optional) Liste der anzuzeigenden Werte (ReadingName[:Comment:[Postfix]],...)
# Beispiel: define sysv weblink htmlCode {SYSMON_ShowValuesText('sysmon', ('date:Datum', 'cpu_temp:CPU Temperatur: �C', 'cpu_freq:CPU Frequenz: MHz'))}
#------------------------------------------------------------------------------
sub SYSMON_ShowValuesText ($;@)
{
	my ($name, @data) = @_;
	return SYSMON_ShowValuesFmt($name, 0, @data);
}

#------------------------------------------------------------------------------
# Systemparameter formatiert ausgeben
# Parameter: 
#   Format: 0 = Text, 1 = HTML
#   Name des SYSMON-Geraetes (muss existieren), dessen Daten zur Anzeige gebracht werden sollen.
#   (optional) Liste der anzuzeigenden Werte (ReadingName[:Comment:[Postfix]],...)
#------------------------------------------------------------------------------
sub SYSMON_ShowValuesFmt ($$;@)
{
    my ($name, $format, @data) = @_;
    
    if($format != 0 && $format != 1) {
    	return "unknown output format\r\n";
    }
    
    my $hash = $main::defs{$name};
    
    #if(!defined($cur_readings_map)) {
	  #  SYSMON_updateCurrentReadingsMap($hash);
    #}
  
    SYSMON_updateCurrentReadingsMap($hash);
  #Log 3, "SYSMON $>name, @data<";
  my @dataDescription = @data;
  if(scalar(@data)<=0) {
	  # Array mit anzuzeigenden Parametern (Prefix, Name (in Map), Postfix)
	  my $deg = "�";
	  if($format == 1) {
	  	$deg = "&deg;";
	  }
	  @dataDescription = (DATE,
	                      CPU_TEMP.":".$cur_readings_map->{+CPU_TEMP}.": ".$deg."C", 
	                      CPU_FREQ.":".$cur_readings_map->{+CPU_FREQ}.": "."MHz", 
	                      CPU_BOGOMIPS,
	                      UPTIME_TEXT, FHEMUPTIME_TEXT, LOADAVG, RAM, SWAP);

	  # network-interfaces
  	my $networks = AttrVal($name, "network-interfaces", undef);
    if(defined $networks) {
      my @networks_list = split(/,\s*/, trim($networks));
      foreach (@networks_list) {
      	my($nName, $nDef, $nComment) = split(/:/, $_);
      	push(@dataDescription, $nName);
      }
    }
    
    # named filesystems
  	my $filesystems = AttrVal($name, "filesystems", undef);
    if(defined $filesystems) {
      my @filesystem_list = split(/,\s*/, trim($filesystems));
      foreach (@filesystem_list) {
        my($fName, $fDef, $fComment) = split(/:/, $_);
  	    push(@dataDescription, $fName);
  	  }
  	}
  	
  	# User defined
	  my $userdefined = AttrVal($name, "user-defined", undef);
    if(defined $userdefined) {
    	my @userdefined_list = split(/,\s*/, trim($userdefined));
      foreach (@userdefined_list) {
         # <readingName>:<Interval_Minutes>:<Comment>:<Cmd>
	       my($uName, $uInterval, $uComment, $uCmd) = split(/:/, $_);
	       push(@dataDescription, $uName);
      }
    }
  }
  
  my $map = SYSMON_obtainParameters($hash, 1);

  my $div_class="sysmon";

  my $htmlcode;
  if($format == 1) {
  	$htmlcode = "<div  class='".$div_class."'><table>";
  } else {
  	if($format == 0) {
  	  $htmlcode = "";
  	}
  }
  
  # oben definierte Werte anzeigen
  foreach (@dataDescription) {
  	my($rName, $rComment, $rPostfix) = split(/:/, $_);
  	if(defined $rName) {
  	  if(!defined $rComment) {
        $rComment = $cur_readings_map->{$rName};
      }
      my $rVal = $map->{$rName};
      if($rName eq DATE) {
      	# Datum anzeigen
  	    $rVal = strftime("%d.%m.%Y %H:%M:%S", localtime());
  	  }
  	  if(!defined $rPostfix) { $rPostfix = ""; }
  	  if(defined $rVal) {
  	  	if($format == 1) {
  	  	  $htmlcode .= "<tr><td valign='top'>".$rComment.":&nbsp;</td><td>".$rVal.$rPostfix."</td></tr>";
  	  	} else {
  	  		if($format == 0) {
            $htmlcode .= sprintf("%-24s: %s%s\r\n", $rComment, $rVal,$rPostfix);
          }
        }
      }
    }
  }
  
  # nur Default (also alles anzeigen)
  if(scalar(@data)<=0) {
    # File systems
    foreach my $aName (sort keys %{$map}) {
    	if(defined ($aName) && index($aName, FS_PREFIX) == 0) {
        $aName =~ /^~ (.+)/;
        if($format == 1) {
          $htmlcode .= "<tr><td valign='top'>File System: ".$1."&nbsp;</td><td>".$map->{$aName}."</td></tr>";
        } else {
        	if($format == 0) {
            $htmlcode .= sprintf("%-24s: %s\r\n", "File System: ".$1,$map->{$aName});
          }
        }
      }
    }
  }

  if($format == 1) {
    $htmlcode .= "</table></div><br>";
  } else {
  	if($format == 0) {
  	  $htmlcode .= "";
  	}
  }

  return $htmlcode;
}

my $sys_cpu_temp_rpi = undef;
sub
SYSMON_isCPUTempRPi($) {
	my ($hash) = @_;
	if(!defined $sys_cpu_temp_rpi) {
	  $sys_cpu_temp_rpi = int(SYSMON_execute($hash, "[ -f /sys/class/thermal/thermal_zone0/temp ] && echo 1 || echo 0"));
  }

	return $sys_cpu_temp_rpi;
}

my $sys_cpu_temp_bbb = undef;
sub
SYSMON_isCPUTempBBB($) {
	my ($hash) = @_;
	if(!defined $sys_cpu_temp_bbb) {
	  $sys_cpu_temp_bbb = int(SYSMON_execute($hash, "[ -f /sys/class/hwmon/hwmon0/device/temp1_input ] && echo 1 || echo 0"));
  }

	return $sys_cpu_temp_bbb;
}

my $sys_cpu_freq_rpi_bbb = undef;
sub
SYSMON_isCPUFreqRPiBBB($) {
	my ($hash) = @_;
	if(!defined $sys_cpu_freq_rpi_bbb) {
	  $sys_cpu_freq_rpi_bbb = int(SYSMON_execute($hash, "[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ] && echo 1 || echo 0"));
  }

	return $sys_cpu_freq_rpi_bbb;
}

my $sys_cpu1_freq = undef;
sub
SYSMON_isCPU1Freq($) {
	my ($hash) = @_;
	if(!defined $sys_cpu1_freq) {
	  $sys_cpu1_freq = int(SYSMON_execute($hash, "[ -f /sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq ] && echo 1 || echo 0"));
  }

	return $sys_cpu1_freq;
}

my $sys_fb = undef;
sub
SYSMON_isFB($) {
	my ($hash) = @_;
	if(!defined $sys_fb) {
	  $sys_fb = int(SYSMON_execute($hash, "[ -f /usr/bin/ctlmgr_ctl ] && echo 1 || echo 0"));
  } 
	return $sys_fb;
}

#-Power-------
my $sys_power_ac = undef;
sub
SYSMON_isSysPowerAc($) {
	my ($hash) = @_;
	if(!defined $sys_power_ac) {
	  $sys_power_ac = int(SYSMON_execute($hash, "[ -f /sys/class/power_supply/ac/online ] && echo 1 || echo 0"));
  }

	return $sys_power_ac;
}

my $sys_power_usb = undef;
sub
SYSMON_isSysPowerUsb($) {
	my ($hash) = @_;
	if(!defined $sys_power_usb) {
	  $sys_power_usb = int(SYSMON_execute($hash, "[ -f /sys/class/power_supply/usb/online ] && echo 1 || echo 0"));
  }

	return $sys_power_usb;
}

my $sys_power_bat = undef;
sub
SYSMON_isSysPowerBat($) {
	my ($hash) = @_;
	if(!defined $sys_power_bat) {
	  $sys_power_bat = int(SYSMON_execute($hash, "[ -f /sys/class/power_supply/battery/online ] && echo 1 || echo 0"));
  }

	return $sys_power_bat;
}

sub SYSMON_PowerAcInfo($$)
{
	#online, present, current_now (/1000 =>mA), voltage_now (/1000000 => V)
	my ($hash, $map) = @_;
	my $type="ac";
	my $base = "cat /sys/class/power_supply/".$type."/";
		
  my $d_online = trim(SYSMON_execute($hash, $base."online"));
  my $d_present = trim(SYSMON_execute($hash, $base."present"));
  my $d_current = SYSMON_execute($hash, $base."current_now");
  if(defined $d_current) {$d_current/=1000;}
  my $d_voltage = SYSMON_execute($hash, $base."voltage_now");
  if(defined $d_voltage) {$d_voltage/=1000000;}
  
  #$map->{"power_".$type."_online"}=$d_online;
  #$map->{"power_".$type."_present"}=$d_present;
  #$map->{"power_".$type."_current"}=$d_current;
  #$map->{"power_".$type."_voltage"}=$d_voltage;
  $map->{"power_".$type."_stat"}="$d_online $d_present $d_voltage $d_current";
  $map->{"power_".$type."_text"}=$type.": ".(($d_present eq "1") ? "present" : "absent")." / ".($d_online eq "1" ? "online" : "offline").", Voltage: ".$d_voltage." V, Current: ".$d_current." mA";
  
  return $map;
}

sub SYSMON_PowerUsbInfo($$)
{
	#online, present, current_now (/1000 =>mA), voltage_now (/1000000 => V)
	my ($hash, $map) = @_;
	my $type="usb";
	my $base = "cat /sys/class/power_supply/".$type."/";
		
  my $d_online = trim(SYSMON_execute($hash, $base."online"));
  my $d_present = trim(SYSMON_execute($hash, $base."present"));
  my $d_current = SYSMON_execute($hash, $base."current_now");
  if(defined $d_current) {$d_current/=1000;}
  my $d_voltage = SYSMON_execute($hash, $base."voltage_now");
  if(defined $d_voltage) {$d_voltage/=1000000;}
  
  #$map->{"power_".$type."_online"}=$d_online;
  #$map->{"power_".$type."_present"}=$d_present;
  #$map->{"power_".$type."_current"}=$d_current;
  #$map->{"power_".$type."_voltage"}=$d_voltage;
  $map->{"power_".$type."_stat"}="$d_online $d_present $d_voltage $d_current";
  $map->{"power_".$type."_text"}=$type.": ".(($d_present eq "1") ? "present" : "absent")." / ".($d_online eq "1" ? "online" : "offline").", Voltage: ".$d_voltage." V, Current: ".$d_current." mA";
  
  return $map;
}

sub SYSMON_PowerBatInfo($$)
{
	#online, present, current_now (/1000 =>mA), voltage_now (/1000000 => V)
	my ($hash, $map) = @_;
	my $type="battery";
	my $base = "cat /sys/class/power_supply/".$type."/";
		
  my $d_online = trim(SYSMON_execute($hash, $base."online"));
  my $d_present = trim(SYSMON_execute($hash, $base."present"));
  my $d_current = SYSMON_execute($hash, $base."current_now");
  if(defined $d_current) {$d_current/=1000;}
  my $d_voltage = SYSMON_execute($hash, $base."voltage_now");
  if(defined $d_voltage) {$d_voltage/=1000000;}
  
  #$map->{"power_".$type."_online"}=$d_online;
  #$map->{"power_".$type."_present"}=$d_present;
  #$map->{"power_".$type."_current"}=$d_current;
  #$map->{"power_".$type."_voltage"}=$d_voltage;
  $map->{"power_".$type."_stat"}="$d_online $d_present $d_voltage $d_current";
  $map->{"power_".$type."_text"}=$type.": ".(($d_present eq "1") ? "present" : "absent")." / ".($d_online eq "1" ? "online" : "offline").", Voltage: ".$d_voltage." V, Current: ".$d_current." mA";
  
  # TODO
  if($d_present eq "1") {
    # Zusaetzlich: technology, capacity, status, health, temp (/10 => �C)
    my $d_technology = trim(SYSMON_execute($hash, $base."technology"));
    my $d_capacity = trim(SYSMON_execute($hash, $base."capacity"));
    my $d_status = trim(SYSMON_execute($hash, $base."status"));
    my $d_health = trim(SYSMON_execute($hash, $base."health"));
    my $d_energy_full_design = trim(SYSMON_execute($hash, $base."energy_full_design"));
    
    $map->{"power_".$type."_info"}=$type." info: ".$d_technology." , capacity: ".$d_capacity." %, status: ".$d_status." , health: ".$d_health." , total capacity: ".$d_energy_full_design." mAh";
    
    # ggf. noch irgendwann: model_name, voltage_max_design, voltage_min_design
  } else {
  	$map->{"power_".$type."_info"}=$type." info: n/a , capacity: n/a %, status: n/a , health: n/a , total capacity: n/a mAh";
  }
  
  return $map;
}
#-------------

sub
SYSMON_execute($$)
{
	my ($hash, $cmd) = @_;
  return qx($cmd);
}

#------------------------------------------------------------------------------
# Uebersetzt Sekunden (Dauer) in Tage/Stunden/Minuten/Sekunden
#------------------------------------------------------------------------------
sub SYSMON_decode_time_diff($)
{
  my $s = shift;

  my $d = int($s/86400);
  $s -= $d*86400;
  my $h = int($s/3600);
  $s -= $h*3600;
  my $m = int($s/60);
  $s -= $m*60;

  return ($d,$h,$m,$s);
}

#------------------------------------------------------------------------------
# Logging: Funkrionsaufrufe
#   Parameter: HASH, Funktionsname, Message
#------------------------------------------------------------------------------
sub logF($$$)
{
	my ($hash, $fname, $msg) = @_;
  #Log 5, "SYSMON $fname (".$hash->{NAME}."): $msg";
  Log 5, "SYSMON $fname $msg";
}

#sub trim($)
#{ 
#   my $string = shift;
#   $string =~ s/^\s+//;
#   $string =~ s/\s+$//;
#   return $string;
#}

1;

=pod
=begin html

<!-- ================================ -->
<a name="SYSMON"></a>
<h3>SYSMON</h3>
<ul>
This module provides statistics about the system running FHEM server. Only Linux-based systems are supported. 
Some informations are hardware specific and are not available on every platform. 
So far, this module has been tested on the following systems: 
Raspberry Pi (Debian Wheezy) BeagleBone Black, FritzBox 7390 (no CPU data), WR703N under OpenWrt (no CPU data).
  <br><br>
  <b>Define</b>
  <br><br>
    <code>define &lt;name&gt; SYSMON [&lt;M1&gt;[ &lt;M2&gt;[ &lt;M3&gt;[ &lt;M4&gt;]]]]</code><br>
    <br>
    
This statement creates a new SYSMON instance. The parameters M1 to M4 define the refresh interval for various Readings (statistics). The parameters are to be understood as multipliers for the time defined by INTERVAL_BASE. Because this time is fixed at 60 seconds, the Mx-parameter can be considered as time intervals in minutes.<br>
If one (or more) of the multiplier is set to zero, the corresponding readings is deactivated.
    <br>
    <br>
    The parameters are responsible for updating the readings according to the following scheme:
    <ul>
     <li>M1: (Default: 1)<br>
     cpu_freq, cpu_temp, cpu_temp_avg, loadavg, stat_cpu, stat_cpu_diff, stat_cpu_percent, stat_cpu_text<br><br>
     </li>
     <li>M2: (Default: M1)<br>
     ram, swap<br>
     </li>
     <li>M3: (Default: M1)<br>
     eth0, eth0_diff, wlan0, wlan0_diff<br><br>
     </li>
     <li>M4: (Default: 10*M1)<br>
     Filesystem informations<br><br>
     </li>
     <li>The following parameters are always updated with the base interval (regardless of the Mx-parameter):<br>
     fhemuptime, fhemuptime_text, idletime, idletime_text, uptime, uptime_text<br><br>
     </li>
    </ul>
  <br>

  <b>Readings:</b>
  <br><br>
  <ul>
    <li>cpu_bogomips<br>
        CPU Speed: BogoMIPS
    </li>
    <li>cpu_freq<br>
        CPU frequency
    </li>
    <br>
    <li>cpu_temp<br>
        CPU temperature
    </li>
    <br>
    <li>cpu_temp_avg<br>
        Average of the CPU temperature, formed over the last 4 values.
    </li>
    <br>
    <li>fhemuptime<br>
    	Time (in seconds) since the start of FHEM server.
    </li>
    <br>
    <li>fhemuptime_text<br>
    	Time since the start of the FHEM server: human-readable output (text representation).
    </li>
    <br>
    <li>idletime<br>
    	Time spent by the system since the start in the idle mode (period of inactivity).
    </li>
    <br>
    <li>idletime_text<br>
    	The inactivity time of the system since system start in human readable form.
    </li>
    <br>
    <li>loadavg<br>
        System load (load average): 1 minute, 5 minutes and 15 minutes.
    </li>
    <br>
    <li>ram<br>
       memory usage.
    </li>
    <br>
    <li>swap<br>
    	swap usage.
    </li>
    <br>
    <li>uptime<br>
    	System uptime.
    </li>
    <br>
    <li>uptime_text<br>
    	System uptime (human readable).
    </li>
    <br>
    <li>Network statistics<br>
    Statistics for the specified network interface about the data volumes transferred and the difference since the previous measurement.
    <br>
    Examples:<br>
    Amount of the transmitted data via interface eth0.<br>
    <code>eth0: RX: 940.58 MB, TX: 736.19 MB, Total: 1676.77 MB</code><br>
    Change of the amount of the transferred data in relation to the previous call (for eth0).<br>
    <code>eth0_diff: RX: 0.66 MB, TX: 0.06 MB, Total: 0.72 MB</code><br>
    </li>
    <br>
    <li>File system information<br>
    	Usage of the desired file systems.<br>
    	Example:<br>
    		<code>fs_root: Total: 7340 MB, Used: 3573 MB, 52 %, Available: 3425 MB at /</code>
    </li>
    <br>
    <li>CPU utilization<br>
    		Information about the utilization of CPUs.<br>
    		Example:<br>
    		<code>stat_cpu: 10145283 0 2187286 90586051 542691 69393 400342</code><br>
        <code>stat_cpu_diff: 2151 0 1239 2522 10 3 761</code><br>
        <code>stat_cpu_percent: 4.82 0.00 1.81 93.11 0.05 0.00 0.20</code><br>
        <code>stat_cpu_text: user: 32.17 %, nice: 0.00 %, sys: 18.53 %, idle: 37.72 %, io: 0.15 %, irq: 0.04 %, sirq: 11.38 %</code>
    </li>
    <br>
    <li>user defined<br>
        These readings provide output of commands, which are passed to the operating system. 
    </li>
    <br>
    <b>FritzBox specific Readings</b>
    <li>wlan_state<br>
        WLAN state: on/off
    </li>
    <br>
    <li>wlan_guest_state<br>
        GuestWLAN state: on/off
    </li>
    <br>
    <li>internet_ip<br>
        current IP-Adresse
    </li>
    <br>
    <li>internet_state<br>
        state of the Internet connection: connected/disconnected
    </li>
    <br>
    <li>night_time_ctrl<br>
        state night time control (do not disturb): on/off
    </li>
    <br>
    <li>num_new_messages<br>
        Number of new Voice Mail messages
    </li>
    <br>
    <li>fw_version_info<br>
        Information on the installed firmware version: <VersionNum> <creation date> <time>
    </li>
    <br>
    <b>Power Supply Readings</b>
    <li>power_ac_stat<br>
        status information to the AC socket: present (0|1), online (0|1), voltage, current
        Example:<br>
    		<code>power_ac_stat: 1 1 4.807 264</code><br>
    </li>
    <br>
    <li>power_ac_text<br>
        human readable status information to the AC socket<br>
        Example:<br>
    		<code>power_ac_text ac: present / online, Voltage: 4.807 V, Current: 264 mA</code><br>
    </li>
    <br>
    <li>power_usb_stat<br>
        status information to the USB socket
    </li>
    <br>
    <li>power_usb_text<br>
        human readable status information to the USB socket
    </li>
    <br>
    <li>power_battery_stat<br>
        status information to the battery (if installed)
    </li>
    <br>
    <li>power_battery_text<br>
        human readable status information to the battery (if installed)
    </li>
    <br>
    <li>power_battery_info<br>
        human readable additional information to the battery (if installed): technology, capacity, status, health, total capacity<br>
        Example:<br>
    		<code>power_battery_info: battery info: Li-Ion , capacity: 100 %, status: Full , health: Good , total capacity: 2100 mAh</code><br>
    </li>
    <br>    
  <br>
  </ul>

  Sample output:<br>
  <ul>

<table style="border: 1px solid black;">
<tr><td style="border-bottom: 1px solid black;"><div class="dname">cpu_freq</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>900</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">cpu_temp</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>49.77</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">cpu_temp_avg</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>49.7</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">eth0</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>RX: 2954.22 MB, TX: 3469.21 MB, Total: 6423.43 MB</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">eth0_diff</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>RX: 6.50 MB, TX: 0.23 MB, Total: 6.73 MB</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">fhemuptime</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>11231</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">fhemuptime_text&nbsp;&nbsp;</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>0 days, 03 hours, 07 minutes</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">idletime</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>931024 88.35 %</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">idletime_text</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>10 days, 18 hours, 37 minutes (88.35 %)</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">loadavg</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>0.14 0.18 0.22</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">ram</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>Total: 485 MB, Used: 140 MB, 28.87 %, Free: 345 MB</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">swap</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>n/a</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">uptime</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>1053739</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">uptime_text</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>12 days, 04 hours, 42 minutes</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">wlan0</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>RX: 0.00 MB, TX: 0.00 MB, Total: 0 MB</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">wlan0_diff</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>RX: 0.00 MB, TX: 0.00 MB, Total: 0.00 MB</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">fs_root</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>Total: 7404 MB, Used: 3533 MB, 50 %, Available: 3545 MB at /</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">fs_boot</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>Total: 56 MB, Used: 19 MB, 33 %, Available: 38 MB at /boot</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname">fs_usb1</div></td>
<td style="border-bottom: 1px solid black;"><div>Total: 30942 MB, Used: 6191 MB, 21 %, Available: 24752 MB at /media/usb1&nbsp;&nbsp;</div></td>
<td style="border-bottom: 1px solid black;"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname">stat_cpu</div></td>
<td style="border-bottom: 1px solid black;"><div>10145283 0 2187286 90586051 542691 69393 400342&nbsp;&nbsp;</div></td>
<td style="border-bottom: 1px solid black;"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname">stat_cpu_diff</div></td>
<td style="border-bottom: 1px solid black;"><div>2151 0 1239 2522 10 3 761&nbsp;&nbsp;</div></td>
<td style="border-bottom: 1px solid black;"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname">stat_cpu_percent</div></td>
<td style="border-bottom: 1px solid black;"><div>4.82 0.00 1.81 93.11 0.05 0.00 0.20&nbsp;&nbsp;</div></td>
<td style="border-bottom: 1px solid black;"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td><div class="dname">stat_cpu_text</div></td>
<td><div>user: 32.17 %, nice: 0.00 %, sys: 18.53 %, idle: 37.72 %, io: 0.15 %, irq: 0.04 %, sirq: 11.38 %&nbsp;&nbsp;</div></td>
<td><div>2013-11-27 00:05:36</div></td>
</tr>
</table>
  </ul><br>

  <b>Get:</b><br><br>
    <ul>
    <li>interval<br>
    Lists the specified polling intervalls.
    </li>
    <br>
    <li>list<br>
    Lists all readings.
    </li>
    <br>
    <li>update<br>
    Refreshs all readings.
    </li>
    <br>
    <li>version<br>
    Displays the version of SYSMON module.
    </li>
    <br>
    </ul><br>

  <b>Set:</b><br><br>
    <ul>
    <li>interval_multipliers<br>
       Defines update intervals (as in the definition of the device).
    </li>
    <br>
    <li>clean<br>
      Clears user-definable Readings. After an update (manual or automatic) new readings are generated.<br>
    </li>
    <br>
    <li>clear &lt;reading name&gt;<br>
     Deletes the Reading entry with the given name. After an update this entry is possibly re-created (if defined). This mechanism allows the selective deleting unnecessary custom entries.<br>
    </li>
    <br>
    </ul><br>

  <b>Attributes:</b><br><br>
    <ul>
    <li>filesystems &lt;reading name&gt;[:&lt;mountpoint&gt;[:&lt;comment&gt;]],...<br>
    Specifies the file system to be monitored (a comma-separated list). <br>
    Reading-name is used in the display and logging, the mount point is the basis of the evaluation, comment is relevant to the HTML display (see SYSMON_ShowValuesHTML)<br>
    Examples: <br>
    <code>/boot,/,/media/usb1</code><br>
    <code>fs_boot:/boot,fs_root:/:Root,fs_usb1:/media/usb1:USB-Stick</code><br>
    </li>
    <br>
    <li>network-interfaces &lt;name&gt;[:&lt;interface&gt;[:&lt;comment&gt;]],...<br>
    Comma-separated list of network interfaces that are to be monitored. Each entry consists of the Reading-name, the name of the Netwerk adapter and a comment for the HTML output (see SYSMON_ShowValuesHTML). If no colon is used, the value is used simultaneously as a Reading-name and interface name.<br>
    Example <code>ethernet:eth0:Ethernet,wlan:wlan0:WiFi</code><br>
    </li>
    <br>
    <li>user-defined &lt;readingsName&gt;:&lt;Interval_Minutes&gt;:&lt;Comment&gt;:&lt;Cmd&gt;,...<br>
    This comma-separated list defines user defined Readings with the following data: Reading name, refresh interval (in minutes), a Comment, and operating system command.
    <br>The os commands are executed according to the specified Intervals and are noted as Readings with the specified name. Comments are used for the HTML output (see SYSMON_ShowValuesHTML)..
    <br>All parameter parts are required!
    <br>It is important that the specified commands are executed quickly, because at this time the entire FHEM server is blocked!<br>
    If results of the long-running operations required, these should be set up as a CRON job and store results as a text file.<br><br>
    Example: Display of package updates for the operating system:<br>
    cron-Job:<br>
    <code> apt-get upgrade --dry-run| perl -ne '/(\d*)\s[upgraded|aktualisiert]\D*(\d*)\D*install|^ \S+.*/ and print "$1 aktualisierte, $2 neue Pakete"' 2>/dev/null &gt; /opt/fhem/data/updatestatus.txt</code>
    <br>
    <code>uder-defined</code> attribute<br><code>sys_updates:1440:System Aktualisierungen:cat /opt/fhem/data/updatestatus.txt</code><br>
    the number of available updates is daily recorded as 'sys_updates'.
    </li>
    <br>
    <li>disable<br>
      Possible values: 0 and 1. '1' means that the update is stopped.
    </li>
    <br>
    </ul><br>

  <b>Plots:</b><br><br>
    <ul>
    predefined gplot files:<br>
     <ul>
      FileLog versions:<br>
      <code>
       SM_RAM.gplot<br>
       SM_CPUTemp.gplot<br>
       SM_FS_root.gplot<br>
       SM_FS_usb1.gplot<br>
       SM_Load.gplot<br>
       SM_Network_eth0.gplot<br>
       SM_Network_eth0t.gplot<br>
       SM_Network_wlan0.gplot<br>
       SM_CPUStat.gplot<br>
       SM_CPUStatSum.gplot<br>
       SM_CPUStatTotal.gplot<br>
      </code>
      DbLog versions:<br>
      <code>
       SM_DB_all.gplot<br>
       SM_DB_CPUFreq.gplot<br>
       SM_DB_CPUTemp.gplot<br>
       SM_DB_Load.gplot<br>
       SM_DB_Network_eth0.gplot<br>
       SM_DB_RAM.gplot<br>
      </code>
     </ul>
    </ul><br>

  <b>HTML output method (see Weblink): SYSMON_ShowValuesHTML(&lt;SYSMON-Instance&gt;[,&lt;Liste&gt;])</b><br><br>
    <ul>
    The module provides a function that returns selected Readings as HTML.<br>
    As a parameter the name of the defined SYSMON device is expected.<br>
    The second parameter is optional and specifies a list of readings to be displayed in the format <code>&lt;ReadingName&gt;[:&lt;Comment&gt;[:&lt;Postfix&gt;]]</code>.<br>
    <code>ReadingName</code> is the Name of desired Reading, <code>Comment</code> is used as the display name and postfix is displayed after eihentlichen value (such as units or as MHz can be displayed).<br>
    If no <code>Comment</code> is specified, an internally predefined description is used.<br>
    If no list specified, a predefined selection is used (all values are displayed).<br><br>
    <code>define sysv1 weblink htmlCode {SYSMON_ShowValuesHTML('sysmon')}</code><br>
    <code>define sysv2 weblink htmlCode {SYSMON_ShowValuesHTML('sysmon', ('date:Datum', 'cpu_temp:CPU Temperatur: &deg;C', 'cpu_freq:CPU Frequenz: MHz'))}</code>
    </ul><br>
    
  <b>Text output method (see Weblink): SYSMON_ShowValuesText(&lt;SYSMON-Instance&gt;[,&lt;Liste&gt;])</b><br><br>
    <ul>
    According to SYSMON_ShowValuesHTML, but formatted as plain text.<br>
    </ul><br>
    
  <b>Reading values with perl: SYSMON_getValues([&lt;array of desired keys&gt;])</b><br><br>
    <ul>
    Returns a hash ref with desired values. If no array is passed, all values are returned.<br>
    </ul><br>

  <b>Examples:</b><br><br>
    <ul>
    <code>
      # Modul-Definition<br>
      define sysmon SYSMON 1 1 1 10<br>
      #attr sysmon event-on-update-reading cpu_temp,cpu_temp_avg,cpu_freq,eth0_diff,loadavg,ram,^~ /.*usb.*,~ /$<br>
      attr sysmon event-on-update-reading cpu_temp,cpu_temp_avg,cpu_freq,eth0_diff,loadavg,ram,fs_.*,stat_cpu_percent<br>
      attr sysmon filesystems fs_boot:/boot,fs_root:/:Root,fs_usb1:/media/usb1:USB-Stick<br>
      attr sysmon network-interfaces eth0:eth0:Ethernet,wlan0:wlan0:WiFi<br>
      attr sysmon group RPi<br>
      attr sysmon room 9.03_Tech<br>
      <br>
      # Log<br>
      define FileLog_sysmon FileLog ./log/sysmon-%Y-%m.log sysmon<br>
      attr FileLog_sysmon group RPi<br>
      attr FileLog_sysmon logtype SM_CPUTemp:Plot,text<br>
      attr FileLog_sysmon room 9.03_Tech<br>
      <br>
      # Visualisierung: CPU-Temperatur<br>
      define wl_sysmon_temp SVG FileLog_sysmon:SM_CPUTemp:CURRENT<br>
      attr wl_sysmon_temp group RPi<br>
      attr wl_sysmon_temp label "CPU Temperatur: Min $data{min2}, Max $data{max2}, Last $data{currval2}"<br>
      attr wl_sysmon_temp room 9.03_Tech<br>
      <br>
      # Visualisierung: Netzwerk-Daten&uuml;bertragung f&uuml;r eth0<br>
      define wl_sysmon_eth0 SVG FileLog_sysmon:SM_Network_eth0:CURRENT<br>
      attr wl_sysmon_eth0 group RPi<br>
      attr wl_sysmon_eth0 label "Netzwerk-Traffic eth0: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"<br>
      attr wl_sysmon_eth0 room 9.03_Tech<br>
      <br>
      # Visualisierung: Netzwerk-Daten&uuml;bertragung f&uuml;r wlan0<br>
      define wl_sysmon_wlan0 SVG FileLog_sysmon:SM_Network_wlan0:CURRENT<br>
      attr wl_sysmon_wlan0 group RPi<br>
      attr wl_sysmon_wlan0 label "Netzwerk-Traffic wlan0: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"<br>
      attr wl_sysmon_wlan0 room 9.03_Tech<br>
      <br>
      # Visualisierung: CPU-Auslastung (load average)<br>
      define wl_sysmon_load SVG FileLog_sysmon:SM_Load:CURRENT<br>
      attr wl_sysmon_load group RPi<br>
      attr wl_sysmon_load label "Load Min: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"<br>
      attr wl_sysmon_load room 9.03_Tech<br>
      <br>
      # Visualisierung: RAM-Nutzung<br>
      define wl_sysmon_ram SVG FileLog_sysmon:SM_RAM:CURRENT<br>
      attr wl_sysmon_ram group RPi<br>
      attr wl_sysmon_ram label "RAM-Nutzung Total: $data{max1}, Min: $data{min2}, Max: $data{max2}, Aktuell: $data{currval2}"<br>
      attr wl_sysmon_ram room 9.03_Tech<br>
      <br>
      # Visualisierung: Dateisystem: Root-Partition<br>
      define wl_sysmon_fs_root SVG FileLog_sysmon:SM_FS_root:CURRENT<br>
      attr wl_sysmon_fs_root group RPi<br>
      attr wl_sysmon_fs_root label "Root Partition Total: $data{max1}, Min: $data{min2}, Max: $data{max2}, Aktuell: $data{currval2}"<br>
      attr wl_sysmon_fs_root room 9.03_Tech<br>
      <br>
      # Visualisierung: Dateisystem: USB-Stick<br>
      define wl_sysmon_fs_usb1 SVG FileLog_sysmon:SM_FS_usb1:CURRENT<br>
      attr wl_sysmon_fs_usb1 group RPi<br>
      attr wl_sysmon_fs_usb1 label "USB1 Total: $data{max1}, Min: $data{min2}, Max: $data{max2}, Aktuell: $data{currval2}"<br>
      attr wl_sysmon_fs_usb1 room 9.03_Tech<br>
      <br>
      # Anzeige der Readings zum Einbinden in ein 'Raum'.<br>
      define SysValues weblink htmlCode {SYSMON_ShowValuesHTML('sysmon')}<br>
      attr SysValues group RPi<br>
      attr SysValues room 9.03_Tech<br>
      <br>
      # Anzeige CPU Auslasung<br>
      define wl_sysmon_cpustat SVG FileLog_sysmon:SM_CPUStat:CURRENT<br>
      attr wl_sysmon_cpustat label "CPU(min/max): user:$data{min1}/$data{max1} nice:$data{min2}/$data{max2} sys:$data{min3}/$data{max3} idle:$data{min4}/$data{max4} io:$data{min5}/$data{max5} irq:$data{min6}/$data{max6} sirq:$data{min7}/$data{max7}"<br>
      attr wl_sysmon_cpustat group RPi<br>
      attr wl_sysmon_cpustat room 9.99_Test<br>
      attr wl_sysmon_cpustat plotsize 840,420<br>
      define wl_sysmon_cpustat_s SVG FileLog_sysmon:SM_CPUStatSum:CURRENT<br>
      attr wl_sysmon_cpustat_s label "CPU(min/max): user:$data{min1}/$data{max1} nice:$data{min2}/$data{max2} sys:$data{min3}/$data{max3} idle:$data{min4}/$data{max4} io:$data{min5}/$data{max5} irq:$data{min6}/$data{max6} sirq:$data{min7}/$data{max7}"<br>
      attr wl_sysmon_cpustat_s group RPi<br>
      attr wl_sysmon_cpustat_s room 9.99_Test<br>
      attr wl_sysmon_cpustat_s plotsize 840,420<br>
      define wl_sysmon_cpustatT SVG FileLog_sysmon:SM_CPUStatTotal:CURRENT<br>
      attr wl_sysmon_cpustatT label "CPU-Auslastung"<br>
      attr wl_sysmon_cpustatT group RPi<br>
      attr wl_sysmon_cpustatT plotsize 840,420<br>
      attr wl_sysmon_cpustatT room 9.99_Test<br>
    </code>
    </ul>

  </ul>
<!-- ================================ -->

=end html
=begin html_DE

<a name="SYSMON"></a>
<h3>SYSMON</h3>
<ul>
  Dieses Modul liefert diverse Informationen und Statistiken zu dem System, auf dem FHEM-Server ausgef&uuml;hrt wird.
  Es werden nur Linux-basierte Systeme unterst&uuml;tzt. Manche Informationen sind hardwarespezifisch und sind daher nicht auf jeder Plattform 
  verf&uuml;gbar.
  Bis jetzt wurde dieses Modul auf folgenden Systemen getestet: Raspberry Pi (Debian Wheezy), BeagleBone Black, 
  FritzBox 7390 (keine CPU-Daten), WR703N unter OpenWrt.
  <br><br>
  <b>Define</b>
  <br><br>
    <code>define &lt;name&gt; SYSMON [&lt;M1&gt;[ &lt;M2&gt;[ &lt;M3&gt;[ &lt;M4&gt;]]]]</code><br>
    <br>
    Diese Anweisung erstellt eine neue SYSMON-Instanz.
    Die Parameter M1 bis M4 legen die Aktualisierungsintervalle f&uuml;r verschiedenen Readings (Statistiken) fest.
    Die Parameter sind als Multiplikatoren f&uuml;r die Zeit, die durch INTERVAL_BASE definiert ist, zu verstehen.
    Da diese Zeit fest auf 60 Sekunden gesetzt ist, k&ouml;nnen die Mx-Parameters als Zeitintervalle in Minuten angesehen werden.<br>
    Wird einer (oder mehrere) Multiplikatoren auf Null gesetzt werden, wird das entsprechende Readings deaktiviert.<br>
    <br>
    Die Parameter sind f&uuml;r die Aktualisierung der Readings nach folgender Schema zust&auml;ndig:
    <ul>
     <li>M1: (Default-Wert: 1)<br>
     cpu_freq, cpu_temp, cpu_temp_avg, loadavg, stat_cpu, stat_cpu_diff, stat_cpu_percent, stat_cpu_text<br><br>
     </li>
     <li>M2: (Default-Wert: M1)<br>
     ram, swap<br>
     </li>
     <li>M3: (Default-Wert: M1)<br>
     eth0, eth0_diff, wlan0, wlan0_diff<br><br>
     </li>
     <li>M4: (Default-Wert: 10*M1)<br>
     Filesystem-Informationen<br><br>
     </li>
     <li>folgende Parameter werden immer anhand des Basisintervalls (unabh&auml;ngig von den Mx-Parameters) aktualisiert:<br>
     fhemuptime, fhemuptime_text, idletime, idletime_text, uptime, uptime_text<br><br>
     </li>
    </ul>
  <br>

  <b>Readings:</b>
  <br><br>
  <ul>
    <li>cpu_bogomips<br>
        CPU Speed: BogoMIPS
    </li>
    <li>cpu_freq<br>
        CPU-Frequenz
    </li>
    <br>
    <li>cpu_temp<br>
        CPU-Temperatur
    </li>
    <br>
    <li>cpu_temp_avg<br>
        Durchschnitt der CPU-Temperatur, gebildet &uuml;ber die letzten 4 Werte.
    </li>
    <br>
    <li>fhemuptime<br>
    		Zeit (in Sekunden) seit dem Start des FHEM-Servers.
    </li>
    <br>
    <li>fhemuptime_text<br>
    		Zeit seit dem Start des FHEM-Servers: Menschenlesbare Ausgabe (texttuelle Darstellung).
    </li>
    <br>
    <li>idletime<br>
    		Zeit (in Sekunden und in Prozent), die das System (nicht der FHEM-Server!)
    		seit dem Start in dem Idle-Modus verbracht hat. Also die Zeit der Inaktivit&auml;t.
    </li>
    <br>
    <li>idletime_text<br>
    		Zeit der Inaktivit&auml;t des Systems seit dem Systemstart in menschenlesbarer Form.
    </li>
    <br>
    <li>loadavg<br>
        Ausgabe der Werte f&uuml;r die Systemauslastung (load average): 1 Minute-, 5 Minuten- und 15 Minuten-Werte.
    </li>
    <br>
    <li>ram<br>
       Ausgabe der Speicherauslastung.
    </li>
    <br>
    <li>swap<br>
    		Benutzung und Auslastung der SWAP-Datei (bzw. Partition).
    </li>
    <br>
    <li>uptime<br>
    		Zeit (in Sekenden) seit dem Systemstart.
    </li>
    <br>
    <li>uptime_text<br>
    		Zeit seit dem Systemstart in menschenlesbarer Form.
    </li>
    <br>
    <li>Netzwerkinformationen<br>
    Informationen zu den &uuml;ber die angegebene Netzwerkschnittstellen &uuml;bertragene Datenmengen 
    und der Differenz zu der vorherigen Messung.
    <br>
    Beispiele:<br>
    Menge der &uuml;bertragenen Daten &uuml;ber die Schnittstelle eth0.<br>
    <code>eth0: RX: 940.58 MB, TX: 736.19 MB, Total: 1676.77 MB</code><br>
    &Auml;nderung der &uuml;bertragenen Datenmenge in Bezug auf den vorherigen Aufruf (f&uuml;r eth0).<br>
    <code>eth0_diff: RX: 0.66 MB, TX: 0.06 MB, Total: 0.72 MB</code><br>
    </li>
    <br>
    <li>Dateisysteminformationen<br>
    		Informationen zu der Gr&ouml;&szlig;e und der Belegung der gew&uuml;nschten Dateisystemen.<br>
    		Seit Version 1.1.0 k&ouml;nnen Dateisysteme auch benannt werden (s.u.). <br>
    		In diesem Fall werden f&uuml;r die diese Readings die angegebenen Namen verwendet.<br>
    		Dies soll die &Uuml;bersicht verbessern und die Erstellung von Plots erleichten.<br>
    		Beispiel:<br>
    		<code>fs_root: Total: 7340 MB, Used: 3573 MB, 52 %, Available: 3425 MB at /</code>
    </li>
    <br>
    <li>CPU Auslastung<br>
    		Informationen zu der Auslastung der CPU(s).<br>
    		Beispiel:<br>
    		<code>stat_cpu: 10145283 0 2187286 90586051 542691 69393 400342</code><br>
        <code>stat_cpu_diff: 2151 0 1239 2522 10 3 761</code><br>
        <code>stat_cpu_percent: 4.82 0.00 1.81 93.11 0.05 0.00 0.20</code><br>
        <code>stat_cpu_text: user: 32.17 %, nice: 0.00 %, sys: 18.53 %, idle: 37.72 %, io: 0.15 %, irq: 0.04 %, sirq: 11.38 %</code>
    </li>
    <br>
    <li>Benutzerdefinierte Eintr&auml;ge<br>
        Diese Readings sind Ausgaben der Kommanden, die an das Betriebssystem &uuml;bergeben werden.
        Die entsprechende Angaben werden im Attribut <code>user-defined</code> vorgenommen.
    </li>
    <br>
    <b>FritzBox-spezifische Readings</b>
    <li>wlan_state<br>
        WLAN-Status: on/off
    </li>
    <br>
    <li>wlan_guest_state<br>
        Gast-WLAN-Status: on/off
    </li>
    <br>
    <li>internet_ip<br>
        aktuelle IP-Adresse
    </li>
    <br>
    <li>internet_state<br>
        Status der Internetverbindung: connected/disconnected
    </li>
    <br>
    <li>night_time_ctrl<br>
        Status der Klingelsperre on/off
    </li>
    <br>
    <li>num_new_messages<br>
        Anzahl der neuen Anrufbeantworter-Meldungen
    </li>
    <br>
    <li>fw_version_info<br>
        Angaben zu der installierten Firmware-Version: <VersionNr> <Erstelldatum> <Zeit>
    </li>
    <br>
    <b>Readings zur Stromversorgung</b>
    <li>power_ac_stat<br>
        Statusinformation f&uuml;r die AC-Buchse: present (0|1), online (0|1), voltage, current
        Beispiel:<br>
    		<code>power_ac_stat: 1 1 4.807 264</code><br>
    </li>
    <br>
    <li>power_ac_text<br>
        Statusinformation f&uuml;r die AC-Buchse in menschenlesbarer Form<br>
        Beispiel:<br>
    		<code>power_ac_text ac: present / online, Voltage: 4.807 V, Current: 264 mA</code><br>
    </li>
    <br>
    <li>power_usb_stat<br>
        Statusinformation f&uuml;r die USB-Buchse
    </li>
    <br>
    <li>power_usb_text<br>
        Statusinformation f&uuml;r die USB-Buchse in menschenlesbarer Form
    </li>
    <br>
    <li>power_battery_stat<br>
        Statusinformation f&uuml;r die Batterie (wenn vorhanden)
    </li>
    <br>
    <li>power_battery_text<br>
        Statusinformation f&uuml;r die Batterie (wenn vorhanden) in menschenlesbarer Form
    </li>
    <br>
    <li>power_battery_info<br>
        Menschenlesbare Zusatzinformationen  f&uuml;r die Batterie (wenn vorhanden): Technologie, Kapazit&auml;t, Status, Zustand, Gesamtkapazit&auml;t<br>
        Beispiel:<br>
    		<code>power_battery_info: battery info: Li-Ion , capacity: 100 %, status: Full , health: Good , total capacity: 2100 mAh</code><br>
    </li>
    <br>    
  <br>
  </ul>

  Beispiel-Ausgabe:<br>
  <ul>

<table style="border: 1px solid black;">
<tr><td style="border-bottom: 1px solid black;"><div class="dname">cpu_freq</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>900</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">cpu_temp</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>49.77</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">cpu_temp_avg</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>49.7</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">eth0</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>RX: 2954.22 MB, TX: 3469.21 MB, Total: 6423.43 MB</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">eth0_diff</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>RX: 6.50 MB, TX: 0.23 MB, Total: 6.73 MB</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">fhemuptime</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>11231</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">fhemuptime_text&nbsp;&nbsp;</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>0 days, 03 hours, 07 minutes</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">idletime</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>931024 88.35 %</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">idletime_text</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>10 days, 18 hours, 37 minutes (88.35 %)</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">loadavg</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>0.14 0.18 0.22</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">ram</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>Total: 485 MB, Used: 140 MB, 28.87 %, Free: 345 MB</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">swap</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>n/a</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">uptime</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>1053739</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">uptime_text</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>12 days, 04 hours, 42 minutes</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">wlan0</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>RX: 0.00 MB, TX: 0.00 MB, Total: 0 MB</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">wlan0_diff</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>RX: 0.00 MB, TX: 0.00 MB, Total: 0.00 MB</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">fs_root</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>Total: 7404 MB, Used: 3533 MB, 50 %, Available: 3545 MB at /</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname"><div class="dname">fs_boot</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>Total: 56 MB, Used: 19 MB, 33 %, Available: 38 MB at /boot</div></td>
<td style="border-bottom: 1px solid black;"><div class="dname"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname">fs_usb1</div></td>
<td style="border-bottom: 1px solid black;"><div>Total: 30942 MB, Used: 6191 MB, 21 %, Available: 24752 MB at /media/usb1&nbsp;&nbsp;</div></td>
<td style="border-bottom: 1px solid black;"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname">stat_cpu</div></td>
<td style="border-bottom: 1px solid black;"><div>10145283 0 2187286 90586051 542691 69393 400342&nbsp;&nbsp;</div></td>
<td style="border-bottom: 1px solid black;"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname">stat_cpu_diff</div></td>
<td style="border-bottom: 1px solid black;"><div>2151 0 1239 2522 10 3 761&nbsp;&nbsp;</div></td>
<td style="border-bottom: 1px solid black;"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td style="border-bottom: 1px solid black;"><div class="dname">stat_cpu_percent</div></td>
<td style="border-bottom: 1px solid black;"><div>4.82 0.00 1.81 93.11 0.05 0.00 0.20&nbsp;&nbsp;</div></td>
<td style="border-bottom: 1px solid black;"><div>2013-11-27 00:05:36</div></td>
</tr>
<tr><td><div class="dname">stat_cpu_text</div></td>
<td><div>user: 32.17 %, nice: 0.00 %, sys: 18.53 %, idle: 37.72 %, io: 0.15 %, irq: 0.04 %, sirq: 11.38 %&nbsp;&nbsp;</div></td>
<td><div>2013-11-27 00:05:36</div></td>
</tr>
</table>
  </ul><br>

  <b>Get:</b><br><br>
    <ul>
    <li>interval<br>
    Listet die bei der Definition angegebene Polling-Intervalle auf.
    </li>
    <br>
    <li>list<br>
    Gibt alle Readings aus.
    </li>
    <br>
    <li>update<br>
    Aktualisiert alle Readings. Alle Werte werden neu abgefragt.
    </li>
    <br>
    <li>version<br>
    Zeigt die Version des SYSMON-Moduls.
    </li>
    <br>
    </ul><br>

  <b>Set:</b><br><br>
    <ul>
    <li>interval_multipliers<br>
    Definiert Multipliers (wie bei der Definition des Ger&auml;tes).
    </li>
    <br>
    <li>clean<br>
    L&ouml;scht benutzerdefinierbare Readings. Nach einem Update (oder nach der automatischen Aktualisierung) werden neue Readings generiert.<br>
    </li>
    <br>
    <li>clear &lt;reading name&gt;<br>
    L&ouml;scht den Reading-Eintrag mit dem gegebenen Namen. Nach einem Update (oder nach der automatischen Aktualisierung) 
    wird dieser Eintrag ggf. neu erstellt (falls noch definiert). Dieses Mechanismus erlaubt das gezielte L&ouml;schen nicht mehr ben&ouml;tigter 
    benutzerdefinierten Eintr&auml;ge.<br>
    </li>
    <br>
    </ul><br>

  <b>Attributes:</b><br><br>
    <ul>
    <li>filesystems &lt;reading name&gt;[:&lt;mountpoint&gt;[:&lt;comment&gt;]],...<br>
    Gibt die zu &uuml;berwachende Dateisysteme an. Es wird eine kommaseparierte Liste erwartet.<br>
    Reading-Name wird bei der Anzeige und Logging verwendet, Mount-Point ist die Grundlage der Auswertung, 
    Kommentar ist relevant f&uuml;r die HTML-Anzeige (s. SYSMON_ShowValuesHTML)<br>
    Beispiel: <code>/boot,/,/media/usb1</code><br>
    oder: <code>fs_boot:/boot,fs_root:/:Root,fs_usb1:/media/usb1:USB-Stick</code><br>
    Im Sinne der besseren &Uuml;bersicht sollten zumindest Name und MountPoint angegeben werden.
    </li>
    <br>
    <li>network-interfaces &lt;name&gt;[:&lt;interface&gt;[:&lt;comment&gt;]],...<br>
    Kommaseparierte Liste der Netzwerk-Interfaces, die &uuml;berwacht werden sollen.
    Jeder Eintrag besteht aus dem Reading-Namen, dem Namen 
    des Netwerk-Adapters und einem Kommentar f&uuml;r die HTML-Anzeige (s. SYSMON_ShowValuesHTML). Wird kein Doppelpunkt verwendet, 
    wird der Wert gleichzeitig als Reading-Name und Interface-Name verwendet.<br>
    Beispiel <code>ethernet:eth0:Ethernet,wlan:wlan0:WiFi</code><br>
    </li>
    <br>
    <li>user-defined &lt;readingsName&gt;:&lt;Interval_Minutes&gt;:&lt;Comment&gt;:&lt;Cmd&gt;,...<br>
    Diese kommaseparierte Liste definiert Eintr&auml;ge mit jeweils folgenden Daten: 
    Reading-Name, Aktualisierungsintervall in Minuten, Kommentar und Betriebssystem-Commando.
    <br>Die BS-Befehle werden entsprechend des angegebenen Intervalls ausgef&uuml;hrt und als Readings mit den angegebenen Namen vermerkt.
    Kommentare werden f&uuml;r die HTML-Ausgaben (s. SYSMON_ShowValuesHTML) ben&ouml;tigt.
    <br>Alle Parameter sind nicht optional!
    <br>Es ist wichtig, dass die angegebenen Befehle schnell ausgef&uuml;hrt werden, denn in dieser Zeit wird der gesamte FHEM-Server blockiert!
    <br>Werden Ergebnisse der lang laufenden Operationen ben&ouml;tigt, sollten diese z.B als CRON-Job eingerichtet werden 
    und in FHEM nur die davor gespeicherten Ausgaben visualisiert.<br><br>
    Beispiel: Anzeige der vorliegenden Paket-Aktualisierungen f&uuml;r das Betriebssystem:<br>
    In einem cron-Job wird folgendes t&auml;glich ausgef&uuml;hrt: <br>
    <code> apt-get upgrade --dry-run| perl -ne '/(\d*)\s[upgraded|aktualisiert]\D*(\d*)\D*install|^ \S+.*/ and print "$1 aktualisierte, $2 neue Pakete"' 2>/dev/null &gt; /opt/fhem/data/updatestatus.txt</code>
    <br>
    Das Attribute <code>uder-defined</code> wird auf <br><code>sys_updates:1440:System Aktualisierungen:cat /opt/fhem/data/updatestatus.txt</code><br> gesetzt.
    Danach wird die Anzahl der verf&uuml;gbaren Aktualisierungen t&auml;glich als Reading 'sys_updates' protokolliert.
    </li>
    <br>
    <li>disable<br>
    M&ouml;gliche Werte: <code>0,1</code>. Bei <code>1</code> wird die Aktualisierung gestoppt.
    </li>
    <br>
    </ul><br>

  <b>Plots:</b><br><br>
    <ul>
    F&uuml;r dieses Modul sind bereits einige gplot-Dateien vordefiniert:<br>
     <ul>
      FileLog-Versionen:<br>
      <code>
       SM_RAM.gplot<br>
       SM_CPUTemp.gplot<br>
       SM_FS_root.gplot<br>
       SM_FS_usb1.gplot<br>
       SM_Load.gplot<br>
       SM_Network_eth0.gplot<br>
       SM_Network_eth0t.gplot<br>
       SM_Network_wlan0.gplot<br>
       SM_CPUStat.gplot<br>
       SM_CPUStatSum.gplot<br>
       SM_CPUStatTotal.gplot<br>
      </code>
      DbLog-Versionen:<br>
      <code>
       SM_DB_all.gplot<br>
       SM_DB_CPUFreq.gplot<br>
       SM_DB_CPUTemp.gplot<br>
       SM_DB_Load.gplot<br>
       SM_DB_Network_eth0.gplot<br>
       SM_DB_RAM.gplot<br>
      </code>
     </ul>
    </ul><br>

  <b>HTML-Ausgabe-Methode (f&uuml;r ein Weblink): SYSMON_ShowValuesHTML(&lt;SYSMON-Instanz&gt;[,&lt;Liste&gt;])</b><br><br>
    <ul>
    Das Modul definiert eine Funktion, die ausgew&auml;hlte Readings in HTML-Format ausgibt. <br>
    Als Parameter wird der Name des definierten SYSMON-Ger&auml;ts erwartet.<br>
    Der zweite Parameter ist optional und gibt eine Liste der anzuzeigende Readings 
    im Format <code>&lt;ReadingName&gt;[:&lt;Comment&gt;[:&lt;Postfix&gt;]]</code> an.<br>
    Dabei gibt <code>ReadingName</code> den anzuzeigenden Reading an, der Wert aus <code>Comment</code> wird als der Anzeigename verwendet
    und <code>Postfix</code> wird nach dem eihentlichen Wert angezeigt (so k&ouml;nnen z.B. Einheiten wie MHz angezeigt werden).<br>
    Falls kein <code>Comment</code> angegeben ist, wird eine intern vordefinierte Beschreibung angegeben. 
    Bei benutzerdefinierbaren Readings wird ggf. <code>Comment</code> aus der Definition verwendet.<br>
    Wird keine Liste angegeben, wird eine vordefinierte Auswahl verwendet (alle Werte).<br><br>
    <code>define sysv1 weblink htmlCode {SYSMON_ShowValuesHTML('sysmon')}</code><br>
    <code>define sysv2 weblink htmlCode {SYSMON_ShowValuesHTML('sysmon', ('date:Datum', 'cpu_temp:CPU Temperatur: &deg;C', 'cpu_freq:CPU Frequenz: MHz'))}</code>
    </ul><br>
    
    <b>Text-Ausgabe-Methode (see Weblink): SYSMON_ShowValuesText(&lt;SYSMON-Instance&gt;[,&lt;Liste&gt;])</b><br><br>
    <ul>
    Analog SYSMON_ShowValuesHTML, jedoch formatiert als reines Text.<br>
    </ul><br>
    
    <b>Readings-Werte mit Perl lesen: SYSMON_getValues([&lt;Liste der gew&uuml;nschten Schl&uuml;ssel&gt;])</b><br><br>
    <ul>
    Liefert ein Hash-Ref mit den gew&uuml;nschten Werten. Wenn keine Liste (array) &uuml;bergeben wird, werden alle Werte geliefert.<br>
    </ul><br>

  <b>Beispiele:</b><br><br>
    <ul>
    <code>
      # Modul-Definition<br>
      define sysmon SYSMON 1 1 1 10<br>
      #attr sysmon event-on-update-reading cpu_temp,cpu_temp_avg,cpu_freq,eth0_diff,loadavg,ram,^~ /.*usb.*,~ /$<br>
      attr sysmon event-on-update-reading cpu_temp,cpu_temp_avg,cpu_freq,eth0_diff,loadavg,ram,fs_.*,stat_cpu_percent<br>
      attr sysmon filesystems fs_boot:/boot,fs_root:/:Root,fs_usb1:/media/usb1:USB-Stick<br>
      attr sysmon network-interfaces eth0:eth0:Ethernet,wlan0:wlan0:WiFi<br>
      attr sysmon group RPi<br>
      attr sysmon room 9.03_Tech<br>
      <br>
      # Log<br>
      define FileLog_sysmon FileLog ./log/sysmon-%Y-%m.log sysmon<br>
      attr FileLog_sysmon group RPi<br>
      attr FileLog_sysmon logtype SM_CPUTemp:Plot,text<br>
      attr FileLog_sysmon room 9.03_Tech<br>
      <br>
      # Visualisierung: CPU-Temperatur<br>
      define wl_sysmon_temp SVG FileLog_sysmon:SM_CPUTemp:CURRENT<br>
      attr wl_sysmon_temp group RPi<br>
      attr wl_sysmon_temp label "CPU Temperatur: Min $data{min2}, Max $data{max2}, Last $data{currval2}"<br>
      attr wl_sysmon_temp room 9.03_Tech<br>
      <br>
      # Visualisierung: Netzwerk-Daten&uuml;bertragung f&uuml;r eth0<br>
      define wl_sysmon_eth0 SVG FileLog_sysmon:SM_Network_eth0:CURRENT<br>
      attr wl_sysmon_eth0 group RPi<br>
      attr wl_sysmon_eth0 label "Netzwerk-Traffic eth0: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"<br>
      attr wl_sysmon_eth0 room 9.03_Tech<br>
      <br>
      # Visualisierung: Netzwerk-Daten&uuml;bertragung f&uuml;r wlan0<br>
      define wl_sysmon_wlan0 SVG FileLog_sysmon:SM_Network_wlan0:CURRENT<br>
      attr wl_sysmon_wlan0 group RPi<br>
      attr wl_sysmon_wlan0 label "Netzwerk-Traffic wlan0: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"<br>
      attr wl_sysmon_wlan0 room 9.03_Tech<br>
      <br>
      # Visualisierung: CPU-Auslastung (load average)<br>
      define wl_sysmon_load SVG FileLog_sysmon:SM_Load:CURRENT<br>
      attr wl_sysmon_load group RPi<br>
      attr wl_sysmon_load label "Load Min: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"<br>
      attr wl_sysmon_load room 9.03_Tech<br>
      <br>
      # Visualisierung: RAM-Nutzung<br>
      define wl_sysmon_ram SVG FileLog_sysmon:SM_RAM:CURRENT<br>
      attr wl_sysmon_ram group RPi<br>
      attr wl_sysmon_ram label "RAM-Nutzung Total: $data{max1}, Min: $data{min2}, Max: $data{max2}, Aktuell: $data{currval2}"<br>
      attr wl_sysmon_ram room 9.03_Tech<br>
      <br>
      # Visualisierung: Dateisystem: Root-Partition<br>
      define wl_sysmon_fs_root SVG FileLog_sysmon:SM_FS_root:CURRENT<br>
      attr wl_sysmon_fs_root group RPi<br>
      attr wl_sysmon_fs_root label "Root Partition Total: $data{max1}, Min: $data{min2}, Max: $data{max2}, Aktuell: $data{currval2}"<br>
      attr wl_sysmon_fs_root room 9.03_Tech<br>
      <br>
      # Visualisierung: Dateisystem: USB-Stick<br>
      define wl_sysmon_fs_usb1 SVG FileLog_sysmon:SM_FS_usb1:CURRENT<br>
      attr wl_sysmon_fs_usb1 group RPi<br>
      attr wl_sysmon_fs_usb1 label "USB1 Total: $data{max1}, Min: $data{min2}, Max: $data{max2}, Aktuell: $data{currval2}"<br>
      attr wl_sysmon_fs_usb1 room 9.03_Tech<br>
      <br>
      # Anzeige der Readings zum Einbinden in ein 'Raum'.<br>
      define SysValues weblink htmlCode {SYSMON_ShowValuesHTML('sysmon')}<br>
      attr SysValues group RPi<br>
      attr SysValues room 9.03_Tech<br>
      <br>
      # Anzeige CPU Auslasung<br>
      define wl_sysmon_cpustat SVG FileLog_sysmon:SM_CPUStat:CURRENT<br>
      attr wl_sysmon_cpustat label "CPU(min/max): user:$data{min1}/$data{max1} nice:$data{min2}/$data{max2} sys:$data{min3}/$data{max3} idle:$data{min4}/$data{max4} io:$data{min5}/$data{max5} irq:$data{min6}/$data{max6} sirq:$data{min7}/$data{max7}"<br>
      attr wl_sysmon_cpustat group RPi<br>
      attr wl_sysmon_cpustat room 9.99_Test<br>
      attr wl_sysmon_cpustat plotsize 840,420<br>
      define wl_sysmon_cpustat_s SVG FileLog_sysmon:SM_CPUStatSum:CURRENT<br>
      attr wl_sysmon_cpustat_s label "CPU(min/max): user:$data{min1}/$data{max1} nice:$data{min2}/$data{max2} sys:$data{min3}/$data{max3} idle:$data{min4}/$data{max4} io:$data{min5}/$data{max5} irq:$data{min6}/$data{max6} sirq:$data{min7}/$data{max7}"<br>
      attr wl_sysmon_cpustat_s group RPi<br>
      attr wl_sysmon_cpustat_s room 9.99_Test<br>
      attr wl_sysmon_cpustat_s plotsize 840,420<br>
      define wl_sysmon_cpustatT SVG FileLog_sysmon:SM_CPUStatTotal:CURRENT<br>
      attr wl_sysmon_cpustatT label "CPU-Auslastung"<br>
      attr wl_sysmon_cpustatT group RPi<br>
      attr wl_sysmon_cpustatT plotsize 840,420<br>
      attr wl_sysmon_cpustatT room 9.99_Test<br>
    </code>
    </ul>

  </ul>

=end html_DE
=cut
