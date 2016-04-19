###############################################
#
# 47_OBIS.pm
#
# Thanks to matzefizi for letting me merge this with 70_SMLUSB.pm and for testing
# Tanks to immi for testing and supporting help and tips
# 
# $Id$

package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday usleep);
use Scalar::Util qw(looks_like_number);
use POSIX qw{strftime};

my %OBIS_channels = ( "21"=>"power_L1",
                 "41"=>"power_L2",
                 "61"=>"power_L3",
                 "12"=>"voltage_avg",
                 "32"=>"voltage_L1",
                 "52"=>"voltage_L2",
                 "72"=>"voltage_L3",
                 "11"=>"current_sum",
                 "31"=>"current_L1",
                 "51"=>"current_L2",
                 "71"=>"current_L3",
                 "1.8"=>"total_consumption",
                 "2.8"=>"total_feed",
                 "2"=>"feed_L1",
                 "4"=>"feed_L2",
                 "6"=>"feed_L3",
                 "1"=>"power", 
                 "15"=>"power",
                 "16"=>"power");
                 
my %OBIS_codes = (	"Serial" 		=> qr{0.0.96.1.255.255\((.*?)\).*
										 |1-0:0\.0\.[0-9]+\*255\((.*?)\).*}x,
					"Owner" 		=> qr{1.0.0.0.0.255\((.*?)\).*}x,
					"Status" 		=> qr{1.0.96.5.5.255\((.*?)\).*}x,
					"Powerdrops"	=> qr{0.0.96.7.\d.255\((.*?)\).*},
					"Time_param"	=> qr{0.0.96.2.1.255\((.*?)\).*},
					"Time_current"	=> qr{0.0.1.0.0.255\((.*?)\).*},
					"Channels_sum" 	=> qr{1.0.(\d+).1.7.255\((<|>)?([-+]?\d+\.?\d*)\*?(.*)\).*},
					"Channels"		=> qr{1.0.(\d+).7\.\d+.\d+\((<|>)?([-+]?\d+\.?\d*)\*?(.*)\).*},
					"Counter"		=> qr{1.0.([12]).(8)\.(\d).255\((<|>)?(-?\d+\.?\d*)\*?(.*)\).*},
					"ManufID"		=> qr{129-129:199\.130\.3\*255\((.*?)\).*},
					"PublicKey"		=> qr{129-129:199\.130\.5\*255\((.*?)\).*},
					"ErrorReg"		=> qr{0.0.97.97.\d.255\((.*?)\).*}
				);

my %SML_specialities = ("TIME"			=> [qr{0.0.96.2.1
											   0.0.1.0.0		}x, sub{return strftime("%d-%m-%Y %H:%M:%S", localtime(unpack("i", pack("I", hex(@_)))))}],
						"HEX2"			=> [qr{1-0:0\.0\.[0-9]	}x, sub{my $a=shift;$a=~s/(..)/$1-/g;$a=~s/-$//;return $a;}],
						"HEX4"			=> [qr{1.0.96.5.5
										 	  |0.0.96.240.\d+
											  |129.129.199.130.5}x, sub{my $a=shift;$a=~s/(....)/$1-/g;$a=~s/-$//;return $a;}],
						"INFO"			=> [qr{1-0:0\.0\.[0-9]
											  |129.129.199.130.3}x, ""],
);
    
#####################################
sub OBIS_Initialize($)
{
  my ($hash) = @_;
  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{Match}     = "OBIS";
  $hash->{ReadFn}  = "OBIS_Read";
  $hash->{ReadyFn}  = "OBIS_Ready";
  $hash->{DefFn}   = "OBIS_Define";
  $hash->{ParseFn}   = "OBIS_Parse";
  #  $hash->{SetFn} = "OBIS_Set";
  
  $hash->{UndefFn} = "OBIS_Undef";
  $hash->{AttrFn}	= "OBIS_Attr";
  $hash->{AttrList}= "do_not_notify:1,0 interval offset_feed offset_energy IODev channels directions alignTime pollingMode:on,off unitReadings:on,off ".
  					  $readingFnAttributes;
}

#####################################
sub OBIS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return 'wrong syntax: define <name> OBIS devicename@baudrate[,databits,parity,stopbits]|none [MeterType]'
    if(@a < 3);
  DevIo_CloseDev($hash);
  RemoveInternalTimer($hash);  
  my $name = $a[0];
  my $dev = $a[2];
  my $type = $a[3]//"Unknown";
  
  $hash->{DeviceName} = $dev;
  $hash->{MeterType}=$type if (defined($type)); 

  my $device_name = "OBIS_".$name;
  $modules{OBIS}{defptr}{$device_name} = $hash;
  
# If device="none", prepeare for an external IO-Module
  if($dev=~/none|ext/) {
  	if (@a == 4){
	  	my $device_name = "OBIS.".$a[4];
	  	$hash->{CODE} = $a[4];
	  	$modules{OBIS}{defptr}{$device_name} = $hash;
  	}
    AssignIoPort($hash);
    Log3 ($hash,1, "OBIS ($name) - OBIS device is none, commands will be echoed only");
   return undef;
  }


  my $baudrate;
  my $devi;
  ($devi, $baudrate) = split("@", $dev);
  
  if (defined($baudrate)) {   ## added for ser2net connection
	if($baudrate =~ m/(\d+)(,([78])(,([NEO])(,([012]))?)?)?/) {
	$baudrate = $1 if(defined($1));
	}
	my %bd=("300"=>"0","600"=>"1","1200"=>"2","2400"=>"3","4800"=>"4","9600"=>"5");
	$hash->{helper}{SPEED}=$bd{$baudrate};
  }
  else {$baudrate=9600; $hash->{helper}{SPEED}="5";}
  
  my %devs= (
#   Name,      Init-String,                 interval,  2ndInit
    "none"		=>	["",                        -1,    ""],
    "Unknown"	=>	["",                        -1,    ""],
    "SML"		=>	["",                        -1,    ""],
    "Ext"		=>	["",                        -1,    ""],
    "Standard"	=>	["",                        -1,    ""],
    "VSM102"	=> 	["/?!".chr(13).chr(10),    600,    chr(6)."0".$hash->{helper}{SPEED}."0".chr(13).chr(10)],
    "E110"		=>  ["/?!".chr(13).chr(10),    600,    chr(6)."0".$hash->{helper}{SPEED}."0".chr(13).chr(10)],
    );
    if (!$devs{$type}) {return 'unknown meterType. Must be one of <nothing>, SML, Standard, VSM102, E110'};
    $devs{$type}[1] = $hash->{helper}{DEVICES}[1] // $devs{$type}[1];
    $hash->{helper}{DEVICES} =$devs{$type};
    $hash->{helper}{TRIGGERTIME}=gettimeofday();
#    if( !$init_done ) {
#	    $attr{$name}{"event-on-change-reading"} = ".*";
 #   }
	my $t=OBIS_adjustAlign($hash,AttrVal($name,"alignTime",undef),$hash->{helper}{DEVICES}[1]);
    Log3 ($hash,5,"OBIS ($name) - Internal timer set to ".FmtDateTime($t)) if ($hash->{helper}{DEVICES}[1]>0);
	InternalTimer($t, "GetUpdate", $hash, 0) if ($hash->{helper}{DEVICES}[1]>0);
	$hash->{helper}{EoM}=-1;
  
  	Log3 $hash,5,"OBIS ($name) - Opening device...";
  	  return DevIo_OpenDev($hash, 0, "OBIS_Init");
}

# Update-Routine
sub GetUpdate($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $type= $hash->{MeterType};
	RemoveInternalTimer($hash);

	$hash->{helper}{EoM}=-1;
	if ($hash->{helper}{DEVICES}[1] eq "") {return undef;}
	DevIo_SimpleWrite($hash,$hash->{helper}{DEVICES}[0],undef) ;
	my $t=OBIS_adjustAlign($hash,AttrVal($name,"alignTime",undef),$hash->{helper}{DEVICES}[1]);
    Log3 ($hash,5,"OBIS ($name) - Internal timer set to ".FmtDateTime($t)) if ($hash->{helper}{DEVICES}[1]>0);
	InternalTimer($t, "GetUpdate", $hash, 1)  if ($hash->{helper}{DEVICES}[1]>0);
}

sub OBIS_Init($)
{
  return undef;
}
#####################################
sub OBIS_Undef($$)
{
  my ($hash, $arg) = @_;
  RemoveInternalTimer($hash);  
  DevIo_CloseDev($hash) if $hash->{DeviceName} ne "none";
  return undef;
}

#####################################
sub OBIS_Read($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
    my $buf = DevIo_SimpleRead($hash);
    OBIS_Parse($hash,$buf) if ($hash->{helper}{EoM}!=1);
    return(undef);
}



sub OBIS_trySMLdecode($$)
{
	my ( $hash, $remainingSML ) = @_;
	if($remainingSML!~/[\x00-\x09|\x10-\x20]/g) {return $remainingSML} else {$hash->{MeterType}="SML"};
	$remainingSML=uc(unpack('H*',$remainingSML));
	$hash->{MeterType}="SML";
	my $newMsg="";
	while ($remainingSML=~/(1B1B1B1B010101.*?1B1B1B1B1A[0-9A-F]{6})/mip) {
		my $msg=$1;
		$remainingSML=${^POSTMATCH};
		if (OBIS_CRC16($hash,pack('H*',$msg)) == 1) {
			$remainingSML=""; #reset possible further messages if actual CRC ok; if someone misses some sessages we remove it. 
			my $OBISmsg="";
			my $initstr="/";
			my $OBISid=$msg=~m/7701([0-9A-F]*?)01/g;
			(undef,undef,$OBISid,undef)=OBIS_decodeTL($1);
			while ($msg =~ m/(7707)([0-9A-F]{2,999}?)(?=7707|1B1B1B1B)/g) {
	    		my $telegramm = $&;
      			my @list=$telegramm=~/(7707)([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2,999})/g;
	    		my $line=hex($list[1])."-".hex($list[2]).":".hex($list[3]).".".hex($list[4]).".".hex($list[5])."*255(";
	    		
				my ($status,$statusL,$statusT,$valTime,$valTimeL,$valTimeT,$unit,$unitL,$unitT,$scaler,$scalerL,$scalerT,$data,$dataL,$dataT,$other);		   
	    		($statusL,$statusT,$status,$other)=OBIS_decodeTL($list[7]);
	    		($valTimeL,$valTimeT,$valTime,$other)=OBIS_decodeTL($other);
	    		($unitL,$unitT,$unit,$other)=OBIS_decodeTL($other);
	    		($scalerL,$scalerT,$scaler,$other)=OBIS_decodeTL($other);
	    		($dataL,$dataT,$data,$other)=OBIS_decodeTL($other);
	    		
# Type String
				my $line2=""; 
	    		if ($dataT ==0 ) {						
	    			if($line=~$SML_specialities{"HEX4"}[0]) {
	    				$line2=$SML_specialities{"HEX4"}[1]->($data)
	    			} elsif($line=~$SML_specialities{"HEX2"}[0]) {
    					$line2=$SML_specialities{"HEX2"}[1]->($data)
	    			} else {
	    				$data=~s/([A-F0-9]{2})/chr(hex($1))/eg;
	    				$line2="$data";
    				}
# Type signed (=80) and unsigned (=96) Integer
				} elsif ($dataT & 0b01010000|$dataT & 0b01100000) {		
					$unit= $unit eq "1E" ? "Wh" :
   							  $unit eq "1B" ? "W" :
   							  $unit eq "21" ? "A" :
   							  $unit eq "23" ? "V" :
   							  $unit eq "2C" ? "Hz" :
   							  $unit eq "01" ? ""  : 
   							  $unit eq "1D" ? "varh" :
   							  $unit eq "" ? "" : "var";
					$scaler=$scaler ne "" ? 10**unpack("c", pack("C", hex($scaler))) : 0;
					if ($scaler==0) {$scaler=1};	# just to make sure
					$line2.="<" if ($status=~/[aA]2$/);
					$line2.=">" if ($status=~/82$/);
					$line2.=(OBIS_hex2int($data)*$scaler).($unit eq "" ? "" : "*$unit")  if($dataT ==80);
					$line2.=(unpack("s", pack("S", hex($data)))*$scaler).($unit eq "" ? "" : "*$unit") if($dataT ==96);					
				} elsif ($dataT & 0b01000000) {		# Type Boolean - no Idea, where this is used
					$line2=OBIS_hex2int($data);			# 0=false, everything else is true
				} elsif ($dataT & 0b01110000) {		# Type List of.... - not sure, if we ever need that
				}
				$initstr.="$line2\\" if ($line=~$SML_specialities{"INFO"}[0]);
				$newMsg.=$line.$line2.")\r\n";
###### TypeLength-Test ends here

			}
			$initstr=~s/\\$//;
			$newMsg=$initstr.chr(13).chr(10).$newMsg;
			$newMsg.="!".chr(13).chr(10);
		} else {
			$hash->{CRC_Errors}+=1;
		}
	}
		return ($newMsg,pack('H*',$remainingSML));
	
}

sub OBIS_Parse($$)
{
	my ($hash, $buf) = @_;
	my $buf2=uc(unpack('H*',$buf));
	if($hash->{MeterType}!~/SML|Unknown/ && $buf2=~m/7701([0-9A-F]*?)01/g) {
		Log 3,"OBIS_Ext called";
		my (undef,undef,$OBISid,undef)=OBIS_decodeTL($1);
		
	  	my $device_name = "OBIS.".$OBISid;
  		Log3 $hash,5,"New Devicename: $device_name";
  		my $def = $modules{OBIS}{defptr}{"$device_name"};
  		if(!$def) {
        	Log3 $hash, 3, "OBIS: Unknown device $device_name, please define it";
        	return "UNDEFINED $device_name OBIS none Ext $OBISid";
  		}
	}
	$hash->{helper}{BUFFER} .= $buf;
	if (length($hash->{helper}{BUFFER}) >5000) { #longer than 3 messages, this is a traffic jam
	  	$hash->{helper}{BUFFER}  =substr( $hash->{helper}{BUFFER} , -1500);
   }	
   my %dir=("<"=>"out",">"=>"in");
	
	my $buffer=$hash->{helper}{BUFFER};
	
	my $remainingSML;
	($buffer,$remainingSML) = OBIS_trySMLdecode($hash,$buffer) if ($hash->{MeterType}=~/SML|Ext|Unknown/);
	my $type= $hash->{MeterType};
	my $name = $hash->{NAME};  
	if(index($buffer,chr(13).chr(10)) ne -1){
		readingsBeginUpdate($hash);
	    while(index($buffer,chr(13).chr(10)) ne -1)
	    {
	      my $rmsg="";
	      $rmsg = substr($buffer, 0, index($buffer,chr(13).chr(10)));
			Log3 $hash,5,"OBIS ($name) - Msg-Parse: $rmsg";
				if($rmsg=~/\/.*|\d-\d{1,3}:\d{1,3}.\d{1,3}.\d{1,3}\*\d{1,3}\(.*?\)|!/) {
					if ($hash->{MeterType} eq "Unknown") {$hash->{MeterType}="Standard"}
					if($rmsg=~/^([23456789]+)-.*/) {
						Log3 $hash,3,"OBIS ($name) - Unknown OBIS-Device, please report: $rmsg".chr(13).chr(10)."Please report to User icinger at forum.fhem.de";
					}
			
			# End of Message
					if ($rmsg=~/!.*/) {
						$hash->{helper}{EoM}+=1 if ($hash->{helper}{DEVICES}[1]>0);
					}
			
			#Version
					if ($rmsg=~ /.*\/(.*)/) {
					  	DevIo_SimpleWrite($hash,$hash->{helper}{DEVICES}[2],undef) if (!$hash->{helper}{DEVICES}[2] eq "");
				  		if (ReadingsVal($name,"Version","") ne $1) {readingsBulkUpdate($hash, "Version"  ,$1); }
			 			$hash->{helper}{EoM}=0;
				  	}
				  	if ($hash->{helper}{EoM}!=1) {
				  		my @patterns=values %OBIS_codes;
				  		if (!$rmsg~~@patterns) {
				  			Log3 $hash,3,"OBIS ($name) - Unknown Message: $rmsg".chr(13).chr(10)."Please report to User icinger at forum.fhem.de"
				  		} else {
							for my $code (keys %OBIS_codes) {
								if ($rmsg =~ $OBIS_codes{$code}) {
									if ($code eq "Channels_sum") {
							    		my $L=$hash->{helper}{Channels}{$1} // $OBIS_channels{$1} // "Unknown_Channel_$1";
					  					readingsBulkUpdate($hash, "sum_$L",(looks_like_number($3) ? $3+0 : $3).(AttrVal($name,"unitReadings","off") eq "off"?"":" $4"));
					  					readingsBulkUpdate($hash, "dir_sum_$L",$hash->{helper}{directions}{$2} // $dir{$2}) if (length $2);
									}
									 
									elsif ($code eq "Channels") {
							    		my $L=$hash->{helper}{Channels}{$1} // $OBIS_channels{$1} // "Unknown_Channel_$1";
					  					readingsBulkUpdate($hash, "$L",(looks_like_number($3) ? $3+0 : $3).(AttrVal($name,"unitReadings","off") eq "off"?"":" $4"));
					  					readingsBulkUpdate($hash, "dir_$L",$hash->{helper}{directions}{$2} // $dir{$2}) if (length $2);
									}
									
									elsif ($code eq "Counter") {
										my $L=$hash->{helper}{Channels}{$1.".".$2} // $OBIS_channels{$1.".".$2} // "Unknown_Channel_$1.$2";
										my $chan=$3+0 > 0 ? "_Ch$3" : "";
										if($1==1) {
											readingsBulkUpdate($hash, $L.$chan  ,(looks_like_number($3) ? $5+0 : $5) +AttrVal($name,"offset_energy",0).(AttrVal($name,"unitReadings","off") eq "off"?"":" $6")); 
										} elsif ($1==2) {
											readingsBulkUpdate($hash, $L.$chan  ,(looks_like_number($3) ? $5+0 : $5) +AttrVal($name,"offset_feed",0).(AttrVal($name,"unitReadings","off") eq "off"?"":" $6")); 				
										}
					  					readingsBulkUpdate($hash, "dir_$L",$hash->{helper}{directions}{$4} // $dir{$4}) if (length $4);
										
									} else 
										{readingsBulkUpdate($hash, $code  ,$1); 
									}
								}
				     		} 
			   			}
				  	}
		   			if ($hash->{helper}{EoM}==1) {last;}
			  	}
	       $buffer = substr($buffer, index($buffer,chr(13).chr(10))+2);;
    	}
    	readingsEndUpdate($hash,1);
	}
    if (defined($remainingSML)) {$hash->{helper}{BUFFER}=$remainingSML}
    	else{$hash->{helper}{BUFFER}=$buffer;}
	if($hash->{helper}{EoM}==1) { $hash->{helper}{BUFFER}="";}
    return $name;
}


#####################################
sub OBIS_Ready($)
{
  my ($hash) = @_;
  return DevIo_OpenDev($hash, 1, "OBIS_Init")
                if($hash->{STATE} eq "disconnected");

     my $name = $hash->{NAME}; 
    my $dev=$hash->{DeviceName};
  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  return if (!$po);
  ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

sub OBIS_Attr(@)
{
	my ($cmd,$name,$aName,$aVal) = @_;
  	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value
    my $hash  = $defs{$name};
    my $dev=$hash->{DeviceName};
	if ($cmd eq "del") {
		if ($aName eq "channels") { $hash->{helper}{Channels}=undef;}
		if ($aName eq "interval") {
		  		RemoveInternalTimer($hash);
				$hash->{helper}{DEVICES}[1]=0;
		}
		if ($aName eq "pollingMode") {
				delete($readyfnlist{"$name.$dev"});
				$selectlist{"$name.$dev"} = $hash;
				 DevIo_CloseDev($hash);
				DevIo_OpenDev($hash, 0, "OBIS_Init");
		}		
	}
	if ($cmd eq "set") {
		if ($aName eq "channels") {
	      $hash->{helper}{Channels}=eval $aVal;
			if ($@) {
				Log3 $name, 3, "OBIS ($name) - X: Invalid regex in attr $name $aName $aVal: $@";
				$hash->{helper}{Channels}=undef;
			}
		}
		if ($aName eq "directions") {
	      $hash->{helper}{directions}=eval $aVal;
			if ($@) {
				Log3 $name, 3, "OBIS ($name) - X: Invalid regex in attr $name $aName $aVal: $@";
				$hash->{helper}{directions}=undef;
			}
		}
		if ($aName eq "interval") {
			if ($aVal=~/^[1-9][0-9]*$/) {
			    $hash->{helper}{TRIGGERTIME}=gettimeofday();
		  		RemoveInternalTimer($hash);
				$hash->{helper}{DEVICES}[1]=$aVal;
				my $t=OBIS_adjustAlign($hash,AttrVal($name,"alignTime",undef),$hash->{helper}{DEVICES}[1]);
			    Log3 ($hash,5,"OBIS ($name) - Internal timer set to ".FmtDateTime($t)) if ($hash->{helper}{DEVICES}[1]>0);
				InternalTimer($t, "GetUpdate", $hash, 0)  if ($hash->{helper}{DEVICES}[1]>0);
			} else {
				return "OBIS ($name) - $name: attr interval must be a number -> $aVal";
			}
		}
		if ($aName eq "alignTime") {
			 if ($hash->{helper}{DEVICES}[1]>0) {
			 	if ($aVal=~/\d+/) {
			  		RemoveInternalTimer($hash);
				    $hash->{helper}{TRIGGERTIME}=gettimeofday();
					my $t=OBIS_adjustAlign($hash,$aVal,$hash->{helper}{DEVICES}[1]);
				    Log3 ($hash,5,"OBIS ($name) - Internal timer set to ".FmtDateTime($t));
					InternalTimer($t, "GetUpdate", $hash, 0);
			 	} else {return "OBIS ($name): attr alignTime must be a Value >0"}
			 } else {
 				return "OBIS ($name): attr alignTime is useless, if no interval is specified";
			 }			
		}
		if ($aName eq "pollingMode")
		{
			if ($aVal eq "on") {
				delete $hash->{FD};
				delete($selectlist{"$name.$dev"});
				$readyfnlist{"$name.$dev"} = $hash;
			} elsif ($aVal eq "off") {
				delete($readyfnlist{"$name.$dev"});
				$selectlist{"$name.$dev"} = $hash;
				 DevIo_CloseDev($hash);
				DevIo_OpenDev($hash, 0, "OBIS_Init");
			} 
		}
		
	}
	return undef;
}

sub OBIS_adjustAlign($$$)
{
  my($hash, $attrVal, $interval) = @_;
  if (!$attrVal) {return gettimeofday()+$interval;}
  my ($alErr, $alHr, $alMin, $alSec, undef) = GetTimeSpec($attrVal);
  return "$hash->{NAME} alignTime: $alErr" if($alErr);
  my $tspec=strftime("\%H:\%M:\%S", gmtime($interval));
#  Obis_adjustAlignTimetest2($hash,AttrVal($hash->{NAME},"alignTime",undef),$hash->{helper}{DEVICES}[1]);
  
  my (undef, $hr, $min, $sec, undef) = GetTimeSpec($tspec);
  my $now = time();
  my $step = ($hr*60+$min)*60+$sec;
  my $alTime = ($alHr*60+$alMin)*60+$alSec;#-fhemTzOffset($now);	
  
  my $ttime = int($hash->{helper}{TRIGGERTIME});
  my $off = ($ttime % 86400) - 86400;
  if ($off >= $alTime) {
	  $ttime = gettimeofday();#-86400;
	  $off -=  86400;
  }
  my $off2=$off;
  while($off < $alTime) {
    $off += $step;
  }
  $ttime += ($alTime-$off);
  $ttime += $step if($ttime <= $now);
  $hash->{NEXT} = FmtDateTime($ttime);
  $hash->{helper}{TRIGGERTIME} = ($off2<=$alTime) ? $ttime : (gettimeofday());
  
  return $hash->{helper}{TRIGGERTIME};
}

sub OBIS_hex2int {
    my ($hexstr) = @_;
    return 0  
      if $hexstr !~ /^[0-9A-Fa-f]{1,35}$/;
    my $num = hex($hexstr);
    return $num >> 31 ? $num - 2 ** 32 : $num;
}

sub OBIS_CRC16($$) {
	my ($hash,$buff)=@_;
	my @crc16 = ( 0x0000, 0x1189, 0x2312, 0x329b, 0x4624, 0x57ad, 0x6536, 0x74bf, 0x8c48,
		0x9dc1, 0xaf5a, 0xbed3, 0xca6c, 0xdbe5, 0xe97e, 0xf8f7, 0x1081, 0x0108, 0x3393, 0x221a, 0x56a5, 0x472c,
		0x75b7, 0x643e, 0x9cc9, 0x8d40, 0xbfdb, 0xae52, 0xdaed, 0xcb64, 0xf9ff, 0xe876, 0x2102, 0x308b, 0x0210,
		0x1399, 0x6726, 0x76af, 0x4434, 0x55bd, 0xad4a, 0xbcc3, 0x8e58, 0x9fd1, 0xeb6e, 0xfae7, 0xc87c, 0xd9f5,
		0x3183, 0x200a, 0x1291, 0x0318, 0x77a7, 0x662e, 0x54b5, 0x453c, 0xbdcb, 0xac42, 0x9ed9, 0x8f50, 0xfbef,
		0xea66, 0xd8fd, 0xc974, 0x4204, 0x538d, 0x6116, 0x709f, 0x0420, 0x15a9, 0x2732, 0x36bb, 0xce4c, 0xdfc5,
		0xed5e, 0xfcd7, 0x8868, 0x99e1, 0xab7a, 0xbaf3, 0x5285, 0x430c, 0x7197, 0x601e, 0x14a1, 0x0528, 0x37b3,
		0x263a, 0xdecd, 0xcf44, 0xfddf, 0xec56, 0x98e9, 0x8960, 0xbbfb, 0xaa72, 0x6306, 0x728f, 0x4014, 0x519d,
		0x2522, 0x34ab, 0x0630, 0x17b9, 0xef4e, 0xfec7, 0xcc5c, 0xddd5, 0xa96a, 0xb8e3, 0x8a78, 0x9bf1, 0x7387,
		0x620e, 0x5095, 0x411c, 0x35a3, 0x242a, 0x16b1, 0x0738, 0xffcf, 0xee46, 0xdcdd, 0xcd54, 0xb9eb, 0xa862,
		0x9af9, 0x8b70, 0x8408, 0x9581, 0xa71a, 0xb693, 0xc22c, 0xd3a5, 0xe13e, 0xf0b7, 0x0840, 0x19c9, 0x2b52,
		0x3adb, 0x4e64, 0x5fed, 0x6d76, 0x7cff, 0x9489, 0x8500, 0xb79b, 0xa612, 0xd2ad, 0xc324, 0xf1bf, 0xe036,
		0x18c1, 0x0948, 0x3bd3, 0x2a5a, 0x5ee5, 0x4f6c, 0x7df7, 0x6c7e, 0xa50a, 0xb483, 0x8618, 0x9791, 0xe32e,
		0xf2a7, 0xc03c, 0xd1b5, 0x2942, 0x38cb, 0x0a50, 0x1bd9, 0x6f66, 0x7eef, 0x4c74, 0x5dfd, 0xb58b, 0xa402,
		0x9699, 0x8710, 0xf3af, 0xe226, 0xd0bd, 0xc134, 0x39c3, 0x284a, 0x1ad1, 0x0b58, 0x7fe7, 0x6e6e, 0x5cf5,
		0x4d7c, 0xc60c, 0xd785, 0xe51e, 0xf497, 0x8028, 0x91a1, 0xa33a, 0xb2b3, 0x4a44, 0x5bcd, 0x6956, 0x78df,
		0x0c60, 0x1de9, 0x2f72, 0x3efb, 0xd68d, 0xc704, 0xf59f, 0xe416, 0x90a9, 0x8120, 0xb3bb, 0xa232, 0x5ac5,
		0x4b4c, 0x79d7, 0x685e, 0x1ce1, 0x0d68, 0x3ff3, 0x2e7a, 0xe70e, 0xf687, 0xc41c, 0xd595, 0xa12a, 0xb0a3,
		0x8238, 0x93b1, 0x6b46, 0x7acf, 0x4854, 0x59dd, 0x2d62, 0x3ceb, 0x0e70, 0x1ff9, 0xf78f, 0xe606, 0xd49d,
		0xc514, 0xb1ab, 0xa022, 0x92b9, 0x8330, 0x7bc7, 0x6a4e, 0x58d5, 0x495c, 0x3de3, 0x2c6a, 0x1ef1, 0x0f78);
		
	my $crc=0xFFFF;
	my $a=substr($buff,0,-2);
	my $b=substr($buff,-2);
	my $crc2=OBIS_hex2int(uc(unpack('H*',$b)));
	foreach (split //, $a) {
		$crc = ($crc >> 8) ^ $crc16[($crc ^ ord($_)) & 0xff];
	}
	$crc ^= 0xffff;
    $crc = (($crc & 0xff) << 8) | (($crc & 0xff00) >> 8);
	return $crc2==$crc ? 1 : 0;
  }
 
  

###############################################
# Input: Whole Datastream, inkl. TL-Byte      #
# Output: Length, Type, Value, remaining Data #
###############################################
sub OBIS_decodeTL($){
	my ($msg)=@_;
	my $msgLength=0;
	my $msgType=0;
	my $lt="";
	$msgType  =hex(substr($msg,0,2)) & 0b01110000;
	do {
		$lt=hex(substr($msg,0,2));
		$msg=substr($msg,2);
		$msgLength=($msgLength*16) + ($lt & 0b00001111);
	} while ($lt & 0b10000000);
	$msgLength-=1;
	my $valu=substr($msg,0,$msgLength*2);
	$msg=substr($msg,$msgLength*2);
	return $msgLength,$msgType,$valu,$msg;
}

"Cogito, ergo sum.";

=pod
=item device
=begin html

<a name="OBIS"></a>
<h3>OBIS</h3>
  This module is for SmartMeters, that report their data in OBIS-Standard. It dosen't matter, wether the data comes as PlainText or SML-encoded.
  <br>
  <b>Define</b>
    <code>define &lt;name&gt; OBIS device|none [MeterType] </code><br>
    <br>
      &lt;device&gt; specifies the serial port to communicate with the smartmeter.
      Normally on Linux the device will be named /dev/ttyUSBx, where x is a number.
      For example /dev/ttyUSB0. You may specify the baudrate used after the @ char.<br>
      <br><br>
      Optional:MeterType can be of
      <ul><li>VSM102 -&gt; Voltcraft VSM102</li>
      <li>E110 -&gt; Landis&&;Gyr E110</li>
      <li>Standard -&gt; Data comes as plainText</li>
      <li>SML -&gt; Smart Message Language</li></ul>
      <br>
      Example: <br>
    <code>define myPowerMeter OBIS /dev/ttyPlugwise@@9600,7,E,1 VSM102</code>
      <br>
    <br>
 
  <b>Attributes</b>
  <ul><li>
    <code>offset_feed <br>offset_energy</code><br>
      If your smartmeter is BEHIND the meter of your powersupplier, then you can hereby adjust
      the total-reading of your SM to that of your official one.
      <br><br>
      </li>
      <li>
   <code>channels</code><br>
      With this, you can adjust the reported channels.
      OBIS-Standard is 
      <ul>
      <li>1-->Sum of all phases</li>
      <li>21-->Phase 1</li>
      <li>41-->Phase 2</li> 
      <li>61-->Phase 3</li></ul>
      You can change that for example to:
      <code>attr myOBIS channels {"2"=>"L1", "4"=>"L2", "6"=>"L3"}</code>
      <br><br></li>
      <li><code>directions</code><br>
      Some Meters report feeding/comnsuming of power in a statusword.
      If this is set, you get an extra reading dir_total_consumption which defaults to "in" and "out"
      Here, you can change this text with:
      <code>attr myOBIS directions {">" => "pwr consuming", "<"=>"pwr feeding"}</code>
      </li>
      <li>
   <code>interval</code><br>
      The polling-interval in seconds 
      </li>
      <li>
   <code>alignTime</code><br>
      Aligns the intervals to a given time. Each interval is repeatedly calculated.
      So if alignTime=00:00 and interval=600 aligns the interval to xx:00:00, xx:10:00, xx:20:00 etc....  
   <code>pollingMode</code><br>
      Changes from direct-read to polling-mode.
      Useful with meters, that send a continous datastream. 
      Reduces CPU-load.  
   <code>unitReadings</code><br>
      Adds the units to the readings like w, wH, A etc.  
      </li>
      
  <br>
</ul>

=end html

=begin html_DE

<a name="OBIS"></a>
<h3>OBIS</h3>
  Modul für Smartmeter, die ihre Daten im OBIS-Standard senden. Hierbei ist es egal, ob die Daten als reiner Text oder aber SML-kodiert kommen.
  <br>
  <b>Define</b>
    <code>define &lt;name&gt; OBIS device|none [MeterType] </code><br>
    <br>
      &lt;device&gt; gibt den seriellen Port an.
      <br><br>
      Optional:MeterType kann sein:
      <ul><li>VSM102 -&gt; Voltcraft VSM102</li>
      <li>E110 -&gt; Landis&&;Gyr E110</li>
      <li>Standard -&gt; Daten kommen als plainText</li>
      <li>SML -&gt; Smart Message Language</li></ul>
      <br>
      Beispiel: <br>
    <code>define myPowerMeter OBIS /dev/ttyPlugwise@@9600,7,E,1 VSM102</code>
      <br>
    <br>
 
  <b>Attribute</b>
  <ul><li>
    <code>offset_feed <br>offset_energy</code><br>
      Wenn das Smartmeter hinter einem Zähler des EVU's sitzt, kann hiermit der Zähler des
      Smartmeters an den des EVU's angepasst werden.
      <br><br>
      </li>
      <li>
   <code>channels</code><br>
      Hiermit können die einzelnen Kanal-Readings angepasst werden.
      OBIS-Standard ist 
      <ul>
      <li>1-->Summe aller Phasen</li>
      <li>21-->Phase 1</li>
      <li>41-->Phase 2</li> 
      <li>61-->Phase 3</li></ul>
      Beispiel:
      <code>attr myOBIS channels {"2"=>"L1", "4"=>"L2", "6"=>"L3"}></code>
      <br><br>
      </li>
      <li><code>directions</code><br>
      Manche SmartMeter senden im Statusbyte die Stromrichtung.
      In diesem Fall gibt es ein extra Reading "dir_total_consumption" welches standardmäßig "in" and "out" beinhaltet
      Hiermit kann dieser Text geändert werden:
      <code>attr myOBIS directions {">" => "pwr consuming", "<"=>"pwr feeding"}</code>
      </li><li>
   <code>interval</code><br>
      Abrufinterval der Daten. 
      </li><li>
   <code>algignTime</code><br>
      Richtet den Zeitpunkt von <interval> nach einer bestimmten Uhrzeit aus. 
      </li><li>
   <code>pollingMode</code><br>
      Hiermit wird von Direktbenachrichtigung auf Polling umgestellt.
      Bei Smartmetern, welche von selbst im Sekundentakt senden,
      kann das zu einer spürbaren Senkung der Prozessorleistung führen.  
   <code>unitReadings</code><br>
      Hängt bei den Readings auch die Einheiten an, zB w, wH, A usw.  
      </li>
  <br>
</ul>

=end html_DE

=cut
