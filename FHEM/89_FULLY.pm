##############################################################################
#
#  89_FULLY.pm 0.4
#
#  $Id$
#
#  Control Fully browser on Android tablets from FHEM.
#  Requires Fully Plus license!
#
##############################################################################

package main;

use strict;
use warnings;
use Blocking;
use SetExtensions;

# Declare functions
sub FULLY_Initialize ($);
sub FULLY_Define ($$);
sub FULLY_Undef ($$);
sub FULLY_Shutdown ($);
sub FULLY_Set ($@);
sub FULLY_Get ($@);
sub FULLY_Attr ($@);
sub FULLY_UpdateDeviceInfo ($);
sub FULLY_Execute ($$$);
sub FULLY_GetDeviceInfo ($);
sub FULLY_ProcessDeviceInfo ($$);
sub FULLY_GotDeviceInfo ($);
sub FULLY_Abort ($);
sub FULLY_UpdateReadings ($$);

my $FULLY_VERSION = "0.4";
my $FULLY_TIMEOUT = 4;
my $FULLY_POLL_INTERVAL = 3600;

##################################################
# Initialize module
##################################################

sub FULLY_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "FULLY_Define";
	$hash->{UndefFn} = "FULLY_Undef";
	$hash->{SetFn} = "FULLY_Set";
	$hash->{GetFn} = "FULLY_Get";
	$hash->{AttrFn} = "FULLY_Attr";
	$hash->{ShutdownFn} = "FULLY_Shutdown";
	$hash->{parseParams} = 1;

	$hash->{AttrList} = "pollInterval requestTimeout " . $readingFnAttributes;
}

##################################################
# Define device
##################################################

sub FULLY_Define ($$)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};
	my $rc = 0;
	
	return "Usage: define devname FULLY IP_or_Hostname password [poll-interval]"
		if (@$a < 4);
	return "FULLY: polling interval must be in range 10 - 86400"
		if (@$a == 5 && ($$a[4] !~ /^[1-9][0-9]+$/ || $$a[4] < 10 || $$a[4] > 86400));

	$hash->{host} = $$a[2];
	$hash->{version} = $FULLY_VERSION;
	$hash->{fully}{password} = $$a[3];
	$hash->{fully}{schedule} = 0;

	Log3 $name, 1, "FULLY: Opening device ".$hash->{host};
	
	my $result = FULLY_GetDeviceInfo ($name);
	if (!FULLY_UpdateReadings ($hash, $result)) {
		Log3 $name, 2, "FULLY: Update of device info failed";
	}

	if (@$a == 5) {
		$attr{$name}{'pollInterval'} = $$a[4];
		$hash->{nextUpdate} = strftime "%d.%m.%Y %H:%M:%S", localtime (time+$$a[4]);
		InternalTimer (gettimeofday()+$$a[4], "FULLY_UpdateDeviceInfo", $hash, 0);
	}
	else {
		$hash->{nextUpdate} = 'off';
	}

	return undef;
}

#####################################
# Set or delete attribute
#####################################

sub FULLY_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};

	if ($cmd eq 'set') {
		if ($attrname eq 'pollInterval') {
			if ($attrval >= 10 && $attrval <= 86400) {
				my $curval = AttrVal ($name, 'pollInterval', $FULLY_POLL_INTERVAL);
				if ($attrval != $curval) {
					Log3 $name, 2, "FULLY: Polling interval set to $attrval";
					RemoveInternalTimer ($hash);
					$hash->{nextUpdate} = strftime "%d.%m.%Y %H:%M:%S", localtime (time+$attrval);
					InternalTimer (gettimeofday()+$attrval, "FULLY_UpdateDeviceInfo", $hash, 0);
				}
			}
			elsif ($attrval == 0) {
				RemoveInternalTimer ($hash);
				$hash->{nextUpdate} = 'off';
			}
			else {
				return "FULLY: Polling interval must be in range 10-86400";
			}
		}
		elsif ($attrname eq 'requestTimeout') {
			return "FULLY: Timeout must be greater than 0" if ($attrval < 1);
		}
	}
	elsif ($cmd eq 'del') {
		if ($attrname eq 'pollInterval') {
				RemoveInternalTimer ($hash);
				$hash->{nextUpdate} = 'off';			
		}
	}
	
	return undef;
}

#####################################
# Delete device
#####################################

sub FULLY_Undef ($$)
{
	my ($hash, $arg) = @_;

	RemoveInternalTimer ($hash);
	BlockingKill ($hash->{fully}{bc}) if (defined ($hash->{fully}{bc}));
	
	return undef;
}

#####################################
# Shutdown FHEM
#####################################

sub FULLY_Shutdown ($)
{
	my ($hash) = @_;

	RemoveInternalTimer ($hash);
	BlockingKill ($hash->{fully}{bc}) if (defined ($hash->{fully}{bc}));

	return undef;
}
	
#####################################
# Set commands
#####################################

sub FULLY_Set ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;
	my $options = "clearCache:noArg exit:noArg lock:noArg motionDetection:on,off off:noArg ".
		"on:noArg restart:noArg unlock:noArg speak url";
	my $response;
	
	# Fully commands without argument
	my %cmds = (
		"clearCache" => "clearCache",
		"exit" => "exitApp", "restart" => "restartApp",
		"on" => "screenOn", "off" => "screenOff",
		"lock" => "enabledLockedMode", "unlock" => "disableLockedMode"
	);
	
	if (exists ($cmds{$opt})) {
		$response = FULLY_Execute ($hash, $cmds{$opt}, undef);
	}
	elsif ($opt eq 'motionDetection') {
		my $state = shift @$a;
		return "Usage: set $name motionDetection {on|off}" if (!defined ($state));
		my $value = $state eq 'on' ? 'true' : 'false';
		$response = FULLY_Execute ($hash, "setBooleanSetting",
			{ "key" => "motionDetection", "value" => "$value" });
	}
	elsif ($opt eq 'speak') {
		my $text = shift @$a;
		return "Usage: set $name speak {Text}" if (!defined ($text));
		while ($text =~ /\[(.+):(.+)\]/) {
			my ($device, $reading) = ($1, $2);
			my $value = ReadingsVal ($device, $reading, '');
			$text =~ s/\[$device:$reading\]/$value/g;
		}
		my $enctext = urlEncode ($text);
		$response = FULLY_Execute ($hash, "textToSpeech", { "text" => "$enctext" });
	}
	elsif ($opt eq 'url') {
		my $url = shift @$a;
		my $cmd = defined ($url) ? "loadURL" : "loadStartURL";
		$response = FULLY_Execute ($hash, $cmd, { "url" => "$url" });
	}
	else {
		return "FULLY: Unknown argument $opt, choose one of ".$options;
	}
	
	my $result = FULLY_ProcessDeviceInfo ($name, $response);
	if (!FULLY_UpdateReadings ($hash, $result)) {
		Log3 $name, 2, "FULLY: Command failed";
		return "FULLY: Command failed";
	}
	
	return undef;
}

#####################################
# Get commands
#####################################

sub FULLY_Get ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;
	my $options = "info:noArg stats:noArg update:noArg";
	my $response;

	if ($opt eq 'info') {
		my $result = FULLY_Execute ($hash, 'deviceInfo', undef);
		if (!defined ($result) || $result eq '') {
			Log3 $name, 2, "FULLY: Command failed";
			return "FULLY: Command failed";
		}
		elsif ($response =~ /Wrong password/) {
			Log3 $name, 2, "FULLY: Wrong password";
			return "FULLY: Wrong password";
		}

		$response = '';
		while ($result =~ /table-cell\">([^<]+)<\/td><td class="table-cell">([^<]+)</g) {
			$response .= "$1 = $2<br/>\n";
		}
		
		return $response;
	}
	elsif ($opt eq 'stats') {
		return "FULLY: Command not implemented";
	}
	elsif ($opt eq 'update') {
		my $result = FULLY_GetDeviceInfo ($name);
		if (!FULLY_UpdateReadings ($hash, $result)) {
			Log3 $name, 2, "FULLY: Command failed";
			return "FULLY: Command failed";
		}
	}
	else {
		return "FULLY: Unknown argument $opt, choose one of ".$options;
	}
	
	return undef;
}

#####################################
# Execute Fully command
#####################################

sub FULLY_Execute ($$$)
{
	my ($hash, $command, $param) = @_;
	my $name = $hash->{NAME};

	my $timeout = AttrVal ($name, 'requestTimeout', $FULLY_TIMEOUT);
	
	my $url = "http://".$hash->{host}.":2323/?cmd=$command";
	
	if (defined ($param)) {
		foreach my $parname (keys %$param) {
			if (defined ($param->{$parname})) {
				$url .= "&$parname=".$param->{$parname};
			}
		}
	}

	return GetFileFromURL ("$url&password=".$hash->{fully}{password}, $timeout);
}

#####################################
# Timer function: Read device info
#####################################

sub FULLY_UpdateDeviceInfo ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if (!exists ($hash->{fully}{bc})) {
		$hash->{fully}{bc} = BlockingCall ("FULLY_GetDeviceInfo", $name, "FULLY_GotDeviceInfo",
			120, "FULLY_Abort", $hash);
	}
}

#####################################
# Get tablet device information
#####################################

sub FULLY_GetDeviceInfo ($)
{
	my ($name) = @_;
	my $hash = $defs{$name};
	
	my $result = FULLY_Execute ($hash, 'deviceInfo', undef);
	
	return FULLY_ProcessDeviceInfo ($name, $result);
}

#####################################
# Extract parameters from HTML code
#####################################

sub FULLY_ProcessDeviceInfo ($$)
{
	my ($name, $result) = @_;

	return "$name|0|state=failed" if (!defined ($result) || $result eq '');
	return "$name|0|state=wrong password" if ($result =~ /Wrong password/);
	
	my $parameters = "$name|1";
	while ($result =~ /table-cell\">([^<]+)<\/td><td class="table-cell">([^<]+)</g) {
		my $rn = lc($1);
		my $rv = $2;
		$rn =~ s/\:/\./g;
		$rn =~ s/[^A-Za-z\d_\.-]+/_/g;
		$rn =~ s/[_]+$//;
		if ($rn eq 'battery_level') {
			if ($rv =~ /^([0-9]+)% \(([^\)]+)\)$/) {
				$parameters .= "|$rn=$1|power=$2";
				next;
			}
		}
		elsif ($rn eq 'screen_status') {
			$parameters .= "|state=$rv";
		}
		$parameters .= "|$rn=$rv";
	}
	
	return $parameters;
}

#####################################
# Success function for blocking call
#####################################

sub FULLY_GotDeviceInfo ($)
{
	my ($string) = @_;
	
	my ($name, $result) = split ('\|', $string, 2);
	my $hash = $defs{$name};

	my $pollInterval = AttrVal ($name, 'pollInterval', $FULLY_POLL_INTERVAL);
	my $timeout = AttrVal ($name, 'requestTimeout', $FULLY_TIMEOUT);

	delete $hash->{fully}{bc} if (exists ($hash->{fully}{bc}));
	
	my $rc = FULLY_UpdateReadings ($hash, $string);
	if (!$rc) {
		Log3 $name, 2, "FULLY: Request timed out";
		if ($hash->{fully}{schedule} == 0) {
			$hash->{fully}{schedule} += 1;
			Log3 $name, 2, "FULLY: Rescheduling in $timeout seconds.";
			$pollInterval = $timeout;
		}
		else {
			$hash->{fully}{schedule} = 0;
		}
	}

	$hash->{nextUpdate} = strftime "%d.%m.%Y %H:%M:%S", localtime (time+$pollInterval);
	InternalTimer (gettimeofday()+$pollInterval, "FULLY_UpdateDeviceInfo", $hash, 0)
		if ($pollInterval > 0);
}

#####################################
# Abort function for blocking call
#####################################

sub FULLY_Abort ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $pollInterval = AttrVal ($name, 'pollInterval', $FULLY_POLL_INTERVAL);
	my $timeout = AttrVal ($name, 'requestTimeout', $FULLY_TIMEOUT);

	delete $hash->{fully}{bc} if (exists ($hash->{fully}{bc}));		

	Log3 $name, 2, "FULLY: request timed out";
	if ($hash->{fully}{schedule} == 0) {
		$hash->{fully}{schedule} += 1;
		Log3 $name, 2, "FULLY: Rescheduling in $timeout seconds.";
		$pollInterval = $timeout;
	}
	else {
		$hash->{fully}{schedule} = 0;
	}

	$hash->{nextUpdate} = strftime "%d.%m.%Y %H:%M:%S", localtime (time+$pollInterval);
	InternalTimer (gettimeofday()+$pollInterval, "FULLY_UpdateDeviceInfo", $hash, 0)
		if ($pollInterval > 0);
}

#####################################
# Update readings
#####################################

sub FULLY_UpdateReadings ($$)
{
	my ($hash, $result) = @_;
	my $name = $hash->{NAME};
	my $rc = 1;

	if (!defined ($result) || $result eq '') {
		Log3 $name, 2, "FULLY: empty response";
		return 0;
	}
	
	my @parameters = split ('\|', $result);
	if (scalar (@parameters) == 0) {
		Log3 $name, 2, "FULLY: empty response";
		return 0;
	}
	
	if ($parameters[0] eq $name) {
		my $n = shift @parameters;
		$rc = shift @parameters;
	}
	
	readingsBeginUpdate ($hash);
	foreach my $parval (@parameters) {
		my ($rn, $rv) = split ('=', $parval);
		readingsBulkUpdate ($hash, $rn, $rv);
	}
	readingsEndUpdate ($hash, 1);
	
	return $rc;	
}

1;


=pod
=item device
=item summary FULLY Browser Integration
=begin html

<a name="FULLY"></a>
<h3>FULLY</h3>
<ul>
   Module for controlling of Fully browser on Android tablets.
   </br></br>
   
   <a name="HMCCUdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; FULLY &lt;HostOrIP&gt; &lt;password&gt; [&lt;poll-interval&gt;]</code>
      <br/><br/>
	  The parameter <i>password</i> is the password set in Fully browser. 
   </ul>
   <br/>
   
   <a name="FULLYset"></a>
   <b>Set</b><br/><br/>
   <ul>
		<li><b>set &lt;name&gt; clearCache</b><br/>
			Clear browser cache.
		</li><br/>
		<li><b>set &lt;name&gt; exit</b><br/>
			Terminate Fully.
		</li><br/>
		<li><b>set &lt;name&gt; motionDetection { on | off }</b><br/>
			Turn motion detection by camera on or off.
		</li><br/>
		<li><b>set &lt;name&gt; { lock | unlock }</b><br/>
			Lock or unlock display.
		</li><br/>
		<li><b>set &lt;name&gt; { on | off }</b><br/>
			Turn tablet display on or off.
		</li><br/>
		<li><b>set &lt;name&gt; restart</b><br/>
			Restart Fully.
		</li><br/>
		<li><b>set &lt;name&gt; speak &lt;text&gt;</b><br/>
			Audio output of <i>text</i>. If <i>text</i> contains blanks it must be enclosed
			in double quotes. The text can contain device readings in format [device:reading].
		</li><br/>
		<li><b>set &lt;name&gt; url [&lt;URL&gt;]</b><br/>
			Navigate to <i>URL</i>. If no URL is specified navigate to start URL.
		</li><br/>
   </ul>
   <br/>
   
   <a name="FULLYget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <li><b>get &lt;name&gt; info</b><br/>
      	Display Fully information.
      </li><br/>
      <li><b>get &lt;name&gt; stats</b><br/>
      	Show Fully statistics.
      </li><br/>
      <li><b>get &lt;name&gt; update</b><br/>
      	Update readings.
      </li><br/>
   </ul>
   <br/>
   
   <a name="FULLYattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
      <li><b>pollInterval &lt;seconds&gt;</b><br/>
         Set polling interval for FULLY device information.
         If <i>seconds</i> is 0 polling is turned off. Valid values are from 10 to
         86400 seconds.
      </li><br/>
      <li><b>requestTimeout &lt;seconds&gt;</b><br/>
         Set timeout for http requests. Default is 4 seconds.
      </li><br/>
   </ul>
</ul>

=end html
=cut

