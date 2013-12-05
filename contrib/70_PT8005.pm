########################################################################################
#
# PT8005.pm
#
# FHEM module to read the data from a PeakTech PT8005 sound level meter
#
# Prof. Dr. Peter A. Henning, 2013
# 
# Version 1.0 - December 2013
#
# Setup as:
# define  <name> PT8005 <device>
#    
# where <name> may be replaced by any name string and <device> 
# is a serial (USB) device or the keyword "emulator".
# In the latter case, a 4.5 kWP solar installation is simulated
#
# get <name> present     => 1 if device present, 0 if not
# get <name> reading     => measurement for all channels
#
# Additional attributes are defined in fhem.cfg as 
#  attr    pt8005 room Noise
# Monthly and yearly log file
#  attr    pt8005 LogM NoiseLogM
#  attr    pt8005 LogY NoiseLogY
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
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
########################################################################################
package main;

use strict;
use warnings;
use Device::SerialPort;

#-- Prototypes to make komodo happy
use vars qw{%attr %defs};
sub Log($$);

#-- globals 
my $freq ="db(A)";     # dB(A) or dB(C)
my $speed="fast";      # response speed fast or slow
my $mode ="normal";    # min/max/...
my $range="50-100 dB"; # measurement range
my $over ="";          # over/underflow

#-- arrays for averaging (60 values = max. 1 hour)
my @datarr;
my @timarr;
my $arrind=0;
my $arrmax=60;

#-- arrays for hourly values
my @hourarr;

#-- These we may get on request
my %gets = (
  "present"   => "",
  "reading"   => "R",
);

#-- These occur in a pulldown menu as settable values
my %sets = (
  "Min/Max"=> "", 
  "off"   => "O",
  "rec"   => "",
  "speed" => "",
  "range" => "",      # toggle the measurement range
  "auto"  => "",      # set the measurement range to auto
  "dBA/C" => "",      # toggle the frequency curve
  "freq"  => ""       # set the frequency curve to a value db(A) or db(C)
);

#-- Single key commands to the PT8005
my %SKC = ("Min/Max","\x11", "off","\x33", "rec","\x55", "speed","\x77", "range","\x88", "dBA/C","\x99");


########################################################################################
#
# PT8005_Initialize
#
# Parameter hash
#
########################################################################################

sub PT8005_Initialize ($) {
  my ($hash) = @_;
  
  $hash->{DefFn}   = "PT8005_Define";
  $hash->{GetFn}   = "PT8005_Get";
  $hash->{SetFn}   = "PT8005_Set";
  # LogM, LogY = name of the monthly and yearly log file
  $hash->{AttrList}= "LogM LogY ".
           "loglevel ".
           $readingFnAttributes;
}

########################################################################################
#
# PT8005_Define - Implements DefFn function
#
# Parameter hash, definition string
#
########################################################################################

sub PT8005_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Define the serial device as a parameter"
    if(@a != 3);
  
  my $dev = $a[2];

  Log 1, "PT8005 opening device $dev";
  my $pt8005_serport = new Device::SerialPort ($dev);
  return "PT8005 Can't open $dev: $!" if(!$pt8005_serport);
  Log 1, "PT8005 opened device $dev";
  $hash->{USBDev} =  $pt8005_serport;
  sleep(1);
  $pt8005_serport->close();  
 
  $hash->{DeviceName}   = $dev;
  $hash->{INTERVAL}       = 60;        # call every 60 seconds
  
  $modules{PT8005}{defptr}{$a[0]} = $hash;

  #-- InternalTimer blocks if init_done is not true
  my $oid = $init_done;
  $init_done = 1;
  readingsSingleUpdate($hash,"state","initialized",1);
   
  PT8005_GetStatus($hash);
  $init_done = $oid;
  return undef;
}

#######################################################################################
#
# PT8005_Average - Average backwards over given period
# 
# Parameter hash, secsincemidnight,period
#
########################################################################################

sub PT8005_Average($$$) {

  my ($hash, $secsincemidnight, $period) = @_;
  
  #-- max. 1 hour allowed
  if( $period>3600 ){
    Log 1,"PT8005_Average: wrong period, must be <=3600";
    return 0;
  }

  my ($minind,$cntind,$oldtime,$ia,$ib,$fa,$fb,$ta,$tb,$fd,$avdata);
  
  #-- go backwards until we have period covered (=max. 60 values)
  $minind=$arrind-1;
  $cntind=1;
  $minind+=$arrmax if($minind<0);
  $oldtime = $timarr[$minind];
  $oldtime-=86400 if($oldtime > $secsincemidnight); 
  while( $oldtime > $secsincemidnight-$period ){
    #Log 1,"===>index $minind is ".($secsincemidnight-$timarr[$minind])." ago";
    $minind--;
    $minind+=$arrmax if($minind<0);
    $oldtime = $timarr[$minind];
    $oldtime-=86400 if($oldtime > $secsincemidnight); 
    $cntind++;
    if( $cntind > $arrmax) {
       $cntind=$arrmax;
       Log 1,"PT8005_Average: ERROR, cntind > $arrmax";
       last;
    }
  }
  #-- now go forwards 
  #-- first value must be done by hand
  $ia = $minind;
  $ib = $minind+1;
  $ib-=$arrmax if($ib>=$arrmax);
  $fa = $datarr[$ia];
  $fb = $datarr[$ib];
  $ta = $timarr[$ia];
  $ta-= 86400 if($ta > $secsincemidnight);
  $tb = $timarr[$ib];
  $tb-= 86400 if($tb > $secsincemidnight);
  $fd = $fa + ($fb-$fa)*($secsincemidnight-$period - $ta)/($tb - $ta);
  $avdata = ($fd + $fb)/2 * ($tb - ($secsincemidnight-$period));
  #Log 1,"===> interpolated value for data point between $ia and $ib is $fd and avdata=$avdata (tb=$tb, ssm=$secsincemidnight)";  
  #-- other values can be done automatically
  for( my $i=1; $i<$cntind; $i++){
    $ia = $minind+$i;
    $ia-= $arrmax if($ia>=$arrmax);
    $ib = $ia+1;
    $ib-= $arrmax if($ib>=$arrmax);
    $fa = $datarr[$ia];
    $fb = $datarr[$ib];
    $ta = $timarr[$ia];
    $ta-= 86400 if($ta > $secsincemidnight);
    $tb = $timarr[$ib];
    $tb-= 86400 if($tb > $secsincemidnight);
    $avdata += ($fa + $fb)/2 * ($tb - $ta);
    #Log 1,"===> adding a new interval between $ia and $ib, new avdata = $avdata (tb=$tb ta=$ta)";  
  }
  #-- and now the average for 15 minutes:
  $avdata = int($avdata/($period/10))/10;
  
  return $avdata;
}
  
#########################################################################################
#
# PT8005_Cmd - Write command to meter
# 
# Parameter hash, cmd = command 
#
########################################################################################

 sub PT8005_Cmd ($$) {
  my ($hash, $cmd) = @_;

  my $res;
  my $dev= $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $serport = new Device::SerialPort ($dev);
  
  if(!$serport) {
      Log GetLogLevel($name,1), "PT8005: Can't open $dev: $!";
      return undef;
  }
  $serport->reset_error();
  $serport->baudrate(9600);
  $serport->databits(8);
  $serport->parity('none');
  $serport->stopbits(1);
  $serport->handshake('none');
  $serport->write_settings;
    
  #-- calculate checksum and send
  #my $cmd="\x33";
  my $count_out = $serport->write($cmd);
  Log GetLogLevel($name,3), "PT8005 write failed\n"  unless ($count_out);
  #-- sleeping 0.05 seconds
  select(undef,undef,undef,0.05);
  my ($count_in, $string_in) = $serport->read(4);
  #-- control
  #my ($i,$j,$k);
  #my $ans="receiving:";
  #for($i=0;$i<$count_in;$i++){
  #  $j=int(ord(substr($string_in,$i,1))/16);
  #  $k=ord(substr($string_in,$i,1))%16;
  #  $ans.="byte $i = 0x$j$k\n";
  #}
  #Log 1, $ans;
  #-- sleeping 0.05 seconds
  select(undef,undef,undef,0.05);
  $serport->close();
}
  
########################################################################################
#
# PT8005_Get -  Implements GetFn function 
#
# Parameter hash, argument array
#
########################################################################################

sub PT8005_Get ($@) {
  my ($hash, @a) = @_;

  #-- check syntax
  return "PT8005_Get needs exactly one parameter" if(@a != 2);
  my $name = $hash->{NAME};
  my $v;

  #-- get present
  if($a[1] eq "present") {
    $v =  ($hash->{READINGS}{"state"}{VAL} =~ m/.*dB.*/) ? 1 : 0;
    return "$a[0] present => $v";
  } 

  #-- current reading
  if($a[1] eq "reading") {
    $v = PT8005_GetStatus($hash);
    if(!defined($v)) {
      Log GetLogLevel($name,2), "PT8005_Get $a[1] error";
      return "$a[0] $a[1] => Error";
    }
    $v =~ s/[\r\n]//g;                          # Delete the NewLine
  } else {
    return "PT8005_Get with unknown argument $a[1], choose one of " . join(",", sort keys %gets);
  }

  Log GetLogLevel($name,3), "PT8005_Get $a[1] $v";
  return "$a[0] $a[1] => $v";
}
 
#######################################################################################
#
# PT8005 - GetStatus - Called in regular intervals to obtain current reading
#
# Parameter hash
#
########################################################################################

sub PT8005_GetStatus ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my ($bcd,$i,$j,$k);
  my ($hour,$min,$sec,$time);
  my $data=0.0;
  my $nospeed=1;
  my $norange=1;
  my $nofreq=1;
  my $nodata=1;
  my $loop=0;
  
  my $secsincemidnight;
  my $av15=0;

  #-- restart timer for updates
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+ $hash->{INTERVAL}, "PT8005_GetStatus", $hash,1);
  #-- check if rec is really off
  PT8005_Unrec($hash);
  
   #-- Obtain the current reading
  my $res;
  my $dev= $hash->{DeviceName};
  my $serport = new Device::SerialPort ($dev);
  
  if(!$serport) {
    Log GetLogLevel($name,3), "PT8005_Read: Can't open $dev: $!";
    return undef;
  }
  $serport->reset_error();
  $serport->baudrate(9600);
  $serport->databits(8);
  $serport->parity('none');
  $serport->stopbits(1);
  $serport->handshake('none');
  $serport->write_settings;
   
  #-- switch into recording mode
  my $count_out = $serport->write($SKC{"rec"});
  Log GetLogLevel($name,3), "PT8005_GetStatus: Switch to REC failed" unless ($count_out);
  #-- sleeping some time
  select(undef,undef,undef,0.15);
 
  #-- loop for the data 
  while ( ($nodata > 0) and ($loop <3) ){
    #my $string_in=PT8005_Read($hash);
    select(undef,undef,undef,0.02);
    my ($count_in, $string_in) = $serport->read(64);
    $loop++;
  
    #--find data items    
    if( index($string_in,"\xA5\x02") != -1){
      $nospeed=0;
      $speed="fast";
    } elsif( index($string_in,"\xA5\x03") != -1){
      $nospeed=0;
      $speed="slow";
    }
   
    if( index($string_in,"\xA5\x04") != -1){
      $mode="max";
    }elsif( index($string_in,"\xA5\x05") != -1){
      $mode="min";
    }else{
      $mode="normal";
    }
   
    if( index($string_in,"\xA5\x10") != -1){
      $norange=0;
      $range="30-80 dB";
    }elsif( index($string_in,"\xA5\x20") != -1){
      $norange=0;
      $range="50-100 dB";
    }elsif( index($string_in,"\xA5\x30") != -1){
      $norange=0;
      $range="80-130 dB";
    }elsif( index($string_in,"\xA5\x40") != -1){
      $norange=0;
      $range="30-130 dB";
    }
  
    if( index($string_in,"\xA5\x07") != -1){
      $over="over";
    }elsif( index($string_in,"\xA5\x08") != -1){
      $over="under";
    }else{
      $over="";
    }
   
    if( index($string_in,"\xA5\x1B") == -1){
      $nofreq=0;
      $freq="dB(A)";
    } elsif ( index($string_in,"\xA5\x1C") != -1){
      $nofreq=0;
      $freq="dB(C)";  
    } 
     
    #-- time not needed
    #my $in_time = index($string_in,"\xA5\x06");
    #if( $in_time != -1 ){
    #  $bcd=ord(substr($string_in,$in_time+2,1));
    #  $hour=int($bcd/16)*10 + $bcd%16 - 20;
    #  $bcd=ord(substr($string_in,$in_time+3,1));
    #  $min = int($bcd/16)*10 + $bcd%16;
    #  $bcd=ord(substr($string_in,$in_time+4,1));
    #  $sec = int($bcd/16)*10 + $bcd%16;     
    #  $time=sprintf("%02d:%02d:%02d",$hour,$min,$sec);
    #} else { 
    #  $time="undef";
    #  Log GetLogLevel($name,3),"PT8005_GetStatus: no time value obtained"
    #}
  
    #-- data value
    my $in_data = index($string_in,"\xA5\x0D");
    if( $in_data != -1){
      my $s1=substr($string_in,$in_data+2,1);
      my $s2=substr($string_in,$in_data+3,1);
      if( ($s1 ne "") && ($s2 ne "") ){ 
        $nodata = 0;
        $bcd=ord($s1);
        $data=(int($bcd/16)*10 + $bcd%16)*10;
        $bcd=ord($s2);
        $data+=(int($bcd/16)*10 + $bcd%16)*0.1;
      }
    } 
  }

  #-- sleeping some time
  select(undef,undef,undef,0.01);
  #-- leave recording mode
  $count_out = $serport->write($SKC{"rec"}); 
  #-- sleeping some time
  select(undef,undef,undef,0.01);
  #-- 
  $serport->close();
  
  #-- could not find a value
  if( $nofreq==1 ){
    Log GetLogLevel($name,4), "PT8005_GetStatus: no dBA/C frequency curve value obtained";
  };
  if( $norange==1 ){
    Log GetLogLevel($name,4), "PT8005_GetStatus: no range value obtained";
  };
  if( $nospeed==1 ){
    Log GetLogLevel($name,4), "PT8005_GetStatus: no speed value obtained";
  };
  if( $nodata==1 ){
    Log GetLogLevel($name,4), "PT8005_GetStatus: no data value obtained";
  };
  
  #-- addnl. messages
  if( $over eq "over"){
    Log GetLogLevel($name,4), "PT8005_GetStatus: Range overflow";
  }elsif( $over eq "under" ){
    Log GetLogLevel($name,4), "PT8005_GetStatus: Range underflow";
  }
  
  #-- put into readings
  $hash->{READINGS}{"soundlevel"}{UNIT}     = $freq 
    if( $nofreq ==0 );
  $hash->{READINGS}{"soundlevel"}{UNITABBR} = $freq
    if( $nofreq ==0 );
  
  #-- testing for wrong data value 
  if( $data <=30 ){
    $nodata=1;
  };
  
  #-- put into READINGS
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"speed",$speed)     
    if( $nospeed ==0 );
  readingsBulkUpdate($hash,"mode",$mode); 
  readingsBulkUpdate($hash,"range",$range)     
    if( $norange ==0 );
  readingsBulkUpdate($hash,"overflow",$over);
    
  if( $nodata==0 ){

    my ($sec, $min, $hour, $day, $month, $year, $wday,$yday,$isdst) = localtime(time);
    $secsincemidnight = $hour*3600+$min*60+$sec;
    $datarr[$arrind] = $data;
    $timarr[$arrind] = $secsincemidnight;    
     
    $av15 = PT8005_Average($hash,$secsincemidnight,900);
    
    $arrind++;
    $arrind-=$arrmax if($arrind>=$arrmax);
    
    my $svalue = sprintf("%3.1f %s [av15 %3.1f %s]",$data,$freq,$av15,$freq);
    my $lvalue = sprintf("%3.1f av15  %3.1f ",$data,$av15);
    readingsBulkUpdate($hash,"state",$svalue);  
    readingsBulkUpdate($hash,"soundlevel",$lvalue);
      
  }  
  readingsEndUpdate($hash,1); 
}
 
########################################################################################
#
# PT8005_Set - Implements SetFn function
#
# Parameter hash, a = argument array
#
########################################################################################

sub PT8005_Set ($@) {
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $res;

  #-- for the selector: which values are possible
  #return join(" ", sort keys %sets) if(@a != 2);
  return "PT8005_Set: With unknown argument $a[0], choose one of " . join(" ", sort keys %sets)
    if(!defined($sets{$a[0]}));
 
  my $dev= $hash->{DeviceName};
  
  #-- Set single key value
  for (keys %SKC){
    if( $a[0] eq "$_" ){
      Log GetLogLevel($name,1),"PT8005_Set called with arg $_";
      PT8005_Cmd($hash,$SKC{$_});
    }
  }
  
  #-- Set frequency curve to db(A) or db(C)
  if( $a[0] eq "freq" ){
    my $freqn = $a[1];
    if ( (!defined($freqn)) || (($freqn ne "dB(A)") && ($freqn ne "dB(C)")) ){
      return "PT8005_Set $name ".join(" ",@a)." with missing parameter, must be dB(A) or dB(C) ";
    }
    if ( (($freq eq "dB(A)") && ($freqn eq "dB(C)")) ||
         (($freq eq "dB(C)") && ($freqn eq "dB(A)")) ){
    Log GetLogLevel($name,1),"PT8005_Set freq $freqn";
    $res=PT8005_Cmd($hash,$SKC{"dBA/C"});
    }
  }
  
  #-- Set measurement range to auto
  if( $a[0] eq "auto" ){
    if ($range eq "30-80 dB"){
      $res =PT8005_Cmd($hash,$SKC{"range"});
      select(undef,undef,undef,0.05);
      $res.=PT8005_Cmd($hash,$SKC{"range"});
      select(undef,undef,undef,0.05);
      $res.=PT8005_Cmd($hash,$SKC{"range"});
    }elsif ($range eq "50-100 dB"){ 
      $res =PT8005_Cmd($hash,$SKC{"range"});
      select(undef,undef,undef,0.05);
      $res.=PT8005_Cmd($hash,$SKC{"range"});
    }elsif ($range eq "80-130 dB"){ 
      $res=PT8005_Cmd($hash,$SKC{"range"});
    }
     
    Log GetLogLevel($name,1),"PT8005_Set auto";
  }
  
  Log GetLogLevel($name,3), "PT8005_Set $name ".join(" ",@a)." => $res";  
  return "PT8005_Set $name ".join(" ",@a)." => $res";
}

########################################################################################
#
# PT8005_Unrec - switch recording mode off
# 
# Parameter hash 
#
########################################################################################

 sub PT8005_Unrec ($) {
  my ($hash) = @_;

  my $res;
  my $dev= $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $serport = new Device::SerialPort ($dev);
  
  if(!$serport) {
      Log GetLogLevel($name,3), "PT8005_UnRec: Can't open $dev: $!";
      return undef;
  }
  $serport->reset_error();
  $serport->baudrate(9600);
  $serport->databits(8);
  $serport->parity('none');
  $serport->stopbits(1);
  $serport->handshake('none');
  $serport->write_settings;
    
  for(my $i = 0; $i < 3; $i++) {  
    #-- read data and look if it is nonzero
    my ($count_in, $string_in) = $serport->read(1);
    if( $string_in eq "" ){
      $serport->close();
      Log GetLogLevel($name,4),"PT8005_UnRec:  REC is off ";
      return 1;
    } else {
    #-- leave recording mode
      select(undef,undef,undef,0.02);
      my $count_out = $serport->write($SKC{"rec"}); 
      #-- sleeping some time
      select(undef,undef,undef,0.02);
    }
  }
  $serport->close();
  Log GetLogLevel($name,4),"PT8005_UnRec: REC cannot be turned off ";
 
  return 0;
}

1;


=pod
=begin html

<a name="PT8005"></a>
        <h3>PT8005</h3>
        <p>FHEM module to commmunicate with a PeakTech PT8005 soundlevel meter<br />
        </p>
        <h4>Example</h4>
        <p>
            <code>define pt8005 PT8005 /dev/ttyUSB0 </code>
        </p><br />   
        <a name="PT8005define"></a>
        <h4>Define</h4>
        <p>
        <code>define &lt;name&gt; PT8005  &lt;device&gt; </code> 
        <br /><br /> Define a PT8005 soundlevel meter</p>
        <ul>
          <li>
            <code>&lt;name&gt;</code>
           Serial device port 
         </li>
        </ul>
        <a name="PT8005set"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="pt8005_time">
                   Not yet implemented</a></li>
        </ul>
        <br />
        <a name="PT8005get"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="pt8005_reading">
                    <code>get &lt;name&gt; reading</code></a>
                <br /> read all current data </li>
            <li><a name="pt8005_present">
                    <code>get &lt;name&gt; present</code></a>
                <br /> 1 if device present, 0 if not </li>
        </ul>
        <br />
        <a name="PT8005attr"></a>
        <h4>Attributes</h4>
        <ul>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a
                    href="#stateFormat">stateFormat</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
        
=end html
=cut

