######################################################################
#
#  88_HMCCUDEV.pm
#
#  $Id: 88_HMCCUDEV.pm 18552 2019-02-10 11:52:28Z zap $
#
#  Version 4.4.016
#
#  (c) 2020 zap (zap01 <at> t-online <dot> de)
#
######################################################################
#  Client device for Homematic devices.
#  Requires module 88_HMCCU.pm
######################################################################

package main;

use strict;
use warnings;
use SetExtensions;

require "$attr{global}{modpath}/FHEM/88_HMCCU.pm";

sub HMCCUDEV_Initialize ($);
sub HMCCUDEV_Define ($@);
sub HMCCUDEV_InitDevice ($$);
sub HMCCUDEV_Undef ($$);
sub HMCCUDEV_Rename ($$);
sub HMCCUDEV_Set ($@);
sub HMCCUDEV_Get ($@);
sub HMCCUDEV_Attr ($@);

######################################################################
# Initialize module
######################################################################

sub HMCCUDEV_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "HMCCUDEV_Define";
	$hash->{UndefFn} = "HMCCUCHN_Undef";
	$hash->{RenameFn} = "HMCCUDEV_Rename";
	$hash->{SetFn} = "HMCCUDEV_Set";
	$hash->{GetFn} = "HMCCUDEV_Get";
	$hash->{AttrFn} = "HMCCUDEV_Attr";
	$hash->{parseParams} = 1;

	$hash->{AttrList} = "IODev ccuaggregate:textField-long ccucalculate:textField-long ". 
		"ccuflags:multiple-strict,ackState,logCommand,nochn0,noReadings,trace ccureadingfilter:textField-long ".
		"ccureadingformat:name,namelc,address,addresslc,datapoint,datapointlc ".
		"ccureadingname:textField-long ".
		"ccuget:State,Value ccuscaleval ccuSetOnChange ccuverify:0,1,2 disable:0,1 ".
		"hmstatevals:textField-long statevals substexcl substitute:textField-long statechannel ".
		"controlchannel statedatapoint controldatapoint stripnumber peer:textField-long ".
		$readingFnAttributes;
}

######################################################################
# Define device
######################################################################

sub HMCCUDEV_Define ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};
	
	my $usage = "Usage: define $name HMCCUDEV {device|'virtual'} [control-channel] ".
		"['readonly'] ['noDefaults'|'defaults'] [iodev={iodev-name}] [address={virtual-device-no}]".
		"[{groupexp=regexp|group={device|channel}[,...]]";
	return $usage if (scalar (@$a) < 3);
	
	my @errmsg = (
		"OK",
		"Invalid or unknown CCU device name or address",
		"Can't assign I/O device",
		"No devices in group",
		"No matching CCU devices found",
		"Type of virtual device not defined",
		"Device type not found",
		"Too many virtual devices"
	);

	my $devname = shift @$a;
	my $devtype = shift @$a;
	my $devspec = shift @$a;

	my $ioHash = undef;
	
# 	my $existDev = HMCCU_ExistsClientDevice ($devspec, $devtype);
# 	return "FHEM device $existDev for CCU device $devspec already exists" if (defined($existDev));

	# Store some definitions for delayed initialization
	$hash->{readonly} = 'no';
	$hash->{hmccu}{devspec}  = $devspec;
	$hash->{hmccu}{groupexp} = $h->{groupexp} if (exists ($h->{groupexp}));
	$hash->{hmccu}{group}    = $h->{group} if (exists ($h->{group}));

	if (exists ($h->{address})) {
		if ($init_done || $devspec ne 'virtual') {
			return "Option address not allowed";
		}
		else {
			$hash->{hmccu}{address}  = $h->{address};
		}
	}
	else {
		return "Option address not specified" if (!$init_done && $devspec eq 'virtual');
	}
	
	# Parse optional command line parameters
	foreach my $arg (@$a) {
		if    ($arg eq 'readonly') { $hash->{readonly} = 'yes'; }
		elsif (lc($arg) eq 'nodefaults' && $init_done) { $hash->{hmccu}{nodefaults} = 1; }
		elsif ($arg eq 'defaults' && $init_done) { $hash->{hmccu}{nodefaults} = 0; }
		elsif ($arg =~ /^[0-9]+$/) { $attr{$name}{controlchannel} = $arg; }
		else { return $usage; }
	}
	
	# IO device can be set by command line parameter iodev, otherwise try to detect IO device
	if (exists ($h->{iodev})) {
		return "Specified IO Device ".$h->{iodev}." does not exist" if (!exists ($defs{$h->{iodev}}));
		return "Specified IO Device ".$h->{iodev}." is not a HMCCU device"
			if ($defs{$h->{iodev}}->{TYPE} ne 'HMCCU');
		$ioHash = $defs{$h->{iodev}};
	}
	else {
		# The following call will fail for non virtual devices during FHEM start if CCU is not ready
		$ioHash = $devspec eq 'virtual' ? HMCCU_GetHash (0) : HMCCU_FindIODevice ($devspec);
	}

	if ($init_done) {
		# Interactive define command while CCU not ready
		if (!defined ($ioHash)) {
			my ($ccuactive, $ccuinactive) = HMCCU_IODeviceStates ();
			if ($ccuinactive > 0) {
				return "CCU and/or IO device not ready. Please try again later";
			}
			else {
				return "Cannot detect IO device";
			}
		}
	}
	else {
		# CCU not ready during FHEM start
		if (!defined ($ioHash) || $ioHash->{ccustate} ne 'active') {
			Log3 $name, 2, "HMCCUDEV: [$devname] Cannot detect IO device, maybe CCU not ready. Trying later ...";
#			readingsSingleUpdate ($hash, "state", "Pending", 1);
			$hash->{ccudevstate} = 'pending';
			return undef;
		}
	}

	# Initialize FHEM device, set IO device
	my $rc = HMCCUDEV_InitDevice ($ioHash, $hash);
	return $errmsg[$rc] if ($rc > 0);

	return undef;
}

######################################################################
# Initialization of FHEM device.
# Called during Define() or by HMCCU after CCU ready.
# Return 0 on successful initialization or >0 on error:
# 1 = Invalid channel name or address
# 2 = Cannot assign IO device
# 3 = No devices in group
# 4 = No matching CCU devices found
# 5 = Type of virtual device not defined
# 6 = Device type not found
# 7 = Too many virtual devices
######################################################################

sub HMCCUDEV_InitDevice ($$)
{
	my ($ioHash, $devHash) = @_;
	my $name = $devHash->{NAME};
	my $devspec = $devHash->{hmccu}{devspec};
	my $gdcount = 0;
	my $gdname = $devspec;

	if ($devspec eq 'virtual') {
		my $no = 0;
		if (exists ($devHash->{hmccu}{address})) {
			# Only true during FHEM start
			$no = $devHash->{hmccu}{address};
		}
		else {
			# Search for free address. Maximum of 10000 virtual devices allowed.
			for (my $i=1; $i<=10000; $i++) {
				my $va = sprintf ("VIR%07d", $i);
				if (!HMCCU_IsValidDevice ($ioHash, $va, 1)) {
					$no = $i;
					last;
				}
			}
			return 7 if ($no == 0);
			$devHash->{DEF} .= " address=$no";
		}

		# Inform HMCCU device about client device
		return 2 if (!HMCCU_AssignIODevice ($devHash, $ioHash->{NAME}, undef));

		$devHash->{ccuif}   = 'fhem';
		$devHash->{ccuaddr} = sprintf ("VIR%07d", $no);
		$devHash->{ccuname} = $name;
		$devHash->{ccudevstate} = 'active';
	}
	else {
		return 1 if (!HMCCU_IsValidDevice ($ioHash, $devspec, 7));

		my ($di, $da, $dn, $dt, $dc) = HMCCU_GetCCUDeviceParam ($ioHash, $devspec);
		return 1 if (!defined ($da));
		$gdname = $dn;

		# Inform HMCCU device about client device
		return 2 if (!HMCCU_AssignIODevice ($devHash, $ioHash->{NAME}, undef));

		$devHash->{ccuif}    = $di;
		$devHash->{ccuaddr}  = $da;
		$devHash->{ccuname}  = $dn;
		$devHash->{ccutype}  = $dt;
		$devHash->{ccudevstate} = 'active';
		$devHash->{hmccu}{channels} = $dc;

		if ($init_done) {
			# Interactive device definition
			HMCCU_AddDevice ($ioHash, $di, $da, $devHash->{NAME});
			HMCCU_UpdateDevice ($ioHash, $devHash);
			HMCCU_UpdateDeviceRoles ($ioHash, $devHash);
			if (!exists($devHash->{hmccu}{nodefaults}) || $devHash->{hmccu}{nodefaults} == 0) {
				if (!HMCCU_SetDefaultAttributes ($devHash)) {
					HMCCU_SetDefaults ($devHash);
				}
			}
			HMCCU_GetUpdate ($devHash, $da, 'Value');
		}
	}
	
	# Parse group options
	if ($devHash->{ccuif} eq 'VirtualDevices' || $devHash->{ccuif} eq 'fhem') {
		my @devlist = ();
		if (exists ($devHash->{hmccu}{groupexp})) {
			# Group devices specified by name expression
			$gdcount = HMCCU_GetMatchingDevices ($ioHash, $devHash->{hmccu}{groupexp}, 'dev', \@devlist);
			return 4 if ($gdcount == 0);
		}
		elsif (exists ($devHash->{hmccu}{group})) {
			# Group devices specified by comma separated name list
			my @gdevlist = split (",", $devHash->{hmccu}{group});
			$devHash->{ccugroup} = '' if (@gdevlist > 0);
			foreach my $gd (@gdevlist) {
				my ($gda, $gdc, $gdo) = ('', '', '', '');

				return 1 if (!HMCCU_IsValidDevice ($ioHash, $gd, 7));

				($gda, $gdc) = HMCCU_GetAddress ($ioHash, $gd, '', '');
				$gdo = $gda;
				$gdo .= ':'.$gdc if ($gdc ne '');
				push @devlist, $gdo;
				$gdcount++;
			}
		}
		else {
			# Group specified by CCU virtual group name
			@devlist = HMCCU_GetGroupMembers ($ioHash, $gdname);
			$gdcount = scalar (@devlist);
		}

		return 3 if ($gdcount == 0);
		
		$devHash->{ccugroup} = join (',', @devlist);
		if ($devspec eq 'virtual') {
			my $dev = shift @devlist;
			my $devtype = HMCCU_GetDeviceType ($ioHash, $dev, 'n/a');
			my $devna = $devtype eq 'n/a' ? 1 : 0;
			for my $d (@devlist) {
				if (HMCCU_GetDeviceType ($ioHash, $d, 'n/a') ne $devtype) {
					$devna = 1;
					last;
				}
			}
			
			my $rc = 0;
			if ($devna) {
				$devHash->{ccutype} = 'n/a';
				$devHash->{readonly} = 'yes';
				$rc = HMCCU_CreateDevice ($ioHash, $devHash->{ccuaddr}, $name, undef, $dev); 
			}
			else {
				$devHash->{ccutype} = $devtype;
				$rc = HMCCU_CreateDevice ($ioHash, $devHash->{ccuaddr}, $name, $devtype, $dev); 
			}
			return $rc+4 if ($rc > 0);
						
			# Set default attributes
			$attr{$name}{ccureadingformat} = 'name';
		}
	}

	return 0;
}

######################################################################
# Delete device
######################################################################

sub HMCCUDEV_Undef ($$)
{
	my ($hash, $arg) = @_;

	if (defined($hash->{IODev})) {
		HMCCU_RemoveDevice ($hash->{IODev}, $hash->{ccuif}, $hash->{ccuaddr}, $hash->{NAME});
		if ($hash->{ccuif} eq 'fhem') {
			HMCCU_DeleteDevice ($hash->{IODev});
		}
	}
	
	return undef;
}

######################################################################
# Rename device
######################################################################

sub HMCCUDEV_Rename ($$)
{
	my ($newName, $oldName) = @_;
	
	my $clHash = $defs{$newName};
	my $ioHash = defined($clHash) ? $clHash->{IODev} : undef;
	
	HMCCU_RenameDevice ($ioHash, $clHash, $oldName);
}

######################################################################
# Set attribute
######################################################################

sub HMCCUDEV_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};

	if ($cmd eq "set") {
		return "Missing attribute value" if (!defined ($attrval));
		if ($attrname eq 'IODev') {
			$hash->{IODev} = $defs{$attrval};
		}
		elsif ($attrname eq "statevals") {
			return "Device is read only" if ($hash->{readonly} eq 'yes');
		}
	}

	if ($init_done) {
		HMCCU_RefreshReadings ($hash);
	}
	
	return;
}

######################################################################
# Set commands
######################################################################

sub HMCCUDEV_Set ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;

	return "No set command specified" if (!defined ($opt));

	# Get I/O device, check device state
	return undef if (!defined ($hash->{ccudevstate}) || $hash->{ccudevstate} eq 'pending' ||
		!defined ($hash->{IODev}));
	my $ioHash = $hash->{IODev};
	my $hmccu_name = $ioHash->{NAME};

	# Handle read only and disabled devices
	return undef if ($hash->{readonly} eq 'yes' && $opt ne '?'
		&& $opt !~ /^(clear|config|defaults)$/);
	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);

	# Check if CCU is busy
	if (HMCCU_IsRPCStateBlocking ($ioHash)) {
		return undef if ($opt eq '?');
		return "HMCCUDEV: CCU busy";
	}

	# Get parameters of current device
	my $ccutype = $hash->{ccutype};
	my $ccuaddr = $hash->{ccuaddr};
	my $ccuif = $hash->{ccuif};
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	# Get state and control datapoints
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash);
			
	# Get additional commands (including state commands)
	my $roleCmds = HMCCU_GetSpecialCommands ($hash, $cc);

	my %pset = ('V' => 'VALUES', 'M' => 'MASTER', 'D' => 'MASTER');
	my $cmdList = '';
	my %valLookup;
	foreach my $cmd (keys %$roleCmds) {
		$cmdList .= " $cmd";
		my @setList = split (/\s+/, $roleCmds->{$cmd});
		foreach my $set (@setList) {
			my ($ps, $dpt, $par) = split(/:/, $set);
			my @argList = ();
			if ($par =~ /^#/) {
				my $paramDef = HMCCU_GetParamDef ($ioHash, $ccuaddr, $pset{$ps}, $dpt);
				if (defined($paramDef)) {
					if ($paramDef->{TYPE} eq 'ENUM' && defined($paramDef->{VALUE_LIST})) {
						$par = $paramDef->{VALUE_LIST};
						$par =~ s/[ ]+/-/g;
						@argList = split (',', $par);
						while (my ($i, $e) = each(@argList)) { $valLookup{$pset{$ps}}{$dpt}{$e} = $i; }
					}
				}
			}
			elsif ($par !~ /^\?/) {
				@argList = split (',', $par);
			}
			$cmdList .= scalar(@argList) > 1 ? ":$par" : ":noArg";
		}
	}
	
	# Get state values related to control command and datapoint
	my $stateVals = HMCCU_GetStateValues ($hash, $cd, $cc);
	my @stateCmdList = split (/[:,]/, $stateVals);
	my %stateCmds = @stateCmdList;
	my @states = keys %stateCmds;

	my $result = '';
	my $rc;

	# Log commands
	HMCCU_Log ($hash, 3, "set $name $opt ".join (' ', @$a))
		if ($opt ne '?' && $ccuflags =~ /logCommand/ || HMCCU_IsFlag ($hmccu_name, 'logCommand')); 
	
	if ($opt eq 'datapoint') {
		my $usage = "Usage: set $name datapoint [{channel-number}.]{datapoint} {value} [...]";
		my %dpval;
		my $i = 0;

		while (my $objname = shift @$a) {
			my $objvalue = shift @$a;
			$i += 1;

			if ($ccutype eq 'HM-Dis-EP-WM55' && !defined ($objvalue)) {
				$objvalue = '';
				foreach my $t (keys %{$h}) {
					if ($objvalue eq '') {
						$objvalue = $t.'='.$h->{$t};
					}
					else {
						$objvalue .= ','.$t.'='.$h->{$t};
					}
				}
			}

			return HMCCU_SetError ($hash, $usage) if (!defined ($objvalue) || $objvalue eq '');

			if ($objname =~ /^([0-9]+)\..+$/) {
				my $chn = $1;
				return HMCCU_SetError ($hash, -7) if ($chn >= $hash->{hmccu}{channels});
			}
			else {
				return HMCCU_SetError ($hash, -11) if ($cc eq '');
				$objname = $cc.'.'.$objname;
			}
		   
		   my $no = sprintf ("%03d", $i);
			$objvalue =~ s/\\_/%20/g;
			$dpval{"$no.$ccuif.$ccuaddr:$objname"} = HMCCU_Substitute ($objvalue, $stateVals, 1, undef, '');
		}

		return HMCCU_SetError ($hash, $usage) if (scalar (keys %dpval) < 1);
		
		$rc = HMCCU_SetMultipleDatapoints ($hash, \%dpval);
		return HMCCU_SetError ($hash, HMCCU_Min(0, $rc));
	}
	elsif ($opt eq 'toggle') {
		return HMCCU_SetError ($hash, -12) if ($cc eq '');
		return HMCCU_SetError ($hash, -14) if ($cd eq '');
		return HMCCU_SetError ($hash, -15) if ($stateVals eq '');
		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $cc, $cd, 2));

		my $stc = scalar (@states);
		my $curState = defined($hash->{hmccu}{dp}{"$cc.$cd"}{VALUES}{SVAL}) ?
			$hash->{hmccu}{dp}{"$cc.$cd"}{VALUES}{SVAL} : $states[0];

		my $newState = '';
		my $st = 0;
		while ($st < $stc) {
			if ($states[$st] eq $curState) {
				$newState = ($st == $stc-1) ? $states[0] : $states[$st+1];
				last;
			}
			else {
				$st++;
			}
		}

		return HMCCU_SetError ($hash, "Current device state doesn't match any state value")
		   if ($newState eq '');

		$rc = HMCCU_SetMultipleDatapoints ($hash,
			{ "001.$ccuif.$ccuaddr:$cc.$cd" => $stateCmds{$newState} }
		);
		return HMCCU_SetError ($hash, HMCCU_Min(0, $rc));
	}
	elsif (defined($roleCmds) && exists($roleCmds->{$opt})) {
		return HMCCU_SetError ($hash, -12) if ($cc eq '');
		return HMCCU_SetError ($hash, -14) if ($cd eq '');

		my $value;
		my %dpval;
		my %cfval;
		
		my @setList = split (/\s+/, $roleCmds->{$opt});
		my $i = 0;
		foreach my $set (@setList) {
			my ($ps, $dpt, $par) = split(/:/, $set);
		
			return HMCCU_SetError ($hash, "Syntax error in definition of command $opt")
				if (!defined($par));
	      if (!HMCCU_IsValidParameter ($hash, $ccuaddr, $pset{$ps}, $dpt)) {
	      	HMCCU_Trace ($hash, 2, "Set", "Invalid parameter $ps $dpt");
				return HMCCU_SetError ($hash, -8);
			}

			# Check if parameter is required
			if ($par =~ /^\?(.+)$/) {
				$par = $1;
				# Consider default value for parameter
				my ($parName, $parDef) = split ('=', $par);
				$value = shift @$a;
				if (!defined($value) && defined($parDef)) {
					if ($parDef =~ /^[+-][0-9]+$/) {
						return HMCCU_SetError ($hash, "Current value of $cc.$dpt not available")
							if (!defined($hash->{hmccu}{dp}{"$cc.$dpt"}{$pset{$ps}}{SVAL}));
						$value = $hash->{hmccu}{dp}{"$cc.$dpt"}{$pset{$ps}}{SVAL}+int($parDef);
					}
					else {
						$value = $parDef;
					}
				}
				
				return HMCCU_SetError ($hash, "Missing parameter $parName")
					if (!defined($value));
			}
			else {
				if (exists($valLookup{$ps}{$dpt})) {
					return HMCCU_SetError ($hash, "Illegal value $par. Use one of ".join(',', keys %{$valLookup{$ps}{$dpt}}))
						if (!exists($valLookup{$ps}{$dpt}{$par}));
					$value = $valLookup{$ps}{$dpt}{$par};
				}
				else {
					$value = $par;
				}
			}
		
			if ($opt eq 'pct' || $opt eq 'level') {
				my $timespec = shift @$a;
				my $ramptime = shift @$a;

				# Set on time
				if (defined ($timespec)) {
					return HMCCU_SetError ($hash, "Can't find ON_TIME datapoint for device type $ccutype")
						if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "ON_TIME", 2));
					if ($timespec =~ /^[0-9]{2}:[0-9]{2}/) {
						$timespec = HMCCU_GetTimeSpec ($timespec);
						return HMCCU_SetError ($hash, "Wrong time format. Use HH:MM[:SS]") if ($timespec < 0);
					}
					$dpval{"001.$ccuif.$ccuaddr.$cc.ON_TIME"} = $timespec if ($timespec > 0);
				}

				# Set ramp time
				if (defined($ramptime)) {
					return HMCCU_SetError ($hash, "Can't find RAMP_TIME datapoint for device type $ccutype")
						if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $ccuaddr, "RAMP_TIME", 2));
					$dpval{"002.$ccuif.$ccuaddr.$cc.RAMP_TIME"} = $ramptime if (defined ($ramptime));
				}
				
				$dpval{"003.$ccuif.$ccuaddr.$cc.$dpt"} = $value;
				last;
			}
			else {
				if ($ps eq 'V') {
					my $no = sprintf ("%03d", $i);
					$dpval{"$i.$ccuif.$ccuaddr.$cc.$dpt"} = $value;
					$i++;
				}
				else {
					$cfval{$dpt} = $value;
				}
			}
		}

		if (scalar(keys %dpval) > 0) {
			$rc = HMCCU_SetMultipleDatapoints ($hash, \%dpval);
			return HMCCU_SetError ($hash, HMCCU_Min(0, $rc));
		}
		if (scalar(keys %cfval) > 0) {
			($rc, $result) = HMCCU_SetMultipleParameters ($hash, $ccuaddr, $h, 'MASTER');
			return HMCCU_SetError ($hash, HMCCU_Min(0, $rc));
		}
	}
	elsif ($opt eq 'on-for-timer' || $opt eq 'on-till') {
		return HMCCU_SetError ($hash, -15) if ($stateVals eq '' || !exists($hash->{hmccu}{statevals}));
		return HMCCU_SetError ($hash, "No state value for 'on' defined")
		   if ("on" !~ /($hash->{hmccu}{statevals})/);
		return HMCCU_SetError ($hash, -12) if ($cc eq '');
		return HMCCU_SetError ($hash, -14) if ($cd eq '');
		return HMCCU_SetError ($hash, "Can't find ON_TIME datapoint for device type")
		   if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $cc, "ON_TIME", 2));

		my $timespec = shift @$a;
		return HMCCU_SetError ($hash, "Usage: set $name $opt {ontime-spec}")
			if (!defined ($timespec));
			
		if ($opt eq 'on-till') {
			$timespec = HMCCU_GetTimeSpec ($timespec);
			return HMCCU_SetError ($hash, "Wrong time format. Use HH:MM[:SS]") if ($timespec < 0);
		}
		
		$rc = HMCCU_SetMultipleDatapoints ($hash, {
			"001.$ccuif.$ccuaddr:$cc.ON_TIME" => $timespec,
			"002.$ccuif.$ccuaddr:$cc.$cd" => HMCCU_Substitute ("on", $stateVals, 1, undef, '')
		});
		return HMCCU_SetError ($hash, HMCCU_Min(0, $rc));
	}
	elsif ($opt eq 'clear') {
		my $rnexp = shift @$a;
		HMCCU_DeleteReadings ($hash, $rnexp);
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt =~ /^(config|values)$/) {
		my %parSets = ('config' => 'MASTER', 'values' => 'VALUES');
		my $paramset = $parSets{$opt};
		my $receiver = '';
		my $ccuobj = $ccuaddr;
		
		return HMCCU_SetError ($hash, "No parameter specified")
			if ((scalar keys %{$h}) < 1);	

		# Channel number is optional because parameter can be related to device or channel
		my $p = shift @$a;
		if (defined($p)) {
			if ($p =~ /^([0-9]{1,2})$/) {
				return HMCCU_SetError ($hash, -7) if ($p >= $hash->{hmccu}{channels});
				$ccuobj .= ':'.$p;
			}
			else {
				$receiver = $p;
				$paramset = 'LINK';
			}
		}
		
		my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $ccuobj, $ccuif);
		return HMCCU_SetError ($hash, "Can't get device description")
			if (!defined($devDesc));
		return HMCCU_SetError ($hash, "Paramset $paramset not supported by device or channel")
			if ($devDesc->{PARAMSETS} !~ /$paramset/);
		if (!HMCCU_IsValidParameter ($ioHash, $devDesc, $paramset, $h)) {
			my @parList = HMCCU_GetParamDef ($ioHash, $devDesc, $paramset);
			return HMCCU_SetError ($hash, "Invalid parameter specified. Valid parameters are ".
				join(',', @parList));
		}
				
		if ($paramset eq 'VALUES' || $paramset eq 'MASTER') {
			($rc, $result) = HMCCU_SetMultipleParameters ($hash, $ccuobj, $h, $paramset);
		}
		else {
			if (exists($defs{$receiver}) && defined($defs{$receiver}->{TYPE})) {
				my $clHash = $defs{$receiver};
				if ($clHash->{TYPE} eq 'HMCCUDEV') {
					my $chnNo = shift @$a;
					return HMCCU_SetError ($hash, "Channel number required for link receiver")
						if (!defined($chnNo) || $chnNo !~ /^[0-9]{1,2}$/);
					$receiver = $clHash->{ccuaddr}.":$chnNo";
				}
				elsif ($clHash->{TYPE} eq 'HMCCUCHN') {
					$receiver = $clHash->{ccuaddr};
				}
				else {
					return HMCCU_SetError ($hash, "Receiver $receiver is not a HMCCUCHN or HMCCUDEV device");
				}
			}
			elsif (!HMCCU_IsChnAddr ($receiver, 0)) {
				my ($rcvAdd, $rcvChn) = HMCCU_GetAddress ($ioHash, $receiver, '', '');
				return HMCCU_SetError ($hash, "$receiver is not a valid CCU channel name")
					if ($rcvAdd eq '' || $rcvChn eq '');
				$receiver = "$rcvAdd:$rcvChn";
			}

			return HMCCU_SetError ($hash, "$receiver is not a link receiver of $name")
				if (!HMCCU_IsValidReceiver ($ioHash, $ccuaddr, $ccuif, $receiver));
			($rc, $result) = HMCCU_RPCRequest ($hash, "putParamset", $ccuaddr, $receiver, $h);
		}

		return HMCCU_SetError ($hash, HMCCU_Min(0, $rc));
	}
	elsif ($opt eq 'defaults') {
		$rc = HMCCU_SetDefaultAttributes ($hash, $cc);
		$rc = HMCCU_SetDefaults ($hash) if (!$rc);
		return HMCCU_SetError ($hash, $rc == 0 ? "No default attributes found" : "OK");
	}
	else {
		my $retmsg = "clear defaults:noArg";
		
		if ($hash->{readonly} ne 'yes') {
			$retmsg .= " datapoint rpcparameter";
			if ($sc ne '') {
				$retmsg .= " config datapoint".$cmdList;
				$retmsg .= " toggle:noArg" if (scalar(@states) > 0);
				$retmsg .= " on-for-timer on-till"
					if ($cc ne '' && HMCCU_IsValidDatapoint ($hash, $hash->{ccutype}, $cc, "ON_TIME", 2));
			}
		}
		return AttrTemplate_Set ($hash, $retmsg, $name, $opt, @$a);
	}
}

######################################################################
# Get commands
######################################################################

sub HMCCUDEV_Get ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;

	return "No get command specified" if (!defined ($opt));
	
	# Get I/O device
	return undef if (!defined ($hash->{ccudevstate}) || $hash->{ccudevstate} eq 'pending' ||
		!defined ($hash->{IODev}));
	my $ioHash = $hash->{IODev};
	my $hmccu_name = $ioHash->{NAME};

	# Handle disabled devices
	my $disable = AttrVal ($name, "disable", 0);
	return undef if ($disable == 1);	

	# Check if CCU is busy
	if (HMCCU_IsRPCStateBlocking ($ioHash)) {
		return undef if ($opt eq '?');
		return "HMCCUDEV: CCU busy";
	}

	# Get parameters of current device
	my $ccutype = $hash->{ccutype};
	my $ccuaddr = $hash->{ccuaddr};
	my $ccuif = $hash->{ccuif};
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash);

	my $result = '';
	my $rc;

	# Virtual devices only support command get update
	if ($ccuif eq 'fhem' && $opt ne 'update') {
		return "HMCCUDEV: Unknown argument $opt, choose one of update:noArg";
	}

	# Log commands
	HMCCU_Log ($hash, 3, "get $name $opt ".join (' ', @$a))
		if ($opt ne '?' && $ccuflags =~ /logCommand/ || HMCCU_IsFlag ($hmccu_name, 'logCommand')); 

	if ($opt eq 'devstate') {
		return HMCCU_SetError ($hash, -11) if ($sc eq '');
		return HMCCU_SetError ($hash, -13) if ($sd eq '');
		return HMCCU_SetError ($hash, -8) if (!HMCCU_IsValidDatapoint ($hash, $ccutype, $sc, $sd, 1));
		   
		my $objname = $ccuif.'.'.$ccuaddr.':'.$sc.'.'.$sd;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname, 0);

		return HMCCU_SetError ($hash, $rc, $result) if ($rc < 0);
		return $result;
	}
	elsif ($opt eq 'datapoint') {
		my $objname = shift @$a;
		return HMCCU_SetError ($hash, "Usage: get $name datapoint [{channel-number}.]{datapoint}")
			if (!defined ($objname));

		if ($objname =~ /^([0-9]+)\..+$/) {
			my $chn = $1;
			return HMCCU_SetError ($hash, -7) if ($chn >= $hash->{hmccu}{channels});
		}
		else {
			return HMCCU_SetError ($hash, -11) if ($sc eq '');
			$objname = $sc.'.'.$objname;
		}

		return HMCCU_SetError ($hash, -8)
			if (!HMCCU_IsValidDatapoint ($hash, $ccutype, undef, $objname, 1));

		$objname = $ccuif.'.'.$ccuaddr.':'.$objname;
		($rc, $result) = HMCCU_GetDatapoint ($hash, $objname, 0);

		return HMCCU_SetError ($hash, $rc, $result) if ($rc < 0);
		HMCCU_SetState ($hash, "OK") if (exists ($hash->{STATE}) && $hash->{STATE} eq "Error");
		return $result;
	}
	elsif ($opt eq 'update') {
		my $ccuget = shift @$a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCU_SetError ($hash, "Usage: get $name update [{'State'|'Value'}]");
		}

		if ($hash->{ccuif} ne 'fhem') {
			$rc = HMCCU_GetUpdate ($hash, $ccuaddr, $ccuget);
			return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		}
		else {
			# Update all devices belonging to group
			my @vdevs = split (",", $hash->{ccugroup});
			foreach my $vd (@vdevs) {
				$rc = HMCCU_GetUpdate ($hash, $vd, $ccuget);
				return HMCCU_SetError ($hash, $rc) if ($rc < 0);
			}
		}

		return undef;
	}
	elsif ($opt eq 'deviceinfo') {
		my $ccuget = shift @$a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		if ($ccuget !~ /^(Attr|State|Value)$/) {
			return HMCCU_SetError ($hash, "Usage: get $name deviceinfo [{'State'|'Value'}]");
		}
		$result = HMCCU_GetDeviceInfo ($hash, $ccuaddr, $ccuget);
		return HMCCU_SetError ($hash, -2) if ($result eq '');
		my $devInfo = HMCCU_FormatDeviceInfo ($result);
		$devInfo .= "StateDatapoint = $sc.$sd\nControlDatapoint = $cc.$cd";
		return $devInfo;
	}
	elsif ($opt =~ /^(paramset|config|values)$/) {
		my $par = shift @$a;
		my $defParamset = '';
		my %parSets = ('config' => 'MASTER,LINK', 'values' => 'VALUES');
		my ($devAddr, undef) = HMCCU_SplitChnAddr ($ccuaddr);
		my @addList = ($ccuaddr);

		my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $ccuaddr, $ccuif);
		return HMCCU_SetError ($hash, "Can't get device description") if (!defined($devDesc));
		push @addList, split (',', $devDesc->{CHILDREN});
		
		if (exists($parSets{$opt})) {
			$defParamset = $parSets{$opt};
		}
		else {
			if (defined($par)) {
				$defParamset = $par;
				$par = shift @$a;
			}
		}
		
		$par = '.*' if (!defined ($par));

		my $res = '';
		my %objects;
		foreach my $a (@addList) {
			my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $a, $ccuif);
			return HMCCU_SetError ($hash, "Can't get device description") if (!defined($devDesc));
			
			my $paramset = $defParamset eq '' ? $devDesc->{PARAMSETS} : $defParamset;
			my ($da, $dc) = HMCCU_SplitChnAddr ($a);
			$dc = 'd' if ($dc eq '');

			$res .= $a eq $devAddr ? "Device $a\n" : "Channel $a\n";
			foreach my $ps (split (',', $paramset)) {
				next if ($devDesc->{PARAMSETS} !~ /$ps/);

				($rc, $result) = HMCCU_RPCRequest ($hash, 'getRawParamset', $a, $ps, undef, $par);
				return HMCCU_SetError ($hash, $rc, $result) if ($rc < 0);
				my @paramsetPars = keys %$result;
				next if (scalar(@paramsetPars) == 0);
				
				$res .= "  Paramset $ps\n".join ("\n", map { $_ =~ /$par/ ?
					"    ".$_.' = '.HMCCU_GetParamValue ($ioHash, $devDesc, $ps, $_, $result->{$_}) : ()
				} sort @paramsetPars)."\n";

				foreach my $p (@paramsetPars) { $objects{$da}{$dc}{$ps}{$p} = $result->{$p}; }
			}
		}

		if (scalar(keys %objects) > 0) {
			my $convRes = HMCCU_UpdateParamsetReadings ($ioHash, $hash, \%objects);
			if (defined($convRes)) {
				foreach my $da (sort keys %$convRes) {
					$res .= "Device $da\n";
					foreach my $dc (sort keys %{$convRes->{$da}}) {
						foreach my $ps (sort keys %{$convRes->{$da}{$dc}}) { 
							$res .= "  Channel $dc [$ps]\n";
							$res .= join ("\n", map { 
								"    ".$_.' = '.$convRes->{$da}{$dc}{$ps}{$_}
							} sort keys %{$convRes->{$da}{$dc}{$ps}})."\n";
						}
					}
				}
			}
		}
		
		return $res;
	}
	elsif ($opt eq 'paramsetdesc') {
		$result = HMCCU_ParamsetDescToStr ($ioHash, $hash);
		return defined($result) ? $result : HMCCU_SetError ($hash, "Can't get device model");
	}
	elsif ($opt eq 'devicedesc') {
		$result = HMCCU_DeviceDescToStr ($ioHash, $hash);
		return defined($result) ? $result : HMCCU_SetError ($hash, "Can't get device description");
	}
	elsif ($opt eq 'defaults') {
		$result = HMCCU_GetDefaults ($hash, 0);
		return $result;
	}
	else {
		my $retmsg = "HMCCUDEV: Unknown argument $opt, choose one of datapoint";
		
		my @valuelist;
		my $valuecount = HMCCU_GetValidDatapoints ($hash, $ccutype, -1, 1, \@valuelist);
		   
		$retmsg .= ":".join(",", @valuelist) if ($valuecount > 0);
		$retmsg .= " defaults:noArg update:noArg config paramset".
			" paramsetdesc:noArg devicedesc:noArg deviceinfo:noArg";
		$retmsg .= ' devstate:noArg' if ($sc ne '');

		return $retmsg;
	}
}


1;

=pod
=item device
=item summary controls HMCCU client devices for Homematic CCU - FHEM integration
=begin html

<a name="HMCCUDEV"></a>
<h3>HMCCUDEV</h3>
<ul>
   The module implements Homematic CCU devices as client devices for HMCCU. A HMCCU I/O device must
   exist before a client device can be defined. If a CCU channel is not found execute command
   'get devicelist' in I/O device.<br/>
   This reference contains only commands and attributes which differ from module
   <a href="#HMCCUCHN">HMCCUCHN</a>.
   </br></br>
   <a name="HMCCUDEVdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; HMCCUDEV {&lt;device&gt; | 'virtual'} [&lt;controlchannel&gt;]
      [readonly] [<u>defaults</u>|noDefaults] [{group={device|channel}[,...]|groupexp=regexp] 
      [iodev=&lt;iodev-name&gt;]</code>
      <br/><br/>
      If option 'readonly' is specified no set command will be available. With option 'defaults'
      some default attributes depending on CCU device type will be set. Default attributes are only
      available for some device types. The option is ignored during FHEM start.
      Parameter <i>controlchannel</i> corresponds to attribute 'controlchannel'.<br/>
      A HMCCUDEV device supports CCU group devices. The CCU devices or channels related to a group
      device are specified by using options 'group' or 'groupexp' followed by the names or
      addresses of the CCU devices or channels. By using 'groupexp' one can specify a regular
      expression for CCU device or channel names. Since version 4.2.009 of HMCCU HMCCUDEV
      is able to detect members of group devices automatically. So options 'group' or
      'groupexp' are no longer necessary to define a group device.<br/>
      It's also possible to group any kind of CCU devices without defining a real group
      in CCU by using option 'virtual' instead of a CCU device specification. 
      <br/><br/>
      Examples:<br/>
      <code>
      # Simple device by using CCU device name<br/>
      define window_living HMCCUDEV WIN-LIV-1<br/>
      # Simple device by using CCU device address and with state channel<br/>
      define temp_control HMCCUDEV BidCos-RF.LEQ1234567 1<br/>
      # Simple read only device by using CCU device address and with default attributes<br/>
      define temp_sensor HMCCUDEV BidCos-RF.LEQ2345678 1 readonly defaults
      # Group device by using CCU group device and 3 group members<br/>
      define heating_living HMCCUDEV GRP-LIV group=WIN-LIV,HEAT-LIV,THERM-LIV
      </code>
      <br/>
   </ul>
   <br/>
   
   <a name="HMCCUDEVset"></a>
   <b>Set</b><br/><br/>
   <ul>
      <li><b>set &lt;name&gt; clear [&lt;reading-exp&gt;]</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a> 
      </li><br/>
      <li><b>set &lt;name&gt; config [&lt;channel-number&gt;] &lt;parameter&gt;=&lt;value&gt;
        [...]</b><br/>
        Set configuration parameter of CCU device or channel. Valid parameters can be listed by 
        using command 'get configdesc'.
      </li><br/>
      <li><b>set &lt;name&gt; datapoint [&lt;channel-number&gt;.]&lt;datapoint&gt;
       &lt;value&gt; [...]</b><br/>
        Set datapoint values of a CCU device channel. If channel number is not specified
        state channel is used. String \_ is substituted by blank.
        <br/><br/>
        Example:<br/>
        <code>set temp_control datapoint 2.SET_TEMPERATURE 21</code><br/>
        <code>set temp_control datapoint 2.AUTO_MODE 1 2.SET_TEMPERATURE 21</code>
      </li><br/>
      <li><b>set &lt;name&gt; defaults</b><br/>
   		Set default attributes for CCU device type. Default attributes are only available for
   		some device types.
      </li><br/>
      <li><b>set &lt;name&gt; devstate &lt;value&gt;</b><br/>
         Set state of a CCU device channel. Channel and state datapoint must be defined as
         attribute 'statedatapoint'. If <i>value</i> contains string \_ it is substituted by blank.
      </li><br/>
      <li><b>set &lt;name&gt; down [&lt;value&gt;]</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>set &lt;name&gt; on-for-timer &lt;ontime&gt;</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>set &lt;name&gt; on-till &lt;timestamp&gt;</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>set &lt;name&gt; pct &lt;value;&gt; [&lt;ontime&gt; [&lt;ramptime&gt;]]</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>set &lt;name&gt; rpcparameter [&lt;channel&gt;] { VALUES | MASTER | LINK } &lt;parameter&gt;=&lt;value&gt; [...]</b><br/>
         Set multiple datapoints or config parameters by using RPC interface instead of ReGa.
         Supports attribute 'ccuscaleval' for datapoints. Methods VALUES (setting datapoints)
         and LINK require a channel number. For method MASTER (setting parameters) a channel number
         is optional (setting device parameters). Parameter <i>parameter</i> must be a valid
         datapoint or config parameter name.
      </li><br/>
      <li><b>set &lt;name&gt; &lt;statevalue&gt;</b><br/>
         State datapoint of a CCU device channel is set to 'statevalue'. State channel and state
         datapoint must be defined as attribute 'statedatapoint'. Values for <i>statevalue</i>
         are defined by setting attribute 'statevals'.
         <br/><br/>
         Example:<br/>
         <code>
         attr myswitch statedatapoint 1.STATE<br/>
         attr myswitch statevals on:true,off:false<br/>
         set myswitch on
         </code>
      </li><br/>
      <li><b>set &lt;name&gt; toggle</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>set &lt;name&gt; up [&lt;value&gt;]</b><br/>
      	<a href="#HMCCUCHNset">see HMCCUCHN</a>
      </li><br/>
      <li><b>ePaper Display</b><br/><br/>
      This display has 5 text lines. The lines 1,2 and 4,5 are accessible via config parameters
      TEXTLINE_1 and TEXTLINE_2 in channels 1 and 2. Example:<br/><br/>
      <code>
      define HM_EPDISP HMCCUDEV CCU_EPDISP<br/>
      set HM_EPDISP config 2 TEXTLINE_1=Line1<br/>
		set HM_EPDISP config 2 TEXTLINE_2=Line2<br/>
		set HM_EPDISP config 1 TEXTLINE_1=Line4<br/>
		set HM_EPDISP config 1 TEXTLINE_2=Line5<br/>
      </code>
      <br/>
      The lines 2,3 and 4 of the display can be accessed by setting the datapoint SUBMIT of the
      display to a string containing command tokens in format 'parameter=value'. The following
      commands are allowed:
      <br/><br/>
      <ul>
      <li>text1-3=Text - Content of display line 2-4</li>
      <li>icon1-3=IconCode - Icons of display line 2-4</li>
      <li>sound=SoundCode - Sound</li>
      <li>signal=SignalCode - Optical signal</li>
      <li>pause=Seconds - Pause between signals (1-160)</li>
      <li>repeat=Count - Repeat count for sound (0-15)</li>
      </ul>
      <br/>
      IconCode := ico_off, ico_on, ico_open, ico_closed, ico_error, ico_ok, ico_info,
      ico_newmsg, ico_svcmsg<br/>
      SignalCode := sig_off, sig_red, sig_green, sig_orange<br/>
      SoundCode := snd_off, snd_longlong, snd_longshort, snd_long2short, snd_short, snd_shortshort,
      snd_long<br/><br/>
      Example:<br/>
      <code>
      set HM_EPDISP datapoint 3.SUBMIT text1=Line2,text2=Line3,text3=Line4,sound=snd_short,
      signal=sig_red
      </code>
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUDEVget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <li><b>get &lt;name&gt; config [&lt;filter-expr&gt;]</b><br/>
         Get configuration parameters of CCU device and all its channels. If ccuflag noReadings is set 
         parameters are displayed in browser window (no readings set). Parameters can be filtered
         by <i>filter-expr</i>.
      </li><br/>
      <li><b>get &lt;name&gt; datapoint [&lt;channel-number&gt;.]&lt;datapoint&gt;</b><br/>
         Get value of a CCU device datapoint. If <i>channel-number</i> is not specified state 
         channel is used.
      </li><br/>
      <li><b>get &lt;name&gt; defaults</b><br/>
      	<a href="#HMCCUCHNget">see HMCCUCHN</a>
      </li><br/>
      <li><b>get &lt;name&gt; devicedesc [&lt;channel-number&gt;]</b><br/>
      	Display device description.
      </li><br/>
      <li><b>get &lt;name&gt; deviceinfo [{State | <u>Value</u>}]</b><br/>
         Display all channels and datapoints of device with datapoint values and types.
      </li><br/>
      <li><b>get &lt;name&gt; devstate</b><br/>
         Get state of CCU device. Attribute 'statechannel' must be set. Default state datapoint
         STATE can be modified by attribute 'statedatapoint'.
      </li><br/>
		<li><b>get &lt;name&gt; paramset [&lt;paramset&gt;[,...]] [&lt;filter-expr&gt;]</b><br/>
			Read parameter set values.
		</li><br/>
      <li><b>get &lt;name&gt; update [{State | <u>Value</u>}]</b><br/>
      	<a href="#HMCCUCHNget">see HMCCUCHN</a>
      </li><br/>
   </ul>
   <br/>
   
   <a name="HMCCUDEVattr"></a>
   <b>Attributes</b><br/><br/>
   <ul>
      To reduce the amount of events it's recommended to set attribute 'event-on-change-reading'
      to '.*'.<br/><br/>
      <li><b>ccucalculate &lt;value-type&gt;:&lt;reading&gt;[:&lt;dp-list&gt;[;...]</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuflags {nochn0, trace}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuget {State | <u>Value</u>}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccureadingfilter &lt;filter-rule[,...]&gt;</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccureadingformat {address[lc] | name[lc] | datapoint[lc]}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccureadingname &lt;old-readingname-expr&gt;:&lt;new-readingname&gt;[,...]</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuscaleval &lt;datapoint&gt;:&lt;factor&gt;[,...]</b><br/>
      ccuscaleval &lt;[!]datapoint&gt;:&lt;min&gt;:&lt;max&gt;:&lt;minn&gt;:&lt;maxn&gt;[,...]<br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuSetOnChange &lt;expression&gt;</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>ccuverify {0 | 1 | 2}</b><br/>
      	<a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>controlchannel &lt;channel-number&gt;</b><br/>
         Channel used for setting device states.
      </li><br/>
      <li><b>controldatapoint &lt;channel-number.datapoint&gt;</b><br/>
         Set channel number and datapoint for device control.
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>disable {<u>0</u> | 1}</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
		<li><b>hmstatevals &lt;subst-rule&gt;[;...]</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
		</li><br/>
		<li><b>peer [&lt;datapoints&gt;:&lt;condition&gt;:
			{ccu:&lt;object&gt;=&lt;value&gt;|hmccu:&lt;object&gt;=&lt;value&gt;|fhem:&lt;command&gt;}</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
		</li><br/>
      <li><b>statechannel &lt;channel-number&gt;</b><br/>
         Channel for getting device state. Deprecated, use attribute 'statedatapoint' instead.
      </li><br/>
      <li><b>statedatapoint [&lt;channel-number&gt;.]&lt;datapoint&gt;</b><br/>
         Set state channel and state datapoint for setting device state by devstate command.
         Default is STATE. If 'statedatapoint' is not defined at least attribute 'statechannel'
         must be set.
      </li><br/>
      <li><b>statevals &lt;text&gt;:&lt;text&gt;[,...]</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>stripnumber {0 | 1 | 2 | -n}</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>substexcl &lt;reading-expr&gt;</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
      <li><b>substitute &lt;subst-rule&gt;[;...]</b><br/>
         <a href="#HMCCUCHNattr">see HMCCUCHN</a>
      </li><br/>
   </ul>
</ul>

=end html
=cut

