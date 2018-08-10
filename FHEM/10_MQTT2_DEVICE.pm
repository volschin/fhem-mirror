##############################################
# $Id$
package main;

use strict;
use warnings;
use SetExtensions;

sub MQTT2_JSON($;$);

sub
MQTT2_DEVICE_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}    = ".*";
  $hash->{SetFn}    = "MQTT2_DEVICE_Set";
  $hash->{GetFn}    = "MQTT2_DEVICE_Get";
  $hash->{DefFn}    = "MQTT2_DEVICE_Define";
  $hash->{UndefFn}  = "MQTT2_DEVICE_Undef";
  $hash->{AttrFn}   = "MQTT2_DEVICE_Attr";
  $hash->{ParseFn}  = "MQTT2_DEVICE_Parse";
  $hash->{RenameFn} = "MQTT2_DEVICE_Rename";

  no warnings 'qw';
  my @attrList = qw(
    IODev
    disable:0,1
    disabledForIntervals
    readingList:textField-long
    setList:textField-long
    getList:textField-long
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." ".$readingFnAttributes;
  $modules{MQTT2_DEVICE}{defptr} = ();
}


#############################
sub
MQTT2_DEVICE_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = shift @a;
  my $type = shift @a; # always MQTT2_DEVICE

  return "wrong syntax for $name: define <name> MQTT2_DEVICE" if(int(@a));

  AssignIoPort($hash);
  return undef;
}

#############################
sub
MQTT2_DEVICE_Parse($$)
{
  my ($iodev, $msg) = @_;
  my $ioname = $iodev->{NAME};
  my @ret;

  sub
  checkForGet($$$)
  {
    my ($hash, $key, $value) = @_;
    if($hash->{asyncGet} && $key eq $hash->{asyncGet}{reading}) {
      RemoveInternalTimer($hash->{asyncGet});
      asyncOutput($hash->{asyncGet}{CL}, "$key $value");
      delete($hash->{asyncGet});
    }
  }

  my ($topic, $value) = split(":", $msg, 2);
  my $dp = $modules{MQTT2_DEVICE}{defptr};
  foreach my $re (keys %{$dp}) {
    next if($msg !~ m/^$re$/s);
    foreach my $dev (keys %{$dp->{$re}}) {
      next if(IsDisabled($dev));
      my @retData;
      my $code = $dp->{$re}{$dev};
      Log3 $dev, 4, "MQTT2_DEVICE_Parse: $dev $topic => $code";
      my $hash = $defs{$dev};

      if($code =~ m/^{.*}$/s) {
        $code = EvalSpecials($code, ("%TOPIC"=>$topic, "%EVENT"=>$value));
        my $ret = AnalyzePerlCommand(undef, $code);
        readingsBeginUpdate($hash);
        foreach my $k (keys %{$ret}) {
          readingsBulkUpdate($hash, $k, $ret->{$k});
          push(@retData, "$k $ret->{$k}");
          checkForGet($hash, $k, $ret->{$k});
        }
        readingsEndUpdate($hash, 1);

      } else {
        readingsSingleUpdate($hash, $code, $value, 1);
        push(@retData, "$code $value");
        checkForGet($hash, $code, $value);
      }

      push @ret, $dev;
    }
  }

  return @ret;
}

#############################
# simple json reading parser
sub
MQTT2_JSON($;$)
{
  my ($in,$prefix) = @_;
  $prefix = "" if(!defined($prefix));
  my %ret;

  sub
  lquote($)
  {
    my ($t) = @_;
    my $esc;
    for(my $off = 1; $off < length($t); $off++){
      my $s = substr($t,$off,1);
      if($s eq '\\') { 
        $esc = !$esc;
      } elsif($s eq '"' && !$esc) {
        return (substr($t,1,$off-1), substr($t,$off+1));
      } else {
        $esc = 0;
      }
    }
    return ($t, "");    # error
  }

  sub
  lhash($)
  {
    my ($t) = @_;
    my $depth=1;
    my ($esc, $inquote);

    for(my $off = 1; $off < length($t); $off++){
      my $s = substr($t,$off,1);
      if($s eq '}') {
        $depth--;
        return (substr($t,1,$off-1), substr($t,$off+1)) if(!$depth);

      } elsif($s eq '{' && !$inquote) {
        $depth++;

      } elsif($s eq '"' && !$esc) {
        $inquote = !$inquote;

      } elsif($s eq '\\') {
        $esc = !$esc;

      } else {
        $esc = 0;
      }
    }
    return ($t, "");    # error
  }

  $in = $1 if($in =~ m/^{(.*)}$/s);

  while($in =~ m/^"([^"]+)"\s*:\s*(.*)$/s) {
    my ($name,$val) = ($1,$2);
    $name =~ s/[^a-z0-9._\-\/]/_/gsi;

    if($val =~ m/^"/) {
      ($val, $in) = lquote($val);
      $ret{"$prefix$name"} = $val;

    } elsif($val =~ m/^{/) { # }
      ($val, $in) = lhash($val);
      my $r2 = MQTT2_JSON($val);
      foreach my $k (keys %{$r2}) {
        $ret{"$prefix${name}_$k"} = $r2->{$k};
      }

    } elsif($val =~ m/^([0-9.-]+)(.*)$/s) {
      $ret{"$prefix$name"} = $1;
      $in = $2;

    } else {
      Log 1, "Error parsing $val";
      $in = "";
    }

    $in =~ s/^\s*,\s*//;
  }
  return \%ret;
}


#############################
sub
MQTT2_DEVICE_Get($@)
{
  my ($hash, @a) = @_;
  return "Not enough arguments for get" if(!defined($a[1]));

  my %gets;
  map {  my ($k,$v) = split(" ",$_,2); $gets{$k} = $v; }
        split("\n", AttrVal($hash->{NAME}, "getList", ""));
  return "Unknown argument $a[1], choose one of ".join(" ",sort keys %gets)
        if(!$gets{$a[1]});
  return undef if(IsDisabled($hash->{NAME}));

  my ($getReading, $cmd) = split(" ",$gets{$a[1]},2);
  if($hash->{CL}) {
    my $tHash = { hash=>$hash, CL=>$hash->{CL}, reading=>$getReading };
    $hash->{asyncGet} = $tHash;
    InternalTimer(gettimeofday()+4, sub {
      asyncOutput($tHash->{CL}, "Timeout reading answer for $cmd");
      delete($hash->{asyncGet});
    }, $tHash, 0);
  }

  shift @a;
  if($cmd =~ m/^{.*}$/) {
    $cmd = EvalSpecials($cmd, ("%EVENT"=>join(" ",@a)));
    $cmd = AnalyzeCommandChain($hash->{CL}, $cmd);
    return if(!$cmd);
  } else {
    shift @a;
    $cmd .= " ".join(" ",@a) if(@a);
  }

  IOWrite($hash, split(" ",$cmd,2));
  return undef;
}

#############################
sub
MQTT2_DEVICE_Set($@)
{
  my ($hash, @a) = @_;
  return "Not enough arguments for set" if(!defined($a[1]));

  my %sets;
  map {  my ($k,$v) = split(" ",$_,2); $sets{$k} = $v; }
        split("\n", AttrVal($hash->{NAME}, "setList", ""));
  my $cmd = $sets{$a[1]};
  return SetExtensions($hash, join(" ", sort keys %sets), @a) if(!$cmd);
  return undef if(IsDisabled($hash->{NAME}));

  shift @a;
  if($cmd =~ m/^{.*}$/) {
    $cmd = EvalSpecials($cmd, ("%EVENT"=>join(" ",@a)));
    $cmd = AnalyzeCommandChain($hash->{CL}, $cmd);
    return if(!$cmd);
  } else {
    shift @a;
    $cmd .= " ".join(" ",@a) if(@a);
  }
  IOWrite($hash, split(" ",$cmd,2));
  return undef;
}


sub
MQTT2_DEVICE_Attr($$)
{
  my ($type, $dev, $attrName, $param) = @_;

  if($attrName =~ m/(.*)List/) {
    my $type = $1;

    if($type eq "del") {
      MQTT2_DEVICE_delReading($dev) if($type eq "reading");
      return undef;
    }

    foreach my $el (split("\n", $param)) {
      my ($par1, $par2) = split(" ", $el, 2);
      next if(!$par1);

      (undef, $par2) = split(" ", $par2, 2) if($type eq "get");
      return "$dev attr $attrName: more parameters needed" if(!$par2);

      if($type eq "reading") {
        if($par2 =~ m/^{.*}$/) {
          my $ret = perlSyntaxCheck($par2,
                                ("%TOPIC"=>1, "%EVENT"=>"0 1 2 3 4 5 6 7 8 9"));
          return $ret if($ret);
        } else {
          return "unsupported character in readingname $par2"
              if(!goodReadingName($par2));
        }

      } else {
        my $ret = perlSyntaxCheck($par2, ("%EVENT"=>"0 1 2 3 4 5 6 7 8 9"));
        return $ret if($ret);

      }
    }
    MQTT2_DEVICE_addReading($dev, $param) if($type eq "reading");
  }
  return undef;
}

sub
MQTT2_DEVICE_delReading($)
{
  my ($name) = $_;
  my $dp = $modules{MQTT2_DEVICE}{defptr};
  foreach my $re (keys %{$dp}) {
    if($dp->{$re}{$name}) {
      delete($dp->{$re}{$name});
      delete($dp->{$re}) if(!int(keys %{$dp->{$re}}));
    }
  }
}

sub
MQTT2_DEVICE_addReading($$)
{
  my ($name, $param) = @_;
  foreach my $line (split("\n", $param)) {
    my ($re,$code) = split(" ", $line,2);
    $modules{MQTT2_DEVICE}{defptr}{$re}{$name} = $code;
  }
}


#####################################
sub
MQTT2_DEVICE_Rename($$)
{
  my ($new, $old) = @_;
  MQTT2_DEVICE_delReading($old);
  MQTT2_DEVICE_addReading($new, AttrVal($old, "readingList", ""));
  return undef;
}

#####################################
sub
MQTT2_DEVICE_Undef($$)
{
  my ($hash, $arg) = @_;
  MQTT2_DEVICE_delReading($arg);
  return undef;
}

1;

=pod
=item summary    devices communicating via the MQTT2_SERVER
=item summary_DE &uuml;ber den MQTT2_SERVER kommunizierende Ger&auml;te
=begin html

<a name="MQTT2_DEVICE"></a>
<h3>MQTT2_DEVICE</h3>
<ul>
  MQTT2_DEVICE is used to represent single devices connected to the
  MQTT2_SERVER. MQTT2_SERVER and MQTT2_DEVICE is intended to simplify
  connecting MQTT devices to FHEM.
  <br> <br>

  <a name="MQTT2_DEVICEdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MQTT2_DEVICE</code>
    <br><br>
    To enable a meaningful function you will need to set at least one of the
    readingList, setList or getList attributes below.<br>
  </ul>
  <br>

  <a name="MQTT2_DEVICEset"></a>
  <b>Set</b>
  <ul>
    see the setList attribute documentation below.
  </ul>
  <br>

  <a name="MQTT2_DEVICEget"></a>
  <b>Get</b>
  <ul>
    see the getList attribute documentation below.
  </ul>
  <br>

  <a name="MQTT2_DEVICEattr"></a>
  <b>Attributes</b>
  <ul>

    <li><a href="#disable">disable</a><br>
        <a href="#disabledForIntervals">disabledForIntervals</a></li><br>

    <a name="readingList"></a>
    <li>readingList &lt;topic-regexp&gt; [readingName|perl-Expression] ...<br>
      On receiving a topic matching the topic-regexp either set readingName to
      the published message, or evaluate the perl expression, which has to
      return a hash consisting of readingName=>readingValue entries.
      You can define multiple such tuples, separated by newline, the newline
      does not have to be entered in the FHEMWEB frontend.<br>
      Example:<br>
      <code>
        &nbsp;&nbsp;attr dev readingList\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;myDev/temp temperature\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;myDev/hum { { humidity=>$EVTPART0 } }<br>
      </code><br>
      Notes:
      <ul>
        <li>in the perl expression the variables $TOPIC and $EVENT are
          available (the letter containing the whole message), as well as
          $EVTPART0, $EVTPART1, ... each containing a single word of the
          message.</li>
        <li>the helper function MQTT2_JSON($EVENT) can be used to parse a json
          encoded value. Importing all values from a Sonoff device with a
          Tasmota firmware can be done with:
          <ul><code>
            attr sonoff_th10 readingList tele/sonoff/S.* { MQTT2_JSON($EVENT) }
          </code></ul></li>
      </ul>
      </li><br>

    <a name="setList"></a>
    <li>setList cmd [topic|perl-Expression] ...<br>
      When the FHEM command cmd is issued, publish the topic.
      Multiple tuples can be specified, each of them separated by newline, the
      newline does not have to be entered in the FHEMWEB frontend.
      Example:<br>
      <code>
        &nbsp;&nbsp;attr dev setList\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;on tasmota/sonoff/cmnd/Power1 on\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;off tasmota/sonoff/cmnd/Power1 off
      </code><br>
      This example defines 2 set commands (on and off), which both publish
      the same topic, but with different messages (arguments).<br>
      Notes:
      <ul>
        <li>Arguments to the set command will be appended to the message
          published (not for the perl expression)</li>
        <li>If using a perl expressions, the command arguments are available as
          $EVENT, $EVTPART0, etc. The perl expression must return a string
          containing the topic and the message separated by a space.</li>
        <li>SetExtensions is activated</li>
      </ul>
      </li><br>

    <a name="getList"></a>
    <li>getList cmd reading [topic|perl-Expression] ...<br>
      When the FHEM command cmd is issued, publish the topic, wait for the
      answer (the specified reading), and show it in the user interface.
      Multiple triples can be specified, each of them separated by newline, the
      newline does not have to be entered in the FHEMWEB frontend.<br>
      Example:<br>
      <code>
        &nbsp;&nbsp;attr dev getList\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;temp temperature myDev/cmd/getstatus\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;hum  hum  myDev/cmd/getStatus
      </code><br>
      This example defines 2 get commands (temp and hum), which both publish
      the same topic, but wait for different readings to be set.<br>
      Notes:
      <ul>
        <li>the readings must be parsed by a readingList</li>
        <li>get is asynchron, it is intended for frontends like FHEMWEB or
          telnet, the result cannot be used in self-written perl expressions.
          Use a set and a notify/DOIF/etc definition for such a purpose</li>
        <li>arguments to the get command will be appended to the message
          published (not for the perl expression)</li>
        <li>if using a perl expressions, the command arguments are available as
          $EVENT, $EVTPART0, etc. The perl expression must return a string
          containing the topic and the message separated by a space.</li>
      </ul>
      </li><br>

  </ul>
</ul>

=end html
=cut
