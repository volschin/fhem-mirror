##############################################
package main;

use strict;
use warnings;

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

use Device::Firmata::Constants qw/ :all /;
use Device::Firmata::IO;
use Device::Firmata::Protocol;
use Device::Firmata::Platform;

sub FRM_Set($@);
sub FRM_Attr(@);

my %sets = (
  "reset" => "",
  "reinit" => ""
);

my %gets = (
  "firmware" => "",
  "version"   => ""
);

#####################################
sub FRM_Initialize($) {
	my $hash = shift @_;
	
	require "$main::attr{global}{modpath}/FHEM/DevIo.pm";

	# Provider
	$hash->{Clients} = ":FRM_IN:FRM_OUT:FRM_AD:FRM_PWM:FRM_I2C:FRM_SERVO:OWX:FRM_LCD:";
	$hash->{ReadyFn} = "FRM_Ready";  
	$hash->{ReadFn}  = "FRM_Read";

	# Consumer
	$hash->{DefFn}    = "FRM_Define";
	$hash->{UndefFn}  = "FRM_Undef";
	$hash->{GetFn}    = "FRM_Get";
	$hash->{SetFn}    = "FRM_Set";
	$hash->{AttrFn}   = "FRM_Attr";
  
	$hash->{AttrList} = "model:nano dummy:1,0 loglevel:0,1,2,3,4,5,6 sampling-interval i2c-config $main::readingFnAttributes";
}

#####################################
sub FRM_Define($$) {
	my ( $hash, $def ) = @_;

	my ($name, $type, $dev, $global) = split("[ \t]+", $def);

	my $isServer = 1 if($dev && $dev =~ m/^(IPV6:)?\d+$/);
#	my $isClient = 1 if($dev && $dev =~ m/^(IPV6:)?.*:\d+$/);

#	return "Usage: define <name> FRM {<device>[@<baudrate>] | [IPV6:]<tcp-portnr> [global]}"
#		if(!($isServer || $isClient) ||
#			($isClient && $global) ||
#			($global && $global ne "global"));

	# Make sure that fhem only runs once
	if($isServer) {
		my $ret = TcpServer_Open($hash, $dev, $global);
		if (!$ret) {
			$hash->{STATE}="listening";
		}
		return $ret;
	}

	DevIo_CloseDev($hash);	

	if ( $dev eq "none" ) {
		Log (GetLogLevel($hash->{NAME}), "FRM device is none, commands will be echoed only");
		$main::attr{$name}{dummy} = 1;
		return undef;
	}
	$hash->{DeviceName} = $dev;
	
	my $ret = DevIo_OpenDev($hash, 0, "FRM_DoInit");
	return $ret if (defined $ret and $ret eq "");
	$hash->{STATE}="Initialized";
	return $ret;	
}

#####################################
sub FRM_Undef($) {
	my $hash = shift;
	FRM_forall_clients($hash,\&FRM_Client_Unassign,undef);
	if (defined $hash->{DeviceName}) {
		DevIo_Disconnected($hash);
	};
	my $device = $hash->{FirmataDevice};
	if (defined $device) {
		if (defined $device->{io}) {
			delete $hash->{FirmataDevice}->{io}->{handle} if defined $hash->{FirmataDevice}->{io}->{handle};
			delete $hash->{FirmataDevice}->{io};
		}
		delete $device->{protocol} if defined $device->{protocol};
		delete $hash->{FirmataDevice};
	}
	return undef;
}

#####################################
sub FRM_Set($@) {
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));
  my $command = $a[1];
  my $value = $a[2];

  COMMAND_HANDLER: {
    $command eq "reset" and do {
  		DevIo_CloseDev($hash);	
		  return DevIo_OpenDev($hash, 0, "FRM_DoInit");
    };
    $command eq "reinit" and do {
			FRM_forall_clients($hash,\&FRM_Init_Client,undef);
			last;
    };
	}
	return undef;
}

#####################################
sub FRM_Get($@) {
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %gets)
  	if(!defined($gets{$a[1]}));
  my $name = shift @a;
  my $cmd = shift @a;
  ARGUMENT_HANDLER: {
    $cmd eq "firmware" and do {
      if (defined $hash->{FirmataDevice}) {
        return $hash->{FirmataDevice}->{metadata}->{firmware};
      } else {
        return "not connected to FirmataDevice";
      }
		};
		$cmd eq "version" and do {
  		if (defined $hash->{FirmataDevice}) {
  		  return $hash->{FirmataDevice}->{metadata}->{firmware_version};
  		} else {
  		  return "not connected to FirmataDevice";
		  }
		};
	}
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data

sub FRM_Read($) {

	my ( $hash ) = @_;
	if($hash->{SERVERSOCKET}) {   # Accept and create a child
		my $chash = TcpServer_Accept($hash, "FRM");
		return if(!$chash);
		$chash->{DeviceName}=$hash->{PORT}; # required for DevIo_CloseDev and FRM_Ready
		$chash->{TCPDev}=$chash->{CD};
		FRM_DoInit($chash);
		return;
	}
	my $device = $hash->{FirmataDevice} or return;
	$device->poll();
}

sub FRM_Ready($) {

	my ($hash) = @_;
	my $name = $hash->{NAME};
	if ($name=~/^^FRM:.+:\d+$/) { # this is a closed tcp-connection, remove it
		TcpServer_Close($hash);
		delete $main::defs{$hash->{SNAME}}{FirmataDevice} if (defined $hash->{SNAME} && defined $main::defs{$hash->{SNAME}}{FirmataDevice});
		my $dev = $hash->{DeviceName};
		delete $main::readyfnlist{"$name.$dev"};
  		delete $main::attr{$name};
  		delete $main::defs{$name};		
		return undef;
	}
	return DevIo_OpenDev($hash, 1, "FRM_DoInit") if($hash->{STATE} eq "disconnected");
	
	# This is relevant for windows/USB only
	my $po = $hash->{USBDev};
	my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
	if($po) {
		($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
	}
	return ($InBytes && $InBytes>0);
}

sub FRM_Attr(@) {
	my ($command,$name,$attribute,$value) = @_;
	if ($command eq "set") {
		$main::attr{$name}{$attribute}=$value;
		if ($attribute eq "sampling-interval" 
			or $attribute eq "i2c-config" 
			or $attribute eq "loglevel" ) {
			FRM_apply_attribute($main::defs{$name},$attribute);
		}
	}
}

sub FRM_apply_attribute {
	my ($hash,$attribute) = @_;
	my $firmata = $hash->{FirmataDevice};
	my $name = $hash->{NAME};
	if (defined $firmata) {
		if ($attribute eq "sampling-interval") {
			$firmata->sampling_interval(AttrVal($name,$attribute,"1000"));
		} elsif ($attribute eq "i2c-config") {
			my $i2cattr = AttrVal($name,$attribute,undef);
			if (defined $i2cattr) {
				my @a = split(" ", $i2cattr);
				my $i2cpins = $firmata->{metadata}{i2c_pins};
				my $err; 
				if (defined $i2cpins and scalar @$i2cpins) {
					eval {
						foreach my $i2cpin (@$i2cpins) {
							$firmata->pin_mode($i2cpin,PIN_I2C);
						}
						$firmata->i2c_config(@a);
						$firmata->observe_i2c(\&FRM_i2c_observer,$hash);
					};
					$err = $@ if ($@);	
				} else {
					$err = "Error, arduino doesn't support I2C";
				}
				Log (GetLogLevel($hash->{NAME},2),$err) if ($err);
			}
		} elsif ($attribute eq "loglevel") {
			if (defined $firmata->{io}) {
				$firmata->{io}->{loglevel} = AttrVal($name,$attribute,5);
			}
		}
	}
}

sub FRM_DoInit($) {
	
	my ($hash) = @_;
	
	my $name = $hash->{SNAME}; #is this a serversocket-connection?
	my $shash = defined $name ? $main::defs{$name} : $hash;
	$name = $hash->{NAME} if (!defined $name);
	
  	my $firmata_io = Firmata_IO->new($hash);
	my $device = Device::Firmata::Platform->attach($firmata_io) or return 1;

	$hash->{FirmataDevice} = $device;
	$device->observe_string(\&FRM_string_observer,$hash);
	
	my $found; # we cannot call $device->probe() here, as it doesn't select bevore read, so it would likely cause IODev to close the connection on the first attempt to read from empty stream
	my $endTicks = time+5;
	my $queryTicks = time+2;
	$device->system_reset();
	do {
		FRM_poll($hash);
		if ($device->{metadata}{firmware} && $device->{metadata}{firmware_version}) {
			$device->{protocol}->{protocol_version} = $device->{metadata}{firmware_version};
			$main::defs{$name}{firmware} = $device->{metadata}{firmware};
			$main::defs{$name}{firmware_version} = $device->{metadata}{firmware_version};
			Log (3, "Firmata Firmware Version: ".$device->{metadata}{firmware}." ".$device->{metadata}{firmware_version});
			$device->analog_mapping_query();
			$device->capability_query();
			do {
				FRM_poll($hash);
				if ($device->{metadata}{analog_mappings} and $device->{metadata}{capabilities}) {
					my $inputpins = $device->{metadata}{input_pins};
					$main::defs{$name}{input_pins} = join(",", sort{$a<=>$b}(@$inputpins)) if (defined $inputpins and scalar @$inputpins);
					my $outputpins = $device->{metadata}{output_pins};
					$main::defs{$name}{output_pins} =  join(",", sort{$a<=>$b}(@$outputpins)) if (defined $outputpins and scalar @$outputpins);
					my $analogpins = $device->{metadata}{analog_pins};
					$main::defs{$name}{analog_pins} = join(",", sort{$a<=>$b}(@$analogpins)) if (defined $analogpins and scalar @$analogpins);
					my $pwmpins = $device->{metadata}{pwm_pins};
					$main::defs{$name}{pwm_pins} = join(",", sort{$a<=>$b}(@$pwmpins)) if (defined $pwmpins and scalar @$pwmpins);
					my $servopins = $device->{metadata}{servo_pins};
					$main::defs{$name}{servo_pins} = join(",", sort{$a<=>$b}(@$servopins)) if (defined $servopins and scalar @$servopins);
					my $i2cpins = $device->{metadata}{i2c_pins};
					$main::defs{$name}{i2c_pins} = join(",", sort{$a<=>$b}(@$i2cpins)) if (defined $i2cpins and scalar @$i2cpins);
					my $onewirepins = $device->{metadata}{onewire_pins};
					$main::defs{$name}{onewire_pins} = join(",", sort{$a<=>$b}(@$onewirepins)) if (defined $onewirepins and scalar @$onewirepins);
					if (defined $device->{metadata}{analog_resolutions}) {
						my @analog_resolutions;
						foreach my $pin (sort{$a<=>$b}(keys %{$device->{metadata}{analog_resolutions}})) {
							push @analog_resolutions,$pin.":".$device->{metadata}{analog_resolutions}{$pin};
						}
						$main::defs{$name}{analog_resolutions} = join(",",@analog_resolutions) if (scalar @analog_resolutions);
					}
					if (defined $device->{metadata}{pwm_resolutions}) {
						my @pwm_resolutions;
						foreach my $pin (sort{$a<=>$b}(keys %{$device->{metadata}{pwm_resolutions}})) {
							push @pwm_resolutions,$pin.":".$device->{metadata}{pwm_resolutions}{$pin};
						}
						$main::defs{$name}{pwm_resolutions} = join(",",@pwm_resolutions) if (scalar @pwm_resolutions);
					}
					if (defined $device->{metadata}{servo_resolutions}) {
						my @servo_resolutions;
						foreach my $pin (sort{$a<=>$b}(keys %{$device->{metadata}{servo_resolutions}})) {
							push @servo_resolutions,$pin.":".$device->{metadata}{servo_resolutions}{$pin};
						}
						$main::defs{$name}{servo_resolutions} = join(",",@servo_resolutions) if (scalar @servo_resolutions);
					}
					$found = 1;
				} else {
					select (undef,undef,undef,0.01);
				} 
			} while (time < $endTicks and !$found);
			$found = 1;
		} else {
			select (undef,undef,undef,0.01);
			if (time > $queryTicks) {
				Log (3, "querying Firmata Firmware Version");
				$device->firmware_version_query();
				$queryTicks++;
			}
		}
	} while (time < $endTicks and !$found);
	if ($found) {
		$shash->{FirmataDevice} = $device;
		FRM_apply_attribute($shash,"sampling-interval");
		FRM_apply_attribute($shash,"i2c-config");
		FRM_forall_clients($shash,\&FRM_Init_Client,undef);
		return undef;
	}
	Log (3, "no response from Firmata, closing DevIO");
	DevIo_Disconnected($hash);
	delete $hash->{FirmataDevice};
	return "FirmataDevice not responding";
}

sub
FRM_forall_clients($$$)
{
  my ($hash,$fn,$args) = @_;
  foreach my $d ( sort keys %main::defs ) {
    if (   defined( $main::defs{$d} )
      && defined( $main::defs{$d}{IODev} )
      && $main::defs{$d}{IODev} == $hash ) {
      	&$fn($main::defs{$d},$args);
    }
  }
  return undef;
}

sub
FRM_Init_Client($$) {
	my ($hash,$args) = @_;
	if (!defined $args and defined $hash->{DEF}) {
  		my @a = split("[ \t][ \t]*", $hash->{DEF});
  		$args = \@a;
	}
	my $ret = CallFn($hash->{NAME},"InitFn",$hash,$args);
	if ($ret) {
		Log (GetLogLevel($hash->{NAME},2),"error initializing ".$hash->{NAME}.": ".$ret);
	}
}

sub
FRM_Init_Pin_Client($$$) {
	my ($hash,$args,$mode) = @_;
	my $u = "wrong syntax: define <name> FRM_XXX pin";
  	return $u unless defined $args and int(@$args) > 0;
 	my $pin = @$args[0];
  	$hash->{PIN} = $pin;
  eval {
    FRM_Client_FirmataDevice($hash)->pin_mode($pin,$mode);
	};
	if ($@) {
		main::Log(2,"FRM_Init error setting pin_mode: ".$@);
		#FRM_Client_Unassign($hash);
		return "error setting ".$hash->{NAME}." pin_mode for pin ".$pin;
	}
	return undef;
}

sub
FRM_Client_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  $hash->{STATE}="defined";
  
  AssignIoPort($hash);
  FRM_Init_Client($hash,[@a[2..scalar(@a)-1]]);
    
  return undef;
}

sub
FRM_Client_Undef($$)
{
  my ($hash, $name) = @_;
}

sub
FRM_Client_Unassign($)
{
  my ($dev) = @_;
  delete $dev->{IODev} if defined $dev->{IODev};
  $dev->{STATE}="defined";  
}

sub FRM_Client_FirmataDevice($) {
  my $hash = shift;
  my $iodev = $hash->{IODev};
  die $hash->{NAME}." no IODev assigned" unless defined $iodev;
  die $hash->{NAME}.", ".$iodev->{NAME}." is not connected" unless (defined $iodev->{FirmataDevice} and (defined $iodev->{FD} or ($^O=~/Win/ and defined $iodev->{USBDev})));
  return $iodev->{FirmataDevice};
}

package Firmata_IO;

sub new {
	my ($class,$hash) = @_;
	return bless {
		hash => $hash,
		loglevel => main::GetLogLevel($hash->{NAME},5),
	}, $class;
}

sub data_write {
   	my ( $self, $buf ) = @_;
    main::Log ($self->{loglevel}, ">".join(",",map{sprintf"%02x",ord$_}split//,$buf));
   	main::DevIo_SimpleWrite($self->{hash},$buf,undef);
}

sub data_read {
    my ( $self, $bytes ) = @_;
    my $string = main::DevIo_SimpleRead($self->{hash});
    if (defined $string ) {
   	    main::Log ($self->{loglevel},"<".join(",",map{sprintf"%02x",ord$_}split//,$string));
   	}
    return $string;
}

package main;

sub
FRM_i2c_observer
{
	my ($data,$hash) = @_;
	Log GetLogLevel($hash->{NAME},5),"onI2CMessage address: '".$data->{address}."', register: '".$data->{register}."' data: '".$data->{data}."'";
	FRM_forall_clients($hash,\&FRM_i2c_update_device,$data);
}

sub FRM_i2c_update_device
{
	my ($hash,$data) = @_;
	if (defined $hash->{"i2c-address"} && $hash->{"i2c-address"}==$data->{address}) {
		my $replydata = $data->{data};
		my @values = split(" ",ReadingsVal($hash->{NAME},"values",""));
		splice(@values,$data->{register},@$replydata, @$replydata);
		readingsBeginUpdate($hash);
		$hash->{STATE}="active";
		readingsBulkUpdate($hash,"values",join (" ",@values),1);
		readingsEndUpdate($hash,1);
	}
}

sub FRM_string_observer
{
	my ($string,$hash) = @_;
	Log (GetLogLevel($hash->{NAME},3), "received String_data: ".$string);
	readingsSingleUpdate($hash,"error",$string,1);
}

sub FRM_poll
{
	my ($hash) = @_;
	if (defined $hash->{FD}) {
		my ($rout, $rin) = ('', '');
    	vec($rin, $hash->{FD}, 1) = 1;
    	my $nfound = select($rout=$rin, undef, undef, 0.1);
    	my $mfound = vec($rout, $hash->{FD}, 1); 
		if($mfound && defined $hash->{FirmataDevice}) {
			$hash->{FirmataDevice}->poll();
		}
		return $mfound;
	} else {
		# This is relevant for windows/USB only
  		my $po = $hash->{USBDev};
  		my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  		if($po) {
  			($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  		}
  		if ($InBytes && $InBytes>0 && defined $hash->{FirmataDevice}) {
			$hash->{FirmataDevice}->poll();
  		}
	}
}

######### following is code to be called from OWX: ##########

sub
FRM_OWX_Init($$)
{
	my ($hash,$args) = @_;
	my $ret = FRM_Init_Pin_Client($hash,$args,PIN_ONEWIRE);
	return $ret if (defined $ret);
	my $firmata = $hash->{IODev}->{FirmataDevice};
	my $pin = $hash->{PIN};
	$hash->{FRM_OWX_CORRELATIONID} = 0;
	$firmata->observe_onewire($pin,\&FRM_OWX_observer,$hash);
	$hash->{FRM_OWX_REPLIES} = {};
	$hash->{DEVS} = [];
	if ( AttrVal($hash->{NAME},"buspower","") eq "parasitic" ) {
		$firmata->onewire_config($pin,1);
	}
	$hash->{STATE}="Initialized";
	$firmata->onewire_search($pin);
	return undef;
}

sub FRM_OWX_observer
{
	my ( $data,$hash ) = @_;
	my $command = $data->{command};
	COMMAND_HANDLER: {
		$command eq "READ_REPLY" and do {
			my $id = $data->{id};
			my $request = (defined $id) ? $hash->{FRM_OWX_REQUESTS}->{$id} : undef;
			unless (defined $request) {
				return unless (defined $data->{device});
				my $owx_device = FRM_OWX_firmata_to_device($data->{device});
				my %requests = %{$hash->{FRM_OWX_REQUESTS}};
				foreach my $key (keys %requests) {
					if ($requests{$key}->{device} eq $owx_device) {
						$request = $requests{$key};
						$id = $key;
						last;
					};
				};
			};
			return unless (defined $request);
			my $owx_data = pack "C*",@{$data->{data}};
			my $owx_device = $request->{device};
			$hash->{FRM_OWX_REPLIES}->{$owx_device} = $owx_data;
			delete $hash->{FRM_OWX_REQUESTS}->{$id};
			last;			
		};
		($command eq "SEARCH_REPLY" or $command eq "SEARCH_ALARMS_REPLY") and do {
			my @owx_devices = ();
			foreach my $device (@{$data->{devices}}) {
				push @owx_devices, FRM_OWX_firmata_to_device($device);
			}
			if ($command eq "SEARCH_REPLY") {
				$hash->{DEVS} = \@owx_devices;
				#$main::attr{$hash->{NAME}}{"ow-devices"} = join " ",@owx_devices;
			} else {
				$hash->{ALARMDEVS} = \@owx_devices;
			}
			last;
		};
	}
}

########### functions implementing interface to OWX ##########

sub FRM_OWX_device_to_firmata
{
	my @device;
	foreach my $hbyte (unpack "A2xA2A2A2A2A2A2xA2", shift) {
		push @device, hex $hbyte;
	}
	return {
		family => shift @device,
		crc => pop @device,
		identity => \@device,
	}
}

sub FRM_OWX_firmata_to_device
{
	my $device = shift;
	return sprintf ("%02X.%02X%02X%02X%02X%02X%02X.%02X",$device->{family},@{$device->{identity}},$device->{crc});
}

sub FRM_OWX_Verify {
	my ($hash,$dev) = @_;
	foreach my $found ($hash->{DEVS}) {
		if ($dev eq $found) {
			return 1;
		}
	}
	return 0;
}

sub FRM_OWX_Alarms {
	my ($hash) = @_;

	#-- get the interface
	my $frm = $hash->{IODev};
	return 0 unless defined $frm;
	my $firmata = $frm->{FirmataDevice};
	my $pin     = $hash->{PIN};
	return 0 unless ( defined $firmata and defined $pin );
	$hash->{ALARMDEVS} = undef;			
	$firmata->onewire_search_alarms($hash->{PIN});
	my $times = AttrVal($hash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec
	for (my $i=0;$i<$times;$i++) {
		if (FRM_poll($hash->{IODev})) {
			if (defined $hash->{ALARMDEVS}) {
				return 1;
			}
		} else {
			select (undef,undef,undef,0.05);
		}
	}
	$hash->{ALARMDEVS} = [];
	return 1;
}

sub FRM_OWX_Reset {
	my ($hash) = @_;
	#-- get the interface
	my $frm = $hash->{IODev};
	return undef unless defined $frm;
	my $firmata = $frm->{FirmataDevice};
	my $pin     = $hash->{PIN};
	return undef unless ( defined $firmata and defined $pin );

	$firmata->onewire_reset($pin);
	
	return 1;
}

sub FRM_OWX_Complex ($$$$) {
	my ( $hash, $owx_dev, $data, $numread ) = @_;

	my $res = "";

	#-- get the interface
	my $frm = $hash->{IODev};
	return 0 unless defined $frm;
	my $firmata = $frm->{FirmataDevice};
	my $pin     = $hash->{PIN};
	return 0 unless ( defined $firmata and defined $pin );

	my $ow_command = {};

	#-- has match ROM part
	if ($owx_dev) {
		$ow_command->{"select"} = FRM_OWX_device_to_firmata($owx_dev);

		#-- padding first 9 bytes into result string, since we have this
		#   in the serial interfaces as well
		$res .= "000000000";
	}

	#-- has data part
	if ($data) {
		my @data = unpack "C*", $data;
		$ow_command->{"write"} = \@data;
		$res.=$data;
	}

	#-- has receive part
	if ( $numread > 0 ) {
		$ow_command->{"read"} = $numread;
		#Firmata sends 0-address on read after skip
		$owx_dev = '00.000000000000.00' unless defined $owx_dev;
		my $id = $hash->{FRM_OWX_CORRELATIONID};
		$ow_command->{"id"} = $hash->{FRM_OWX_CORRELATIONID};
		$hash->{FRM_OWX_REQUESTS}->{$id} = {
			command => $ow_command,
			device => $owx_dev
		};
		delete $hash->{FRM_OWX_REPLIES}->{$owx_dev};		
		$hash->{FRM_OWX_CORRELATIONID} = ($id + 1) & 0xFFFF;
	}

	$firmata->onewire_command_series( $pin, $ow_command );
	
	if ($numread) {
		my $times = AttrVal($hash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec
		for (my $i=0;$i<$times;$i++) {
			if (FRM_poll($hash->{IODev})) {
				if (defined $hash->{FRM_OWX_REPLIES}->{$owx_dev}) {
					$res .= $hash->{FRM_OWX_REPLIES}->{$owx_dev};
					return $res;
				}
			} else {
				select (undef,undef,undef,0.05);
			}
		}
	}
	return $res;
}

########################################################################################
#
# OWX_Discover_FRM - Discover devices on the 1-Wire bus via internal firmware
#
# Parameter hash = hash of bus master
#
# Return 0  : error
#        1  : OK
#
########################################################################################

sub FRM_OWX_Discover ($) {

	my ($hash) = @_;

	#-- get the interface
	my $frm = $hash->{IODev};
	return 0 unless defined $frm;
	my $firmata = $frm->{FirmataDevice};
	my $pin     = $hash->{PIN};
	return 0 unless ( defined $firmata and defined $pin );
	my $old_devices = $hash->{DEVS};
	$hash->{DEVS} = undef;			
	$firmata->onewire_search($hash->{PIN});
	my $times = AttrVal($hash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec
	for (my $i=0;$i<$times;$i++) {
		if (FRM_poll($hash->{IODev})) {
			if (defined $hash->{DEVS}) {
				return 1;
			}
		} else {
			select (undef,undef,undef,0.05);
		}
	}
	$hash->{DEVS} = $old_devices;
	return 1;
}

1;

=pod
=begin html

<a name="FRM"></a>
<h3>FRM</h3>
<ul>
  connects fhem to <a href="http://www.arduino.cc">Arduino</a> using
  the <a href="http://www.firmata.org">Firmata</a> protocol. 
  <br><br>
  A single FRM device can serve multiple FRM-clients.<br><br>
  Clients of FRM are:<br><br>
  <a href="#FRM_IN">FRM_IN</a> for digital input<br>
  <a href="#FRM_OUT">FRM_OUT</a> for digital out<br>
  <a href="#FRM_AD">FRM_AD</a> for analog input<br>
  <a href="#FRM_PWM">FRM_PWM</a> for analog (pulse_width_modulated) output<br>
  <a href="#FRM_I2C">FRM_I2C</a> to read data from integrated circutes attached
   to Arduino supporting the <a href="http://en.wikipedia.org/wiki/I%C2%B2C">
   i2c-protocol</a>.<br><br>
   
  Each client stands for a Pin of the Arduino configured for a specific use 
  (digital/analog in/out) or an integrated circuit connected to Arduino by i2c.<br><br>
  
  Note: this module requires the <a href="https://github.com/amimoto/perl-firmata">Device::Firmata</a> module (perl-firmata).
  You can download it <a href="https://github.com/amimoto/perl-firmata/archive/master.zip">as a single zip</a> file from github.
  Copy 'lib/Device' (with all subdirectories) to e.g. FHEM directory (or other location within perl include path)<br><br>

  Note: this module may require the Device::SerialPort or Win32::SerialPort
  module if you attach the device via USB and the OS sets strange default
  parameters for serial devices.<br><br>
  
  <a name="FRMdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM {&lt;device&gt; | &lt;port&gt; [global]}</code> <br>
  Specifies the FRM device.   </ul>
  
    <br>
    <ul>
    USB-connected devices:<br><ul>
      &lt;device&gt; specifies the serial port to communicate with the Arduino.
      The name of the serial-device depends on your distribution, under
      linux the cdc_acm kernel module is responsible, and usually a
      /dev/ttyACM0 device will be created. If your distribution does not have a
      cdc_acm module, you can force usbserial to handle the Arduino by the
      following command:<ul>modprobe usbserial vendor=0x03eb
      product=0x204b</ul>In this case the device is most probably
      /dev/ttyUSB0.<br><br>

      You can also specify a baudrate if the device name contains the @
      character, e.g.: /dev/ttyACM0@38400<br><br>

      If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
      perl module Device::SerialPort is not needed, and fhem opens the device
      with simple file io. This might work if the operating system uses sane
      defaults for the serial parameters, e.g. some Linux distributions and
      OSX.  <br><br>
      
      The Arduino has to run 'StandardFirmata'. You can find StandardFirmata
      in the Arduino-IDE under 'Examples->Firmata->StandardFirmata<br><br>

    </ul>
    Network-connected devices:<br><ul>
    &lt;port&gt; specifies the port the FRM device listens on. If 'global' is
    specified the socket is bound to all local ip-addresses, otherwise to localhost
    only.<br>
    The Arduino must run a Version of firmata that connects in client-mode (the
    connection is initiated by the arduino). The ip-address and port of the fhem-server
    has to be configured an the arduino, so it knows where to connect to.<br>
    As of now only a single Arduino per FRM-device configured is supported. Multiple
    Arduinos may connect to different FRM-devices configured for different ports.<br>
    The support for Firmata over ethernet is still experimental. Firmata-ethenet-client
    can be found here: 
    <a href="https://github.com/ntruchsess/arduino/blob/configurable_ethernet/examples/ConfigurableEthernetclient/ConfigurableEthernetclient.ino">
    ConfigurableEthernetclient.ino</a><br>
    </ul>
    <br>
    If the device is called none, then no device will be opened, so you
    can experiment without hardware attached.<br>
  </ul>
  
  <br>
  <a name="FRMset"></a>
  <b>Set</b>
  <ul>
  N/A<br>
  </ul><br>
  <a name="FRMattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>i2c-config<br>
      Configure the arduino for ic2 communication. This will enable i2c on the
      i2c_pins received by the capability-query issued during initialization of FRM.<br>
      As of Firmata 2.3 you can set a delay-time (in microseconds) that will be inserted into i2c
      protocol when switching from write to read.<br>
      See: <a href="http://www.firmata.org/wiki/Protocol#I2C">Firmata Protocol details about I2C</a><br>
      </li><br>
      <li>sampling-interval<br>
      Configure the interval Firmata reports data to FRM. Unit is milliseconds.<br>
      See: <a href="http://www.firmata.org/wiki/Protocol#Sampling_Interval">Firmata Protocol details about Sampling Interval</a></br>
      </li>
    </ul>
  </ul>
<br>

=end html
=cut
