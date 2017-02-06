############################################################################
# $Id$
# fhem Modul f�r Impulsz�hler auf Basis von Arduino mit ArduCounter Sketch
#   
#     This file is part of fhem.
# 
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
# 
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#   Changelog:
#
#   2014-2-4    initial version
#   2014-3-12   added documentation
#   2015-02-08  renamed ACNT to ArduCounter
#   2016-01-01  added attributes for reading names
#   2016-10-15  fixed bug in handling Initialized / STATE
#               added attribute for individual factor for each pin
#   2016-10-29  added option to receive additional Message vom sketch and log it at level 4
#               added documentation, changed logging timestamp for power to begin of interval
#   2016-11-02  Attribute to control timestamp backdating
#   2016-11-04  allow number instead of rising etc. as change with min pulse length
#   2016-11-10  finish parsing new messages
#   2016-11-12  added attributes verboseReadings, readingStartTime
#               add readAnswer for get info
#   2016-12-13  better logging, ignore empty lines from Ardiuno
#               change to new communication syntax of sketch version 1.6
#   2016-12-24  add -b 57600 to flashCommand
#   2016-12-25  check for old firmware and log error, better logging, disable attribute
#   2017-01-01  improved logging
#   2017-01-02  modification for sketch 1.7, monitor clock drift difference between ardino and Fhem
#   2017-01-04  some more beatification in logging
#   2017-01-06  avoid reopening when disable=0 is set during startup

# ideas / todo:



package main;

use strict;                          
use warnings;                        
use Time::HiRes qw(gettimeofday);    

my %ArduCounter_sets = (  
    "raw"   =>  "",
    "reset"   =>  "",
    "flash" =>  ""
);

my %ArduCounter_gets = (  
    "info"  =>  ""
);

my $ArduCounter_Version = '4.5 - 6.1.2017';

#
# FHEM module intitialisation
# defines the functions to be called from FHEM
#########################################################################
sub ArduCounter_Initialize($)
{
    my ($hash) = @_;

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    $hash->{ReadFn}   = "ArduCounter_Read";
    $hash->{ReadyFn}  = "ArduCounter_Ready";
    $hash->{DefFn}    = "ArduCounter_Define";
    $hash->{UndefFn}  = "ArduCounter_Undef";
    $hash->{GetFn}    = "ArduCounter_Get";
    $hash->{SetFn}    = "ArduCounter_Set";
    $hash->{AttrFn}   = "ArduCounter_Attr";
    $hash->{NotifyFn} = "ArduCounter_Notify";
    $hash->{AttrList} =
        'pin.* ' .
        "interval " .
        "factor " .
        "readingNameCount[0-9]+ " .
        "readingNamePower[0-9]+ " .
        "readingFactor[0-9]+ " .
        "readingStartTime[0-9]+ " .
        "verboseReadings[0-9]+ " .
        "flashCommand " .
        "helloSendDelay " .
        "helloWaitTime " .
        "disable:0,1 " .
        "do_not_notify:1,0 " . 
        $readingFnAttributes;
}

#
# Define command
##########################################################################
sub ArduCounter_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split( "[ \t\n]+", $def );

    return "wrong syntax: define <name> ArduCounter devicename\@speed"
      if ( @a < 3 );

    DevIo_CloseDev($hash);
    my $name = $a[0];
    my $dev  = $a[2];
    
    $dev .= '@38400' if ($dev !~ /.+@[0-9]+/);
    $hash->{buffer}        = "";
    $hash->{DeviceName}    = $dev;
    $hash->{VersionModule} = $ArduCounter_Version;
    $hash->{NOTIFYDEV}     = "global";                  # NotifyFn nur aufrufen wenn global events (INITIALIZED)
    $hash->{STATE}         = "disconnected";
    
    delete $hash->{Initialized};
    
    if(!defined($attr{$name}{'flashCommand'})) {
        #$attr{$name}{'flashCommand'} = 'avrdude -p atmega328P -b 57600 -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]';
        $attr{$name}{'flashCommand'} = 'avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]';
    }
    return;
}


#
# Send config commands after Board reported it is ready or still counting
##########################################################################
sub ArduCounter_ConfigureDevice($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    # send attributes to arduino device. Just call ArduCounter_Attr again
    #Log3 $name, 3, "$name: sending configuration from attributes to device";
    while (my ($attr, $val) = each(%{$attr{$name}})) {
        if ($attr =~ "pin|interval") {
            Log3 $name, 3, "$name: ConfigureDevice calls Attr with $attr $val";
            ArduCounter_Attr("set", $name, $attr, $val); 
        }
    }
}


#
# undefine command when device is deleted
#########################################################################
sub ArduCounter_Undef($$)    
{                     
    my ( $hash, $arg ) = @_;       
    DevIo_CloseDev($hash);             
}    


########################################################
# Notify for INITIALIZED 
sub ArduCounter_Notify($$)
{
    my ($hash, $source) = @_;
    return if($source->{NAME} ne "global");

    my $events = deviceEvents($source, 1);
    return if(!$events);

    my $name = $hash->{NAME};
    # Log3 $name, 5, "$name: Notify called for source $source->{NAME} with events: @{$events}";
  
    return if (!grep(m/^INITIALIZED|REREADCFG|(MODIFIED $name)$/, @{$source->{CHANGED}}));

    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 4, "$name: device is disabled - don't set timer to send hello";
        return;
    }   

    Log3 $name, 5, "$name: Notify called with events: @{$events}, open device and set timer to send hello to device";
    DevIo_OpenDev( $hash, 0, 0);    

    my $now = gettimeofday();
    RemoveInternalTimer ("sendHello:$name");
    my $helloDelay = AttrVal($name, "helloSendDelay", 3);
    InternalTimer($now+$helloDelay, "ArduCounter_SendHello", "sendHello:$name", 0);
}


######################################
# wrapper for DevIo write
sub ArduCounter_Write ($$)
{
    my ($hash, $line) = @_;
    my $name = $hash->{NAME};
    if ($hash->{STATE} eq "disconnected" || !$hash->{FD}) {
        Log3 $name, 4, "$name: Write: device is disconnected, dropping line to write";
        return 0;
    } 
    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 4, "$name: Write called but device is disabled, dropping line to send";
        return 0;
    }   
    DevIo_SimpleWrite( $hash, "$line\n", 2);
    return 1;
}


#######################################
# Aufruf aus InternalTimer
sub ArduCounter_SendHello($)
{
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $hash = $defs{$name};
    my $now  = gettimeofday();
    
    Log3 $name, 3, "$name: sending h(ello) to device to ask for version";
    return if (!ArduCounter_Write( $hash, "h"));

    $hash->{WaitForHello} = 1;
    RemoveInternalTimer ("hwait:$name");
    my $helloWait= AttrVal($name, "helloWaitTime ", 3);
    InternalTimer($now+$helloWait, "ArduCounter_HelloTimeout", "hwait:$name", 0);
}


#######################################
# Aufruf aus InternalTimer
sub ArduCounter_HelloTimeout($)
{
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $hash = $defs{$name};
    Log3 $name, 3, "$name: device didn't reply to h(ello). Is the right sketch flashed?";
    delete $hash->{WaitForHello};
}


# Attr command 
#########################################################################
sub ArduCounter_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

    my $hash    = $defs{$name};
    my $modHash = $modules{$hash->{TYPE}};

    
    #Log3 $name, 5, "$name: Attr called with @_";
    if ($cmd eq "set") {
        if ($aName =~ 'pin.*') {
            if ($aName !~ 'pin[dD]?(\d+)') {
                Log3 $name, 3, "$name: Invalid pin name in attr $name $aName $aVal";
                return "Invalid pin name $aName";
            }
            my $pin = $1;
            if ($aVal =~ /^(rising|falling|change) ?(pullup)? ?([0-9]+)?/) {
                my $opt = "";
                if ($1 eq 'rising')       {$opt = "3"}
                elsif ($1 eq 'falling')   {$opt = "2"}
                elsif ($1 eq 'change')    {$opt = "1"}
                $opt .= ($2 ? ",1" : ",0");         # pullup
                $opt .= ($3 ? ",$3" : "");          # min length
                
                if ($hash->{Initialized}) {
                    ArduCounter_Write( $hash, "${pin},${opt}a");
                } else {
                    Log3 $name, 5, "$name: communication postponed until device is initialized";
                }
                  
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }
        } elsif ($aName eq "interval") {
            if ($aVal =~ '^(\d+) (\d+) ?(\d+)? ?(\d+)?$') {
                my $min = $1;
                my $max = $2;
                my $sml = $3;
                my $cnt = $4;
                if ($min < 1 || $min > 3600 || $max < $min || $max > 3600) {
                    Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                    return "Invalid Value $aVal";
                }
                if ($hash->{Initialized}) {
                    $sml = 0 if (!$sml);
                    $cnt = 0 if (!$cnt);
                    ArduCounter_Write($hash, "${min},${max},${sml},${cnt}i");
                } else {
                    Log3 $name, 5, "$name: communication postponed until device is initialized";
                }
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }           
        } elsif ($aName eq "factor") {
            if ($aVal =~ '^(\d+)$') {
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }           
        } elsif ($aName eq 'disable') {
            if ($aVal) {
                Log3 $name, 5, "$name: disable attribute set";
                DevIo_CloseDev($hash);
                return;
            } else {
                Log3 $name, 3, "$name: disable attribute cleared";
                DevIo_OpenDev( $hash, 0, 0) if ($hash->{Initialized});
                my $now = gettimeofday();
                RemoveInternalTimer ("sendHello:$name");
                my $helloDelay = AttrVal($name, "helloSendDelay", 1);
                InternalTimer($now+$helloDelay, "ArduCounter_SendHello", "sendHello:$name", 0);
            }
        }       
        
        # handle wild card attributes -> Add to userattr to allow modification in fhemweb
        #Log3 $name, 3, "$name: attribute $aName checking ";
        if (" $modHash->{AttrList} " !~ m/ ${aName}[ :;]/) {
            # nicht direkt in der Liste -> evt. wildcard attr in AttrList
            foreach my $la (split " ", $modHash->{AttrList}) {
                $la =~ /([^:;]+)(:?.*)/;
                my $vgl = $1;           # attribute name in list - probably a regex
                my $opt = $2;           # attribute hint in list
                if ($aName =~ $vgl) {   # yes - the name in the list now matches as regex
                    # $aName ist eine Auspr�gung eines wildcard attrs
                    addToDevAttrList($name, "$aName" . $opt);    # create userattr with hint to allow changing by click in fhemweb
                    if ($opt) {
                        # remove old entries without hint
                        my $ualist = $attr{$name}{userattr};
                        $ualist = "" if(!$ualist);  
                        my %uahash;
                        foreach my $a (split(" ", $ualist)) {
                            if ($a !~ /^${aName}$/) {    # entry in userattr list is attribute without hint
                                $uahash{$a} = 1;
                            } else {
                                Log3 $name, 3, "$name: added hint $opt to attr $a in userattr list";
                            }
                        }
                        $attr{$name}{userattr} = join(" ", sort keys %uahash);
                    }
                }
            }
        } else {
            # exakt in Liste enthalten -> sicherstellen, dass keine +* etc. drin sind.
            if ($aName =~ /\|\*\+\[/) {
                Log3 $name, 3, "$name: Atribute $aName is not valid. It still contains wildcard symbols";
                return "$name: Atribute $aName is not valid. It still contains wildcard symbols";
            }
        }
        
    } elsif ($cmd eq "del") {
        if ($aName =~ 'pin.*') {
            if ($aName !~ 'pin([dD]?\d+)') {
                Log3 $name, 3, "$name: Invalid pin name in attr $name $aName $aVal";
                return "Invalid pin name $aName";
            }
            my $pin = $1;
            # this cannot come from fhem.cfg and waiting for initialized doesnt help so send it
            ArduCounter_Write( $hash, "${pin}d");

        } elsif ($aName eq 'disable') {
            Log3 $name, 3, "$name: disable attribute removed";                      
            DevIo_OpenDev( $hash, 0, 0) if ($hash->{Initialized});
            my $now = gettimeofday();
            RemoveInternalTimer ("sendHello:$name");
            my $helloDelay = AttrVal($name, "helloSendDelay", 1);
            InternalTimer($now+$helloDelay, "ArduCounter_SendHello", "sendHello:$name", 0);
        }
    }
    return undef;
}


# SET command
#########################################################################
sub ArduCounter_Set($@)
{
    my ( $hash, @a ) = @_;
    return "\"set ArduCounter\" needs at least one argument" if ( @a < 2 );
    
    # @a is an array with DeviceName, SetName, Rest of Set Line
    my $name = shift @a;
    my $attr = shift @a;
    my $arg = join(" ", @a);

    if(!defined($ArduCounter_sets{$attr})) {
        my @cList = keys %ArduCounter_sets;
        return "Unknown argument $attr, choose one of " . join(" ", @cList);
    } 

    if(!$hash->{FD}) {
        Log3 $name, 4, "$name: Set called but device is disconnected";
        return ("Set called but device is disconnected", undef);
    }
    
    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 4, "$name: set called but device is disabled";
        return;
    }   

    
    if ($attr eq "raw") {
        ArduCounter_Write($hash, "$arg");
        
    } elsif ($attr eq "reset") {
        DevIo_CloseDev($hash);
        $hash->{buffer} = "";       
        DevIo_OpenDev( $hash, 0, 0);
        if (ArduCounter_Write($hash, "r")) {
            delete $hash->{Initialized};
            return "sent (r)eset command to device - waiting for its setup message";
        }
       
    } elsif ($attr eq "flash") {
        my @args = split(' ', $arg);
        my $log = "";   
        my @deviceName = split('@', $hash->{DeviceName});
        my $port = $deviceName[0];
        my $firmwareFolder = "./FHEM/firmware/";
        my $logFile = AttrVal("global", "logdir", "./log") . "/ArduCounterFlash.log";
        my $hexFile = $firmwareFolder . "ArduCounter.hex";

        return "The file '$hexFile' does not exist" if(!-e $hexFile);

        Log3 $name, 4, "$name: Flashing Aduino at $port with $hexFile. See $logFile for details";
        
        $log .= "flashing device as ArduCounter for $name\n";
        $log .= "hex file: $hexFile\n";

        $log .= "port: $port\n";
        $log .= "log file: $logFile\n";

        my $flashCommand = AttrVal($name, "flashCommand", "");

        if($flashCommand ne "") {
            if (-e $logFile) {
              unlink $logFile;
            }

            DevIo_CloseDev($hash);
            readingsSingleUpdate($hash, "state", "disconnected", 1);
            $log .= "$name closed\n";

            my $avrdude = $flashCommand;
            $avrdude =~ s/\Q[PORT]\E/$port/g;
            $avrdude =~ s/\Q[HEXFILE]\E/$hexFile/g;
            $avrdude =~ s/\Q[LOGFILE]\E/$logFile/g;

            $log .= "command: $avrdude\n\n";
            `$avrdude`;

            local $/=undef;
            if (-e $logFile) {
                open FILE, $logFile;
                my $logText = <FILE>;
                close FILE;
                $log .= "--- AVRDUDE ---------------------------------------------------------------------------------\n";
                $log .= $logText;
                $log .= "--- AVRDUDE ---------------------------------------------------------------------------------\n\n";
            }
            else {
                $log .= "WARNING: avrdude created no log file\n\n";
            }
            DevIo_OpenDev($hash, 0, 0);
            $log .= "$name opened\n";
        }
        return $log;
    }
    return undef;
}


# GET command
#########################################################################
sub ArduCounter_Get($@)
{
    my ( $hash, @a ) = @_;
    return "\"set ArduCounter\" needs at least one argument" if ( @a < 2 );    
    my $name = shift @a;
    my $attr = shift @a;

    if(!defined($ArduCounter_gets{$attr})) {
        my @cList = keys %ArduCounter_gets;
        return "Unknown argument $attr, choose one of " . join(" ", @cList);
    } 

    if(!$hash->{FD}) {
        Log3 $name, 4, "$name: Get called but device is disconnected";
        return ("Get called but device is disconnected", undef);
    }

    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 4, "$name: get called but device is disabled";
        return;
    }   
    
    if ($attr eq "info") {
        Log3 $name, 3, "$name: Sending info command to device";
        ArduCounter_Write( $hash, "s");
        my ($err, $msg) = ArduCounter_ReadAnswer($hash, 'Next report in [0-9]+ Milliseconds');
        # todo: test adding \n to regex to make sure we got the whole respose string
        
        return ($err ? $err : $msg);
    }
        
    return undef;
}


######################################
sub ArduCounter_HandleVersion($$)
{
    my ($hash, $line) = @_;
    my $name = $hash->{NAME};
    if ($line =~ / V([\d\.]+)/) {
        my $version = $1;
        if ($version < "1.7") {
            $version .= " - not compatible with this Module version - please flash new sketch";
            Log3 $name, 3, "$name: device reported outdated Arducounter Firmware - please update!";
        }
        $hash->{VersionFirmware} = $version;
        Log3 $name, 4, "$name: device reported firmware $version";
    }
}


#########################################################################
sub ArduCounter_Parse($)
{
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $retStr = "";
    
    my @lines = split /\n/, $hash->{buffer};
    foreach my $line (@lines) {
        # Log3 $name, 5, "$name: Parse line: $line";
        if ($line =~ 'R([\d]+) C([\d]+) D([\d]+) T([\d]+)( N[\d]+)?( X[\d]+)?( F[\d]+)?(L [\d]+)?( A[\d]+)?')
        {
            my $pin    = $1;
            my $count  = $2;
            my $diff   = $3;
            my $time   = $4;
            my $deTime = ($5 ? substr($5, 2) / 1000 : "");
            my $reject = ($6 ? substr($6, 2) : "");
            my $first  = ($7 ? substr($7, 2) : "");
            my $last   = ($8 ? substr($8, 2) : "");
            my $avgLen = ($9 ? substr($9, 2) : "");
            
            my $factor = AttrVal($name, "readingFactor$pin", AttrVal($name, "factor", 1000));
            my $rcname = AttrVal($name, "readingNameCount$pin", "pin$pin");
            my $rpname = AttrVal($name, "readingNamePower$pin", "power$pin");
            my $lName  = AttrVal($name, "readingNamePower$pin", AttrVal($name, "readingNameCount$pin", "pin$pin"));
            
            my $chIdx  = 0;         
            my $now    = gettimeofday();
            my $sTime  = $now - $time/1000;   # start of observation interval (~first pulse)
            my $fSTime = FmtDateTime($sTime); # formatted
            my $fSdTim = FmtTime($sTime);     # only time formatted 
            
            my $eTime  = $now;                # now / end of observation interval
            my $fETime = FmtDateTime($eTime); # formatted
            my $fEdTim = FmtTime($eTime);     # only time formatted 
            my $power  = sprintf ("%.3f", ($time ? $diff/$time/1000*3600*$factor : 0));

            
            Log3 $name, 4, "$name: Pin $pin ($lName) count $count (diff $diff) in " .
                sprintf("%.3f", $time/1000) . "s" .
                ((defined($reject) && $reject ne "") ? ", reject $reject" : "") .
                ($avgLen ? ", Avg Len ${avgLen}ms" : "") .
                ", result $power";
            Log3 $name, 5, "$name: interval $fSdTim until $fEdTim" .
                ($first ? ", First at $first" : "") .
                ($last ? ", Last at $last" : "");

            
            readingsBeginUpdate($hash);            
            if (AttrVal($name, "readingStartTime$pin", 0)) {
                $hash->{".updateTime"}      = $sTime;
                $hash->{".updateTimestamp"} = $fSTime;
                Log3 $name, 5, "$name: readingStartTime$pin specified: setting reading timestamp to $fSdTim";
                Log3 $name, 5, "$name: set readings $rpname to $power, timeDiff$pin to $time and countDiff$pin to $diff";
                readingsBulkUpdate($hash, $rpname, $power) if ($time);
                $hash->{CHANGETIME}[$chIdx++] = $fSTime;                        # Intervall start
                $hash->{".updateTime"}      = $eTime;
                $hash->{".updateTimestamp"} = $fETime;

                readingsBulkUpdate($hash, $rcname, $count);
                $hash->{CHANGETIME}[$chIdx++] = $fETime;          
                
                if (AttrVal($name, "verboseReadings$pin", 0)) {
                    readingsBulkUpdate($hash, "timeDiff$pin", $time);
                    $hash->{CHANGETIME}[$chIdx++] = $fETime;
                    readingsBulkUpdate($hash, "countDiff$pin", $diff);
                    $hash->{CHANGETIME}[$chIdx++] = $fETime;
                    readingsBulkUpdate($hash, "lastMsg$pin", $line);
                    $hash->{CHANGETIME}[$chIdx++] = $fETime;
                    if (defined($reject)) {
                        readingsBulkUpdate($hash, "reject$pin", $reject);
                        $hash->{CHANGETIME}[$chIdx++] = $fETime;                  
                    }
                }
            } else {
                Log3 $name, 5, "$name: set readings $rpname to $power, timeDiff$pin to $time and countDiff$pin to $diff";
                readingsBulkUpdate($hash, $rpname, $power) if ($time);
                $eTime = time_str2num(ReadingsTimestamp ($name, $rpname, 0));
                readingsBulkUpdate($hash, $rcname, $count);
                if (AttrVal($name, "verboseReadings$pin", 0)) {
                    readingsBulkUpdate($hash, "timeDiff$pin", $time);
                    readingsBulkUpdate($hash, "countDiff$pin", $diff);
                    readingsBulkUpdate($hash, "lastMsg$pin", $line);        
                    if (defined($reject)) {
                        readingsBulkUpdate($hash, "reject$pin", $reject);
                    }
                }
            }
            readingsEndUpdate($hash, 1);

            if ($deTime) {
                if (defined ($hash->{'.DeTOff'}) && $hash->{'.LastDeT'}) {
                    if ($deTime >= $hash->{'.LastDeT'}) {
                        $hash->{'.Drift2'} = ($now - $hash->{'.DeTOff'}) - $deTime;
                    } else {
                        $hash->{'.DeTOff'}  = $now - $deTime;
                        Log3 $name, 5, "$name: device clock wrapped (now $deTime, before $hash->{'.LastDeT'}). New offset is $hash->{'.DeTOff'}";
                    }
                } else {
                    $hash->{'.DeTOff'}  = $now - $deTime;
                    $hash->{'.Drift2'}  = 0;
                    $hash->{'.DriftStart'}  = $now;
                    Log3 $name, 5, "$name: Initialize clock offset to $hash->{'.DeTOff'}";
                }
                $hash->{'.LastDeT'} = $deTime;  
            }

            my $drTime = ($now - $hash->{'.DriftStart'});
            Log3 $name, 5, "$name: Device Time $deTime" .
                #", Offset " . sprintf("%.3f", $hash->{'.DeTOff'}/1000) . 
                ", Drift "  . sprintf("%.3f", $hash->{'.Drift2'}) .
                "s in " . sprintf("%.3f", $drTime) . "s" .
                ($drTime > 0 ? ", " . sprintf("%.2f", $hash->{'.Drift2'} / $drTime * 100) . "%" : "");
                
            if (!$hash->{Initialized}) {
                Log3 $name, 3, "$name: device reported count";
                if (!$hash->{WaitForHello}) {
                    ArduCounter_SendHello("direct:$name");
                }
                $hash->{Initialized} = 1;
                RemoveInternalTimer ("sendHello:$name");
            }
            
        } elsif ($line =~ /ArduCounter V([\d\.]+).?Hello/) {        # response to h(ello)
            Log3 $name, 3, "$name: device replied to hello, V$1";
            ArduCounter_HandleVersion($hash, $line);
            $hash->{Initialized} = 1;
            ArduCounter_ConfigureDevice($hash) if ($hash->{WaitForHello});
            
            delete $hash->{WaitForHello};
            RemoveInternalTimer ("hwait:$name");
            RemoveInternalTimer ("sendHello:$name");
            
        } elsif ($line =~ /Status: ArduCounter V([\d\.]+)/) {       # response to s(how)
            $retStr .= "\n" if ($retStr);
            $retStr .= $line;
            ArduCounter_HandleVersion($hash, $line);
            
            #todo: remove here?
            delete $hash->{WaitForHello};
            RemoveInternalTimer ("hwait:$name");        # dont wait for hello reply if already sent
            RemoveInternalTimer ("sendHello:$name");    # Hello not needed anymore if not sent yet
            
            
        } elsif ($line =~ /ArduCounter V([\d\.]+).?Started/) {      # setup message
            Log3 $name, 3, "$name: device sent setup message, V$1";
            ArduCounter_HandleVersion($hash, $line);
            $hash->{Initialized} = 1;
            ArduCounter_ConfigureDevice($hash);
            
            delete $hash->{WaitForHello};
            RemoveInternalTimer ("hwait:$name");        # dont wait for hello reply if already sent
            RemoveInternalTimer ("sendHello:$name");    # Hello not needed anymore if not sent yet
         
        } elsif ($line =~ /V([\d\.]+).?Setup done/) {      # old setup message 
            Log3 $name, 3, "$name: device is flashed with an old and incompatible firmware : $1";
            Log3 $name, 3, "$name: please use set $name flash to update";
            ArduCounter_HandleVersion($hash, $line);
            
        } elsif ($line =~ /^M (.*)/) {
            $retStr .= "\n" if ($retStr);
            $retStr .= $1;
            Log3 $name, 3, "$name: device: $1";
        } elsif ($line =~ /^[\s\n]*$/) {
            # blank line - ignore
        } else {
            Log3 $name, 3, "$name: unparseable message from device: $line";
        }
    }
    $hash->{buffer} = "";
    return $retStr;
}



#########################################################################
# called from the global loop, when the select for hash->{FD} reports data
sub ArduCounter_Read($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my ($pin, $count, $diff, $power, $time, $reject, $msg);
    
    # read from serial device
    my $buf = DevIo_SimpleRead($hash);      
    return if (!defined($buf) );

    $hash->{buffer} .= $buf;    
    my $end = chop $buf;
    #Log3 $name, 5, "$name: Read: current buffer content: " . $hash->{buffer};

    # did we already get a full frame?
    return if ($end ne "\n");   
    ArduCounter_Parse($hash);
}



#####################################
# Called from get / set to get a direct answer
# called with logical device hash
sub
ArduCounter_ReadAnswer($$)
{
    my ($hash, $expect) = @_;
    my $name   = $hash->{NAME};
    my $rin    = '';
    my $msgBuf = '';
    my $to     = AttrVal($name, "timeout", 2);
    my $buf;

    Log3 $name, 5, "$name: ReadAnswer called";  
    
    for(;;) {

        if($^O =~ m/Win/ && $hash->{USBDev}) {        
            $hash->{USBDev}->read_const_time($to*1000);   # set timeout (ms)
            $buf = $hash->{USBDev}->read(999);
            if(length($buf) == 0) {
                Log3 $name, 3, "$name: Timeout in ReadAnswer";
                return ("Timeout reading answer", undef)
            }
        } else {
            if(!$hash->{FD}) {
                Log3 $name, 3, "$name: Device lost in ReadAnswer";
                return ("Device lost when reading answer", undef);
            }

            vec($rin, $hash->{FD}, 1) = 1;    # setze entsprechendes Bit in rin
            my $nfound = select($rin, undef, undef, $to);
            if($nfound < 0) {
                next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
                my $err = $!;
                DevIo_Disconnected($hash);
                Log3 $name, 3, "$name: ReadAnswer error: $err";
                return("ReadAnswer error: $err", undef);
            }
            if($nfound == 0) {
                Log3 $name, 3, "$name: Timeout2 in ReadAnswer";
                return ("Timeout reading answer", undef);
            }

            $buf = DevIo_SimpleRead($hash);
            if(!defined($buf)) {
                Log3 $name, 3, "$name: ReadAnswer got no data";
                return ("No data", undef);
            }
        }

        if($buf) {
            #Log3 $name, 5, "$name: ReadAnswer got: $buf";
            $hash->{buffer} .= $buf;
        }
        
        my $end = chop $buf;
        #Log3 $name, 5, "$name: Current buffer content: " . $hash->{buffer};
        next if ($end ne "\n"); 


        $msgBuf .= "\n" if ($msgBuf);
        $msgBuf .= ArduCounter_Parse($hash);
        
        #Log3 $name, 5, "$name: ReadAnswer msgBuf: " . $msgBuf;
        if ($msgBuf =~ $expect) {
            Log3 $name, 5, "$name: ReadAnswer matched $expect";
            return (undef, $msgBuf);
        }
    }
    return ("no Data", undef);
}



#
# copied from other FHEM modules
#########################################################################
sub ArduCounter_Ready($)
{
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    
    if (AttrVal($name, "disable", undef)) {
        return;
    }   
    
    # try to reopen if state is disconnected  
    if ( $hash->{STATE} eq "disconnected" ) {
        #Log3 $name, 3, "$name: ReadyFN tries to open";     # debug
        DevIo_OpenDev( $hash, 1, undef );
        if ($hash->{FD} && !$hash->{Initialized}) {
            Log3 $name, 3, "$name: device not initialized yet, set timer to send h(ello";
            my $now = gettimeofday();
            RemoveInternalTimer ("sendHello:$name");
            my $helloDelay = AttrVal($name, "helloSendDelay", 3);
            InternalTimer($now+$helloDelay, "ArduCounter_SendHello", "sendHello:$name", 0);
        }
        return;
    }
      
    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    if ($po) {
        my ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags ) = $po->status;
        return ( $InBytes > 0 );
    }
}


1;


=pod
=item device
=item summary Module for consumption counter based on an arduino with the ArduCounter sketch
=item summary_DE Modul f�r Strom / Wasserz�hler auf Arduino-Basis mit ArduCounter Sketch
=begin html

<a name="ArduCounter"></a>
<h3>ArduCounter</h3>

<ul>
    This module implements an Interface to an Arduino based counter for pulses on any input pin of an Arduino Uno, Nano or similar device like a Jeenode. The typical use case is an S0-Interface on an energy meter<br>
    Counters are configured with attributes that define which Arduino pins should count pulses and in which intervals the Arduino board should report the current counts.<br>
    The Arduino sketch that works with this module uses pin change interrupts so it can efficiently count pulses on all available input pins.
    <br><br>
    <b>Prerequisites</b>
    <ul>
        <br>
        <li>
            This module requires an Arduino uno, nano, Jeenode or similar device running the ArduCounter sketch provided with this module
        </li>
    </ul>
    <br>

    <a name="ArduCounterdefine"></a>
    <b>Define</b>
    <ul>
        <br>
        <code>define &lt;name&gt; ArduCounter &lt;device&gt;</code>
        <br>
        &lt;device&gt; specifies the serial port to communicate with the Arduino.<br>
        
        The name of the serial-device depends on your distribution.
        You can also specify a baudrate if the device name contains the @
        character, e.g.: /dev/ttyUSB0@38400<br>
        The default baudrate of the ArduCounter firmware is 38400 since Version 1.4
        <br>
        Example:<br>
        <br>
        <ul><code>define AC ArduCounter /dev/ttyUSB2@38400</code></ul>
    </ul>
    <br>

    <a name="ArduCounterconfiguration"></a>
    <b>Configuration of ArduCounter counters</b><br><br>
    <ul>
        Specify the pins where impulses should be counted e.g. as <code>attr AC pinX falling pullup 30</code> <br>
        The X in pinX can be an Arduino pin number with or without the letter D e.g. pin4, pinD5, pin6, pinD7 ...<br>
        After the pin you can define if rising or falling edges of the signals should be counted. The optional keyword pullup activates the pullup resistor for the given Arduino Pin.
        The last argument is also optional and specifies a minimal pulse length in milliseconds. In this case the first argument (e.g. falling) means that an impulse starts with a falling edge from 1 to 0 and ends when the signal changes back from 0 to 1.
        <br><br>
        Example:<br>
        <pre>
        define AC ArduCounter /dev/ttyUSB2
        attr AC factor 1000
        attr AC interval 60 300
        attr AC pinD4 falling pullup
        attr AC pinD5 falling pullup 30
        attr AC pinD6 rising
        </pre>
        this defines three counters connected to the pins D4, D5 and D5. <br>
        D4 and D5 have their pullup resistors activated and the impulse draws the pins to zero.  <br>
        For D4 every falling edge of the signal (when the input changes from 1 to 0) is counted.<br>
        For D5 the arduino measures the time in milliseconds between the falling edge and the rising edge. If this time is longer than the specified 30 milliseconds then the impulse is counted. If the time is shorter then this impulse is regarded as noise and added to a separate reject counter.<br>
        For pin D6 the ardiono counts every time when the signal changes from 0 to 1. <br>
        The ArduCounter sketch which must be loaded on the Arduino implements this using pin change interrupts,
        so all avilable input pins can be used, not only the ones that support normal interrupts.
    </ul>
    <br>

    <a name="ArduCounterset"></a>
    <b>Set-Commands</b><br>
    <ul>
        <li><b>raw</b></li> 
            send the value to the Arduino board so you can directly talk to the sketch using its commands.<br>
            This is not needed for normal operation but might be useful sometimes for debugging<br>
        <li><b>flash</b></li> 
            flashes the ArduCounter firmware ArduCounter.hex from the fhem subdirectory FHEM/firmware
            onto the device. This command needs avrdude to be installed. The attribute flashCommand specidies how avrdude is called. If it is not modifed then the module sets it to avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]<br>
            This setting should work for a standard installation and the placeholders are automatically replaced when 
            the command is used. So normally there is no need to modify this attribute.<br>
            Depending on your specific Arduino board however, you might need to insert <code>-b 57600</code> in the flash Command.<br>
            <br>
        <li><b>reset</b></li> 
            reopens the arduino device and sends a command to it which causes a reinitialize and reset of the counters. Then the module resends the attribute configuration / definition of the pins to the device.
    </ul>
    <br>
    <a name="ArduCounterget"></a>
    <b>Get-Commands</b><br>
    <ul>
        <li><b>info</b></li> 
            send a command to the Arduino board to get current counts.<br>
            This is not needed for normal operation but might be useful sometimes for debugging<br>
    </ul>
    <br>
    <a name="ArduCounterattr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
        <li><b>pin.*</b></li> 
            Define a pin of the Arduino board as input. This attribute expects either 
            <code>rising</code>, <code>falling</code> or <code>change</code>, followed by an optional <code>pullup</code> and an optional number as value.<br>
            If a number is specified, the arduino will track rising and falling edges of each impulse and measure the length of a pulse in milliseconds. The number specified here is the minimal length of a pulse and a pause before a pulse. If one is too small, the pulse is not counted but added to a separate reject counter.
        <li><b>interval</b> normal max min mincout</li> 
            Defines the parameters that affect the way counting and reporting works.
            This Attribute expects at least two and a maximum of four numbers as value. The first is the normal interval, the second the maximal interval, the third is a minimal interval and the fourth is a minimal pulse count.

            In the usual operation mode (when the normal interval is smaller than the maximum interval),
            the Arduino board just counts and remembers the time between the first impulse and the last impulse for each pin.<br>
            After the normal interval is elapsed the Arduino board reports the count and time for those pins where impulses were encountered.<br>
            This means that even though the normal interval might be 10 seconds, the reported time difference can be 
            something different because it observed impulses as starting and ending point.<br>
            The Power (e.g. for energy meters) is the calculated based of the counted impulses and the time between the first and the last impulse. <br>
            For the next interval, the starting time will be the time of the last impulse in the previous 
            reporting period and the time difference will be taken up to the last impulse before the reporting
            interval has elapsed.
            <br><br>
            The second, third and fourth numbers (maximum, minimal interval and minimal count) exist for the special case when the pulse frequency is very low and the reporting time is comparatively short.<br>
            For example if the normal interval (first number) is 60 seconds and the device counts only one impulse in 90 seconds, the the calculated power reading will jump up and down and will give ugly numbers.
            By adjusting the other numbers of this attribute this can be avoided.<br>
            In case in the normal interval the observed impulses are encountered in a time difference that is smaller than the third number (minimal interval) or if the number of impulses counted is smaller than the 
            fourth number (minimal count) then the reporting is delayed until the maximum interval has elapsed or the above conditions have changed after another normal interval.<br>
            This way the counter will report a higher number of pulses counted and a larger time difference back to fhem.
            <br><br>
            If this is seems too complicated and you prefer a simple and constant reporting interval, then you can set the normal interval and the mximum interval to the same number. This changes the operation mode of the counter to just count during this normal and maximum interval and report the count. In this case the reported time difference is always the reporting interval and not the measured time between the real impulses.
        <li><b>factor</b></li> 
            Define a multiplicator for calculating the power from the impulse count and the time between the first and the last impulse
            
        <li><b>readingNameCount[0-9]+</b></li> 
            Change the name of the counter reading pinX to something more meaningful.
        <li><b>readingNamePower[0-9]+</b></li> 
            Change the name of the power reading powerX to something more meaningful.
        <li><b>readingFactor[0-9]+</b></li> 
            Override the factor attribute for this individual pin.
        <li><b>readingStartTime[0-9]+</b></li> 
            Allow the reading time stamp to be set to the beginning of measuring intervals
        <li><b>verboseReadings[0-9]+</b></li> 
            create readings timeDiff, countDiff and lastMsg for each pin
    </ul>
    <br>
    <b>Readings / Events</b><br>
    <ul>
        The module creates at least the following readings and events for each defined pin:
        <li><b>pin.*</b></li> 
            the current count at this pin
        <li><b>power.*</b></li> 
            the current calculated power at this pin
		Most reading names can be customized with attribues and many more readings can be generated by setting the attribute verboseReadings[0-9]+ to 1.
    </ul>
    <br>
</ul>

=end html
=cut

