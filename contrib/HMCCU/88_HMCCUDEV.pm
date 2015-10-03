################################################################
#
#  88_HMCCUDEV.pm
#
#  $Id:$
#
#  Version 1.0
#
#  (c) 2015 zap (zap01 <at> t-online <dot> de)
#
################################################################
#
#  define <name> HMCCUDEV <hmccu> <ccudev>
#
#  set <name> datapoint <channel>.<datapoint> <value>
#  set <name> devstate <channel> <value>
#
#  get <name> datapoint <channel>.<datapoint>
#
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> statechannel <channel>
#  attr <name> stateval <text1>:<subtext1>[,...]
#  attr <name> substitute <regexp1>:<subtext1>[,...]
#
################################################################
#  Requires module 88_HMCCU
################################################################

package main;

use strict;
use warnings;
use SetExtensions;

sub HMCCUDEV_Define ($$);
sub HMCCUDEV_Set ($@);
sub HMCCUDEV_Get ($@);
sub HMCCUDEV_Attr ($@);
sub HMCCUDEV_SetError ($$);

#####################################
# Initialize module
#####################################

sub HMCCUDEV_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "HMCCUDEV_Define";
	$hash->{SetFn} = "HMCCUDEV_Set";
	$hash->{GetFn} = "HMCCUDEV_Get";
	$hash->{AttrFn} = "HMCCUDEV_Attr";

	$hash->{AttrList} = "IODev ccureadings:0,1 stateval substitute statechannel:0,1,2,3 loglevel:0,1,2,3,4,5,6 ". $readingFnAttributes;
}

#####################################
# Define device
#####################################

sub HMCCUDEV_Define ($$)
{
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);

	return "Specifiy the CCU device name as parameters" if(@a < 3);
	return "Channel or datapoint not allowed in CCU device name" if ($a[2] =~ /^(.*):/);

	$attr{$name}{ccureadings} = 1;
  
	# Keep name of CCU device
	$hash->{ccudev} = $a[2];

	# Inform HMCCU device about client device
	Log 1, "HMCCUDEV: Assigning IO Port";
	AssignIoPort ($hash);

	readingsSingleUpdate ($hash, "state", "Initialized", 1);

	return undef;
}

#####################################
# Set attribute
#####################################

sub HMCCUDEV_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;

	if (defined ($attrval)) {
		if ($cmd eq "set" && $attrname eq "IODev") {
			$defs{$name}{IODev} = $defs{$attrval};
		}
	}

	return undef;
}

#####################################
# Set commands
#####################################

sub HMCCUDEV_Set ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;

	if (!defined ($hash->{IODev})) {
		return HMCCUDEV_SetError ($hash, "No IO device defined");
	}

	my $statechannel = AttrVal ($name, "statechannel", '');
	my $stateval = AttrVal ($name, "stateval", '');
	my $substitute = AttrVal ($name, "substitute", '');

	my $hmccu_hash = $hash->{IODev};
	my $hmccu_name = $hash->{IODev}->{NAME};
	my $ccudev = $hash->{ccudev};

	# process set <name> command par1 ...
	if ($opt eq 'datapoint') {
		my $objname = shift @a;
		my $objvalue = join ('%20', @a);

		if (!defined ($objname) || $objname !~ /^[0-9]+\..*$/ || !defined ($objvalue)) {
			return HMCCUDEV_SetError ($hash, "Usage: set <device> datapoint <channel>.<datapoint> <value>");
		}

		$objname = $ccudev.':'.$objname;

		my ($dev, $chn, $dpt, $flags) = HMCCU_ParseCCUDev ($objname);
		if ($flags != 7) {
			return HMCCUDEV_SetError ($hash, "Format for objname is channel.datapoint");
		}

		$objvalue = HMCCU_Substitute ($objvalue, $substitute);
		HMCCU_Set ($hmccu_hash, $hmccu_name, 'datapoint', $objname, $objvalue);
		usleep (100000);
		HMCCU_Get ($hmccu_hash, $hmccu_name, 'datapoint', $objname);

		return undef;
	}
	elsif ($opt eq 'devstate' || $opt eq 'on' || $opt eq 'off') {
		my $objvalue = ($opt eq 'on' || $opt eq 'off') ? $opt : join ('%20', @a);

		if ($statechannel eq '') {
			return HMCCUDEV_SetError ($hash, "No STATE channel specified");
		}
		if (!defined ($objvalue)) {
			return HMCCUDEV_SetError ($hash, "Usage: set <device> devstate <value>");
		}

		my $objname = $ccudev.':'.$statechannel.'.STATE';
		$objvalue = HMCCU_Substitute ($objvalue, $stateval);
		HMCCU_Set ($hmccu_hash, $hmccu_name, 'datapoint', $objname, $objvalue);
		usleep (100000);
		HMCCU_Get ($hmccu_hash, $hmccu_name, 'datapoint', $objname);

		return undef;
	}
	else {
		my $retmsg = "HMCCUDEV: Unknown argument $opt, choose one of datapoint on:noArg off:noArg";
		if ($stateval ne '') {
			my @valpairs = split /,/, $stateval;
			my $sep = " devstate:";
			foreach my $vp (@valpairs) {
				my @sv = split /:/, $vp;
				if (@sv == 2) {
					$retmsg .= $sep . $sv[0];
					$sep = "," if ($sep ne ',');
				}
			}
		}
		else {
			$retmsg .= " devstate";
		}

		return $retmsg;
	}
}

#####################################
# Get commands
#####################################

sub HMCCUDEV_Get ($@)
{
	my ($hash, @a) = @_;
	my $name = shift @a;
	my $opt = shift @a;

	if (!defined ($hash->{IODev})) {
		return HMCCUDEV_SetError ($hash, "No IO device defined");
	}

	my $hmccu_hash = $hash->{IODev};
	my $hmccu_name = $hash->{IODev}->{NAME};
	my $ccudev = $hash->{ccudev};

	if ($opt eq 'datapoint') {
		my $objname = shift @a;
		if (!defined ($objname) || $objname !~ /^[0-9]+\..*$/) {
			return HMCCUDEV_SetError ($hash, "Usage: get <device> datapoint <channel>.<datapoint>");
		}

		$objname = $ccudev.':'.$objname;
		my ($dev, $chn, $dpt, $flags) = HMCCU_ParseCCUDev ($objname);
		if ($flags != 7) {
			return HMCCUDEV_SetError ($hash, "Format for objname is channel.datapoint");
		}

		HMCCU_Get ($hmccu_hash, $hmccu_name, 'datapoint', $objname);

		return undef;
	}
	else {
		return "HMCCUDEV: Unknown argument $opt, choose one of datapoint";
	}
}

sub HMCCUDEV_SetError ($$)
{
	my ($hash, $text) = @_;
	my $name = $hash->{NAME};

	$text = "HMCCUDEV: ".$name." ". $text;
	readingsSingleUpdate ($hash, "state", "Error", 1);
	Log 1, $text;
	return $text;
}

1;

=pod
=begin html

<a name="HMCCUDEV"></a>
<h3>HMCCUDEV</h3>
<div style="width:800px"> 
<ul>
   The module implements client devices for HMCCU.
   </br></br>
   <a name="HMCCUDEVdefine"></a>
   <b>Define</b>
   <ul>
      <br/>
      <code>define &lt;name&gt; HMCCUDEV &lt;<i>CCU_Device</i>&gt;</code>
      <br/><br/>
      Example:
      <br/>
      <code>define window_living HMCCUDEV WIN-LIV-1</code>
      <br/><br/>
      <i>CCU_Device</i> - Name of device in CCU without channel or datapoint.
      <br/>
   </ul>
   <br/>
   
   <a name="HMCCUDEVset"></a>
   <b>Set</b><br/>
   <ul>
      <br/>
      <li>set &lt;<i>Name</i>&gt; devstate &lt;<i>Value</i>&gt;
         <br/>
         Set state of a CCU device channel. Channel must be defined as attribute
         statechannel.
         <br/><br/>
         Example:<br/>
         <code>set light_entrance devstate on</code>
      </li><br/>
      <li>set &lt;<i>Name</i>&gt; { on | off }
         <br/>
         Set state of a CCU device channel is set to 'on' or 'off'. Channel must
         be defined as attribute statechannel. State values 'on' and 'off' can 
         be replaced by setting attribute stateval.
      </li><br/>
      <li>set &lt;<i>Name</i>&gt; datapoint &lt;<i>channel</i>.<i>datapoint</i>&gt; &lt;<i>Value</i>&gt;
        <br/>
        Set value of a datapoint of a CCU device channel.
        <br/><br/>
        Example:<br/>
        <code>set temp_control datapoint TEMP_CONTROL:2.SET_TEMPERATURE 21</code>
      </li><br/>
   </ul>
   <br/>
   
   <a name="HMCCUDEVget"></a>
   <b>Get</b><br/>
   <ul>
      <br/>
      <li>get &lt;<i>Name</i>&gt; datapoint &lt;<i>Device</i>:<i>Channel</i>.<i>datapoint</i>&gt;
         <br/>
         Get state of a CCU device datapoint.
      </li><br/>
   </ul>
   <br/>
   
   <a name="HMCCUDEVattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
      <li>ccureadings &lt;0 | 1&gt;
         <br/>
            If set to 1 values read from CCU will be stored as readings.
      </li><br/>
      <li>statechannel &lt;<i>Channel</i>&gt;
         <br/>
            Channel for setting device state by devstate command.
      </li><br/>
      <li>stateval &lt;<i>text</i>:<i>text</i>[,...]&gt;
         <br/>
            Define substitution for set commands values.
      </li><br/>
      <li>substitude &lt;<i>expression</i>:<i>string</i>[,...]&gt;
         <br/>
            Define substitions for reading values. Substitutions for parfile values must
            be specified in parfiles.
      </li><br/>
   </ul>
</ul>
</div>

=end html
=cut

