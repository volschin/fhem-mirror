#############################################################
#
# EQ3BT.pm (c) by Dominik Karall, 2016
# dominik karall at gmail dot com
# $Id$
#
# FHEM module to communicate with EQ-3 Bluetooth thermostats
#
# Version: 1.1.2
#
#############################################################
#
# v1.1.2 - 20161108
# - FEATURE: support set <name> eco (eco temperature)
# - FEATURE: support set <name> comfort (comfort temperature)
# - CHANGE:  updated commandref
#
# v1.1.1 - 20161106
# - FEATURE: new reading consumption today/yesterday
# - FEATURE: new reading firmware which shows the current version
# - FEATURE: support set <name> mode automatic/manual
#
# v1.1.0 - 20161105
# - CHANGE:  code cleanup to make support of new functions easier
# - FEATURE: support boost on/off command
# - BUGFIX:  redirect stderr to stdout to avoid "Device or ressource busy"
#            and other error messages in the log output, only
#            if an action fails 20 times an error will be shown in the log
#
# v1.0.7 - 20161101
# - FEATURE: new reading consumption
#            calculation based on valvePosition and time (unit = %h)
# - FEATURE: new reading battery
# - FEATURE: new reading boost
# - FEATURE: new reading windowOpen
# - CHANGE:  change mode reading to Automatic/Manual only
# - FEATURE: new reading ecoMode (=holiday)
#
# v1.0.6 - 20161028
# - BUGFIX:  support temperature down to 4.5 (=OFF) degrees
#
# v1.0.5 - 20161027
# - BUGFIX:  fix wrong date/time after updateStatus again
#
# v1.0.4 - 20161025
# - BUGFIX:  remove unnecessary scan command on define
#
# v1.0.3 - 20161024
# - BUGFIX:  another fix for retry mechanism
# - BUGFIX:  wait before gatttool execution when
#            another gatttool/hcitool process is running
# - BUGFIX:  fix wrong date/time after updateStatus
#
# v1.0.2 - 20161020
# - FEATURE: automatically pair/trust device on define
# - FEATURE: add updateStatus method to update all values
# - BUGFIX:  fix retry mechanism for setDesiredTemperature
# - BUGFIX:  fix valvePosition value
# - BUGFIX:  fix uninitialized value error
# - BUGFIX:  RemoveTimer if set desired temp works again
# - BUGFIX:  set error reading to "" after it works again
# - BUGFIX:  disconnect device on define (startup)
#
# v1.0.1 - 20161016
# - FEATURE: read mode/desiredTemp/valvePos every 2 hours
#            might have impact on battery life!
# - CHANGED: temperature renamed to desiredTemperature
# - FEATURE: retry setTemperature 20 times if it fails
#
# v1.0.0 - 20161015
# - FEATURE: first public release
#
# NOTES
# command            dec
# DONE: boost mode command 69 00/01
# temperature offset 19 (x*2)+7
# request profile    32 01-07
# vacation mode      64 ...
# system info        00 => frameType=1,version=value[1],typeCode=value[2]
# window             20 t*2 time*5
# factory reset      -16
# DONE: comfort temp       67
# lock               -128 00/01
# DONE: mode               64 mode<<6
# DONE: temp               65 temp*2
# timer              3...
# start FW update    -96
# DONE: eco mode           68
# FW data            -95 ...
# profile set        16 ...
# set tempconf       17 comfort*2 eco*2
#
# TODOs
# - read/set eco/comfort temperature
# - read/set tempOffset
# - read/set windowOpen time settings
# - read/set profiles per day
#
#############################################################

package main;

use strict;
use warnings;

use Blocking;
use Encode;
use SetExtensions;

sub EQ3BT_Initialize($) {
    my ($hash) = @_;
    
    $hash->{DefFn}    = 'EQ3BT_Define';
    $hash->{UndefFn}  = 'EQ3BT_Undef';
    $hash->{GetFn}    = 'EQ3BT_Get';
    $hash->{SetFn}    = 'EQ3BT_Set';
    $hash->{AttrFn}   = 'EQ3BT_Attribute';
    
    return undef;
}

sub EQ3BT_Define($$) {
    #save BTMAC address
    my ($hash, $def) = @_;
    my @a = split("[ \t]+", $def);
    my $name = $a[0];
    my $mac;
    
    $hash->{STATE} = "initialized";
    
    if (int(@a) > 3) {
        return 'EQ3BT: Wrong syntax, must be define <name> EQ3BT <mac address>';
    } elsif(int(@a) == 3) {
        $mac = $a[2];
        $hash->{MAC} = $a[2];
    }
    
    $hash->{helper}{consumptionYesterday} = 0;
    
    BlockingCall("EQ3BT_pairDevice", $name."|".$hash->{MAC});
    
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+60, "EQ3BT_updateStatusWithTimer", $hash, 0);
    InternalTimer(gettimeofday()+20, "EQ3BT_updateSystemInformation", $hash, 0);
    
    return undef;
}

sub EQ3BT_pairDevice {
    my ($string) = @_;
    my ($name, $mac) = split("\\|", $string);

    qx(echo "pair $mac\\n";sleep 7;echo "trust $mac\\ndisconnect $mac\\n";sleep 2; echo "quit\\n" | bluetoothctl);

    return $name;
}

sub EQ3BT_Attribute($$$$) {
    my ($mode, $devName, $attrName, $attrValue) = @_;
    
    if($mode eq "set") {
        
    } elsif($mode eq "del") {
        
    }
    
    return undef;
}

sub EQ3BT_Set($@) {
    #set temperature/mode/...
    #BlockingCall for gatttool
    #handle result from BlockingCall in separate function and
    # write result into readings
    #
    my ($hash, $name, @params) = @_;
    my $workType = shift(@params);
    my $list = "desiredTemperature:slider,4.5,0.5,29.5,1 updateStatus:noArg boost:on,off mode:manual,automatic eco:noArg comfort:noArg";
    #my $list = "desiredTemperature:slider,5,0.5,30,1 boost daymode nightmode childlock holidaymode datetime window program";
    
    # check parameters for set function
    if($workType eq "?") {
        return SetExtensions($hash, $list, $name, $workType, @params);
    }

    if($workType eq "desiredTemperature") {
        return "EQ3BT: desiredTemperature requires <temperature> in celsius degrees as additional parameter" if(int(@params) < 1);
        return "EQ3BT: desiredTemperature supports temperatures from 4.5 - 29.5 degrees" if($params[0]<4.5 || $params[0]>29.5);
        EQ3BT_setDesiredTemperature($hash, $params[0]);
    } elsif($workType eq "updateStatus") {
        $hash->{helper}{retryUpdateStatusCounter} = 0;
        EQ3BT_updateStatus($hash, 1);
    } elsif($workType eq "boost") {
        return "EQ3BT: boost requires on/off as additional parameter" if(int(@params) < 1);
        EQ3BT_setBoost($hash, $params[0]);
    } elsif($workType eq "mode") {
        return "EQ3BT: mode requires automatic/manual as additional parameter" if(int(@params) < 1);
        EQ3BT_setMode($hash, $params[0]);
    } elsif($workType eq "eco") {
        EQ3BT_setEco($hash);
    } elsif($workType eq "comfort") {
        EQ3BT_setComfort($hash);
    } elsif($workType eq "childlock") {
        return "EQ3BT: childlock requires on/off as additional parameter" if(int(@params) < 1);
        EQ3BT_setChildlock($hash, $params[0]);
    } elsif($workType eq "holidaymode") {
        return "EQ3BT: holidaymode requires YYMMDDHHMM as additional parameter" if(int(@params) < 1);
        EQ3BT_setHolidaymode($hash, $params[0]);
    } elsif($workType eq "datetime") {
        return "EQ3BT: datetime requires YYMMDDHHMM as additional parameter" if(int(@params) < 1);
        EQ3BT_setDatetime($hash, $params[0]);
    } elsif($workType eq "window") {
        return "EQ3BT: windows requires open/closed as additional parameter" if(int(@params) < 1);
        EQ3BT_setWindow($hash, $params[0]);
    } elsif($workType eq "program") {
        return "EQ3BT: programming the device is not supported yet";
    } else {
        return SetExtensions($hash, $list, $name, $workType, @params);
    }
    
    return undef;
}

### updateSystemInformation ###
sub EQ3BT_updateSystemInformation {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    $hash->{helper}{RUNNING_PID} = BlockingCall("EQ3BT_execGatttool", $name."|".$hash->{MAC}."|updateSystemInformation|0x0411|00", "EQ3BT_processGatttoolResult", 300, "EQ3BT_killGatttool", $hash);
    
    InternalTimer(gettimeofday()+7200+int(rand(180)), "EQ3BT_updateSystemInformation", $hash, 0);
}

sub EQ3BT_updateSystemInformationSuccessful {
    my ($hash, $handle, $value) = @_;
    
    return undef;
}

sub EQ3BT_updateSystemInformationRetry {
    my ($hash) = @_;
    EQ3BT_retryGatttool($hash, "updateSystemInformation");
    return undef;
}

### updateStatus ###
sub EQ3BT_updateStatusWithTimer {
    my ($hash, $donotsettimer) = @_;
    my $name = $hash->{NAME};
    $hash->{helper}{RUNNING_PID} = BlockingCall("EQ3BT_execGatttool", $name."|".$hash->{MAC}."|updateStatus|0x0411|03|listen", "EQ3BT_processGatttoolResult", 300, "EQ3BT_killGatttool", $hash);
    
    InternalTimer(gettimeofday()+160+int(rand(20)), "EQ3BT_updateStatusWithTimer", $hash, 0);
}

sub EQ3BT_updateStatus {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    $hash->{helper}{RUNNING_PID} = BlockingCall("EQ3BT_execGatttool", $name."|".$hash->{MAC}."|updateStatus|0x0411|03|listen", "EQ3BT_processGatttoolResult", 300, "EQ3BT_killGatttool", $hash);
}

sub EQ3BT_updateStatusSuccessful {
    my ($hash, $handle, $value) = @_;
    
    return undef;
}

sub EQ3BT_updateStatusRetry {
    my ($hash) = @_;
    EQ3BT_retryGatttool($hash, "updateStatus");
    return undef;
}

### setDesiredTemperature ###
sub EQ3BT_setDesiredTemperature($$) {
    my ($hash, $desiredTemp) = @_;
    my $name = $hash->{NAME};
    
    my $eq3Temp = sprintf("%02X", $desiredTemp * 2);
    
    $hash->{helper}{RUNNING_PID} = BlockingCall("EQ3BT_execGatttool", $name."|".$hash->{MAC}."|setDesiredTemperature|0x0411|41".$eq3Temp, "EQ3BT_processGatttoolResult", 60, "EQ3BT_killGatttool", $hash);
    return undef;
}

sub EQ3BT_setDesiredTemperatureSuccessful {
    my ($hash, $handle, $tempVal) = @_;
    my $temp = (hex($tempVal) - 0x4100) / 2;
    readingsSingleUpdate($hash, "desiredTemperature", $temp, 1);
    return undef;
}

sub EQ3BT_setDesiredTemperatureRetry {
    my ($hash) = @_;
    EQ3BT_retryGatttool($hash, "setDesiredTemperature");
    return undef;
}

### setBoost ###
sub EQ3BT_setBoost {
    my ($hash, $onoff) = @_;
    my $name = $hash->{NAME};
    my $data = "01";
    $data = "00" if($onoff eq "off");
    
    $hash->{helper}{RUNNING_PID} = BlockingCall("EQ3BT_execGatttool", $name."|".$hash->{MAC}."|setBoost|0x0411|45".$data, "EQ3BT_processGatttoolResult", 60, "EQ3BT_killGatttool", $hash);
    return undef;
}

sub EQ3BT_setBoostSuccessful {
    my ($hash, $handle, $value) = @_;
    my $val = (hex($value) - 0x4500);
    readingsSingleUpdate($hash, "boost", $val, 1);
    return undef;
}

sub EQ3BT_setBoostRetry {
    my ($hash) = @_;
    EQ3BT_retryGatttool($hash, "setBoost");
    return undef;
}

### setMode ###
sub EQ3BT_setMode {
    my ($hash, $mode) = @_;
    my $name = $hash->{NAME};
    my $data = "40";
    $data = "00" if($mode eq "automatic");
    
    $hash->{helper}{RUNNING_PID} = BlockingCall("EQ3BT_execGatttool", $name."|".$hash->{MAC}."|setMode|0x0411|40".$data."|listen", "EQ3BT_processGatttoolResult", 60, "EQ3BT_killGatttool", $hash);
    return undef;
}

sub EQ3BT_setModeSuccessful {
    my ($hash, $handle, $value) = @_;
    
    return undef;
}

sub EQ3BT_setModeRetry {
    my ($hash) = @_;
    EQ3BT_retryGatttool($hash, "setMode");
    return undef;
}

### setEco ###
sub EQ3BT_setEco {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    $hash->{helper}{RUNNING_PID} = BlockingCall("EQ3BT_execGatttool", $name."|".$hash->{MAC}."|setEco|0x0411|44|listen", "EQ3BT_processGatttoolResult", 60, "EQ3BT_killGatttool", $hash);
    return undef;
}

sub EQ3BT_setEcoSuccessful {
    my ($hash, $handle, $value) = @_;
    
    return undef;
}

sub EQ3BT_setEcoRetry {
    my ($hash) = @_;
    EQ3BT_retryGatttool($hash, "setEco");
    return undef;
}

### setComfort ###
sub EQ3BT_setComfort {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    $hash->{helper}{RUNNING_PID} = BlockingCall("EQ3BT_execGatttool", $name."|".$hash->{MAC}."|setComfort|0x0411|43|listen", "EQ3BT_processGatttoolResult", 60, "EQ3BT_killGatttool", $hash);
    return undef;
}

sub EQ3BT_setComfortSuccessful {
    my ($hash, $handle, $value) = @_;
    
    return undef;
}

sub EQ3BT_setComfortRetry {
    my ($hash) = @_;
    EQ3BT_retryGatttool($hash, "setEco");
    return undef;
}

### Gatttool functions ###
sub EQ3BT_retryGatttool {
    my ($hash, $workType) = @_;
    $hash->{helper}{RUNNING_PID} = BlockingCall("EQ3BT_execGatttool", $hash->{NAME}."|".$hash->{MAC}."|$workType|".$hash->{helper}{"handle$workType"}."|".$hash->{helper}{"value$workType"}, "EQ3BT_processGatttoolResult", 60, "EQ3BT_killGatttool", $hash);
    return undef;
}

sub EQ3BT_execGatttool($) {
    my ($string) = @_;
    my ($name, $mac, $workType, $handle, $value, $listen) = split("\\|", $string);
    my $wait = 1;
    
    my $gatttool = qx(which gatttool);
    chomp $gatttool;
    
    if(-x $gatttool) {
        my $gtResult;

        while($wait) {
            my $grepGatttool = qx(ps ax| grep \'hcitool\\|gatttool\' | grep -v grep);
            if(not $grepGatttool =~ /^\s*$/) {
                #another gattool is running
                Log3 $name, 5, "EQ3BT ($name): another gatttool/hcitool process is running. waiting...";
                sleep(1);
            } else {
                $wait = 0;
            }
        }
        
        if($value eq "03") {
            my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
            my $currentDate = sprintf("%02X%02X%02X%02X%02X", $year+1900-2000, $mon+1, $mday, $hour, $min);
            $value .= $currentDate;
        }
        
        my $cmd = "gatttool -b $mac --char-write-req --handle=$handle --value=$value";
        if(defined($listen) && $listen eq "listen") {
            $cmd = "timeout 13 ".$cmd." --listen";
        }
        
        #redirect stderr to stdout
        $cmd .= " 2>&1";

        Log3 $name, 5, "EQ3BT ($name): $cmd";
        $gtResult = qx($cmd);
        chomp $gtResult;
        my @gtResultArr = split("\n", $gtResult);
        Log3 $name, 4, "EQ3BT ($name): gatttool result: ".join(",", @gtResultArr);
        if(defined($gtResultArr[0]) && $gtResultArr[0] eq "Characteristic value was written successfully") {
            #read notification
            if(defined($gtResultArr[1]) && $gtResultArr[1] =~ /Notification handle = 0x0421 value: (.*)/) {
                return "$name|$mac|ok|$workType|$handle|$value|$1";
            } else {
                return "$name|$mac|ok|$workType|$handle|$value";
            }
        } else {
            return "$name|$mac|error|$workType|$handle|$value|$workType failed";
        }
    } else {
        return "$name|$mac|error|$workType|$handle|$value|no gatttool binary found. Please check if bluez-package is properly installed";
    }
}

sub EQ3BT_processGatttoolResult($) {
    my ($string) = @_;
    
    return unless(defined($string));
    
    my @a = split("\\|", $string);
    my $name = $a[0];
    my $hash = $defs{$name};
    my $mac = $a[1];
    my $ret = $a[2];
    my $workType = $a[3];
    my $handle = $a[4];
    my $value = $a[5];
    my $notification = $a[6];
    
    Log3 $hash, 5, "EQ3BT ($name): gatttool return string: $string";
    
    $hash->{helper}{"handle$workType"} = $handle;
    $hash->{helper}{"value$workType"} = $value;
    
    if($ret eq "ok") {
        #process notification
        if(defined($notification)) {
            EQ3BT_processNotification($hash, $notification);
        }
        #call WorkTypeSuccessful function
        my $call = "EQ3BT_".$workType."Successful";
        #FIXME otherwise temperature is not set after successfull write
        no strict "refs";
        &{$call}($hash, $handle, $value);
        use strict "refs";
        RemoveInternalTimer($hash, "EQ3BT_".$workType."Retry");
        $hash->{helper}{"retryCounter$workType"} = 0;
        readingsSingleUpdate($hash, "error", "", 1);
    } else {
        $hash->{helper}{"retryCounter$workType"} = 0 if(!defined($hash->{helper}{"retryCounter$workType"}));
        $hash->{helper}{"retryCounter$workType"}++;
        Log3 $hash, 4, "EQ3BT ($name): $workType failed ($handle, $value, $notification)";
        if ($hash->{helper}{"retryCounter$workType"} > 20) {
            readingsSingleUpdate($hash, "error", "$workType, $value failed", 1);
            Log3 $hash, 3, "EQ3BT ($name): $workType, $handle, $value failed 20 times.";
            $hash->{helper}{"retryCounter$workType"} = 0;
        } else {
            InternalTimer(gettimeofday()+5, "EQ3BT_".$workType."Retry", $hash, 0);
        }
    }
    
    return undef;
}

sub EQ3BT_processNotification {
    my ($hash, $notification) = @_;
    my @vals = split(" ", $notification);
    
    my $frameType = $vals[0];
    
    if($frameType eq "01") {
        my $version = hex($vals[1]);
        my $typeCode = hex($vals[2]);
        readingsSingleUpdate($hash, "firmware", $version, 1);
        #readingsSingleUpdate($hash, "typeCode", $typeCode, 1);
    } elsif($frameType eq "02") {
        return undef if(!defined($vals[2]));
      
        #vals[2]
        my $mode = hex($vals[2]) & 1;
        my $modeStr = "Manual";
        if($mode == 0) {
            $modeStr = "Automatic";
        }
        my $eco  = (hex($vals[2]) & 2) >> 1;
        my $isBoost = (hex($vals[2]) & 4) >> 2;
        my $dst  = (hex($vals[2]) & 8) >> 3;
        my $wndOpen = (hex($vals[2]) & 16) >> 4;
        my $unknown = (hex($vals[2]) & 32) >> 5;
        $unknown = (hex($vals[2]) & 64) >> 6;
        my $isLowBattery = (hex($vals[2]) & 128) >> 7;
        my $batteryStr = "ok";
        if($isLowBattery > 0) {
            $batteryStr = "low";
        }

        #vals[3]
        my $pct  = hex($vals[3]);

        #vals[5]
        my $temp = hex($vals[5]) / 2;

        my $timeSinceLastChange = ReadingsAge($hash->{NAME}, "valvePosition", 0);
        my $consumption = ReadingsVal($hash->{NAME}, "consumption", 0);
        my $consumptionToday = ReadingsVal($hash->{NAME}, "consumptionToday", 0);
        my $oldVal = ReadingsVal($hash->{NAME}, "valvePosition", 0);
        my $consumptionDiff = 0;
        if($timeSinceLastChange < 300) {
            $consumptionDiff += ($oldVal + $pct) / 2 * $timeSinceLastChange / 3600;
        }
        
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
        if($yday ne $hash->{helper}{consumptionYesterday}) {
            $hash->{helper}{consumptionYesterday} = $yday;
            readingsSingleUpdate($hash, "consumptionYesterday", $consumptionToday, 1);
            readingsSingleUpdate($hash, "consumptionToday", 0, 1);
        } else {
            readingsSingleUpdate($hash, "consumptionToday", sprintf("%.3f", $consumptionToday+$consumptionDiff), 1);
        }

        readingsSingleUpdate($hash, "windowOpen", $wndOpen, 1);
        readingsSingleUpdate($hash, "ecoMode", $eco, 1);
        readingsSingleUpdate($hash, "battery", $batteryStr, 1);
        readingsSingleUpdate($hash, "boost", $isBoost, 1);
        readingsSingleUpdate($hash, "consumption", sprintf("%.3f", $consumption+$consumptionDiff), 1);
        readingsSingleUpdate($hash, "mode", $modeStr, 1);
        readingsSingleUpdate($hash, "valvePosition", $pct, 1);
        readingsSingleUpdate($hash, "desiredTemperature", $temp, 1);
    }
    
    return undef;
}

sub EQ3BT_killGatttool($) {

}

sub EQ3BT_setDaymode($) {
    my ($hash) = @_;
}

sub EQ3BT_setNightmode($) {
    my ($hash) = @_;
}

sub EQ3BT_setChildlock($$) {
    my ($hash, $desiredState) = @_;
}

sub EQ3BT_setHolidaymode($$) {
    my ($hash, $holidayEndTime) = @_;
}

sub EQ3BT_setDatetime($$) {
    my ($hash, $currentDatetime) = @_;
}

sub EQ3BT_setWindow($$) {
    my ($hash, $desiredState) = @_;
}

sub EQ3BT_setProgram($$) {
    my ($hash, $program) = @_;
}

sub EQ3BT_Undef($) {
    my ($hash) = @_;

    #remove internal timer
    RemoveInternalTimer($hash);

    return undef;
}

sub EQ3BT_Get($$) {
    return undef;
}

1;

=pod
=item device
=item summary Control EQ3 Bluetooth Smart Radiator Thermostat
=item summary_DE Steuerung des EQ3 Bluetooth Thermostats
=begin html

<a name="EQ3BT"></a>
<h3>EQ3BT</h3>
<ul>
  EQ3BT is used to control a EQ3 Bluetooth Smart Radiator Thermostat<br><br>
	<b>Note:</b> The bluez package is required to run this module. Please check if gatttool executable is available on your system.
		
  <br>
  <br>
  <a name="EQ3BTdefine" id="EQ3BTdefine"></a>
    <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EQ3BT &lt;mac address&gt;</code><br>
    <br>
    Example:
    <ul>
      <code>define livingroom.thermostat EQ3BT 00:33:44:33:22:11</code><br>
    </ul>
  </ul>
  
  <br>

  <a name="EQ3BTset" id="EQ3BTset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
               The following commands are defined:<br><br>
        <ul>
          <li><code><b>desiredTemperature</b> [4.5...29.5]</code> &nbsp;&nbsp;-&nbsp;&nbsp; set the temperature</li>
          <li><code><b>boost</b> on/off</code> &nbsp;&nbsp;-&nbsp;&nbsp; activate boost command</li>
          <li><code><b>mode</b> manual/automatic</code> &nbsp;&nbsp;-&nbsp;&nbsp; set manual/automatic mode</li>
          <li><code><b>updateStatus</b></code> &nbsp;&nbsp;-&nbsp;&nbsp; read current thermostat state and update readings</li>
          <li><code><b>eco</b> </code> &nbsp;&nbsp;-&nbsp;&nbsp; set eco temperature</li>
          <li><code><b>comfort</b> </code> &nbsp;&nbsp;-&nbsp;&nbsp; set comfort temperature</li>
        </ul>
    <br>
    </ul>
          
    <a name="EQ3BTget" id="EQ3BTget"></a>
  	<b>Get</b>
	  <ul>
	    <code>n/a</code>
 	 </ul>
 	 <br>

</ul>

=end html
=cut
