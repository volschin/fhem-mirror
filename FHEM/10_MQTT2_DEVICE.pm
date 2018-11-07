##############################################
# $Id$
package main;

use strict;
use warnings;
use SetExtensions;

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
    bridgeRegexp:textField-long
    devicetopic
    disable:0,1
    disabledForIntervals
    model
    readingList:textField-long
    setList:textField-long
    getList:textField-long
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList)." ".$readingFnAttributes;
  my %h = ( re=>{}, cid=>{}, bridge=>{} );
  $modules{MQTT2_DEVICE}{defptr} = \%h;
}


#############################
sub
MQTT2_DEVICE_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = shift @a;
  my $type = shift @a; # always MQTT2_DEVICE
  $hash->{CID} = shift(@a) if(@a);

  return "wrong syntax for $name: define <name> MQTT2_DEVICE [clientid]"
        if(int(@a));
  $hash->{DEVICETOPIC} = $name;
  $modules{MQTT2_DEVICE}{defptr}{cid}{$hash->{CID}} = $hash if($hash->{CID});

  AssignIoPort($hash);
  return undef;
}

#############################
sub
MQTT2_DEVICE_Parse($$)
{
  my ($iodev, $msg) = @_;
  my $ioname = $iodev->{NAME};
  my %fnd;

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

  my $autocreate;
  if($msg =~ m/^autocreate:(.*)/) {
    $msg = $1;
    $autocreate = 1;
  }

  my ($cid, $topic, $value) = split(":", $msg, 3);
  my $dp = $modules{MQTT2_DEVICE}{defptr}{re};
  foreach my $re (keys %{$dp}) {
    my $reAll = $re;
    $reAll =~ s/\$DEVICETOPIC/\.\*/g;

    next if(!("$topic:$value" =~ m/^$reAll$/s ||
              "$cid:$topic:$value" =~ m/^$reAll$/s));
    foreach my $dev (keys %{$dp->{$re}}) {
      next if(IsDisabled($dev));
      my $hash = $defs{$dev};
      my $reRepl = $re;
      $reRepl =~ s/\$DEVICETOPIC/$hash->{DEVICETOPIC}/g;
      next if(!("$topic:$value" =~ m/^$reRepl$/s ||
                "$cid:$topic:$value" =~ m/^$reRepl$/s));

      my @retData;
      my $code = $dp->{$re}{$dev};
      Log3 $dev, 4, "MQTT2_DEVICE_Parse: $dev $topic => $code";

      if($code =~ m/^{.*}$/s) {
        $code = EvalSpecials($code, ("%TOPIC"=>$topic, "%EVENT"=>$value,
                 "%DEVICETOPIC"=>$hash->{DEVICETOPIC}, "%NAME"=>$hash->{NAME}));
        my $ret = AnalyzePerlCommand(undef, $code);
        if($ret && ref $ret eq "HASH") {
          readingsBeginUpdate($hash);
          foreach my $k (keys %{$ret}) {
            readingsBulkUpdate($hash, $k, $ret->{$k});
            push(@retData, "$k $ret->{$k}");
            checkForGet($hash, $k, $ret->{$k});
          }
          readingsEndUpdate($hash, 1);
        }

      } else {
        readingsSingleUpdate($hash, $code, $value, 1);
        push(@retData, "$code $value");
        checkForGet($hash, $code, $value);
      }

      $fnd{$dev} = 1;
    }
  }

  # autocreate and expand readingList
  if($autocreate && !%fnd) {
    return "" if($cid && $cid =~ m/mosqpub.*/);

    ################## bridge stuff
    my $newCid = $cid;
    my $bp = $modules{MQTT2_DEVICE}{defptr}{bridge};
    foreach my $re (keys %{$bp}) {
      next if(!("$topic:$value" =~ m/^$re$/s ||
                "$cid:$topic:$value" =~ m/^$re$/s));
      my $cidExpr = $bp->{$re};
      $newCid = eval $cidExpr;
      if($@) {
        Log 1, "MQTT2_DEVICE: Error evaluating $cidExpr: $@";
        return "";
      }
      last;
    }
    return if(!$newCid);

    my $cidHash = $modules{MQTT2_DEVICE}{defptr}{cid}{$newCid};
    my $nn = $cidHash ? $cidHash->{NAME} : "MQTT2_$newCid";
    PrioQueue_add(sub{
      return if(!$defs{$nn});
      my $add;
      if($value =~ m/^{.*}$/) {
        my $ret = json2nameValue($value);
        $add = "{ json2nameValue(\$EVENT) }" if(keys %{$ret});
      }
      if(!$add) {
        $topic =~ m,.*/([^/]+),;
        $add = ($1 ? $1 : $topic);
      }
      my $rl = AttrVal($nn, "readingList", "");
      $rl .= "\n" if($rl);
      CommandAttr(undef, "$nn readingList $rl$cid:$topic:.* $add");
      MQTT2_DEVICE_Parse($iodev, $msg);
    }, undef);

    return "UNDEFINED $nn MQTT2_DEVICE $newCid" if(!$cidHash);
    return "";
  }

  return keys %fnd;
}

# compatibility: the first version was implemented as MQTT2_JSON and published.
sub
MQTT2_JSON($;$)
{
  return json2nameValue($_[0], $_[1]);
}

sub
MQTT2_getCmdHash($)
{
  my ($list) = @_;
  my (%h, @cmd);
  map { 
    my ($k,$v) = split(" ",$_,2);
    push @cmd, $k;
    $k =~ s/:.*//; # potential arguments
    $h{$k} = $v;
  }
  grep /./,
  split("\n", $list);
  return (\%h, join(" ",@cmd));
}

#############################
# replace {} and $EVENT. Used both in set and get
sub
MQTT2_buildCmd($$$)
{
  my ($hash, $a, $cmd) = @_;

  shift @{$a};
  if($cmd =~ m/^{.*}$/) {
    $cmd = EvalSpecials($cmd, ("%EVENT"=>join(" ",@{$a}), "%NAME"=>$hash->{NAME}));
    $cmd = AnalyzeCommandChain($hash->{CL}, $cmd);
    return if(!$cmd);

  } else {
    if($cmd =~ m/\$EV/) {       # replace EVENT & $EVTPART
      my $event = join(" ",@{$a});
      $cmd =~ s/\$EVENT/$event/g;
      for(my $i=0; $i<@{$a}; $i++) {
        my $n = "\\\$EVTPART$i";
        $cmd =~ s/$n/$a->[$i]/ge;
      }
    } else {
      shift @{$a};
      $cmd .= " ".join(" ",@{$a}) if(@{$a});
    }
  }

  $cmd =~ s/\$DEVICETOPIC/$hash->{DEVICETOPIC}/g;
  return $cmd;
}

#############################
sub
MQTT2_DEVICE_Get($@)
{
  my ($hash, @a) = @_;
  return "Not enough arguments for get" if(!defined($a[1]));

  my ($gets,$cmdList) = MQTT2_getCmdHash(AttrVal($hash->{NAME}, "getList", ""));
  return "Unknown argument $a[1], choose one of $cmdList" if(!$gets->{$a[1]});
  return undef if(IsDisabled($hash->{NAME}));

  my ($getReading, $cmd) = split(" ",$gets->{$a[1]},2);
  if($hash->{CL}) {
    my $tHash = { hash=>$hash, CL=>$hash->{CL}, reading=>$getReading };
    $hash->{asyncGet} = $tHash;
    InternalTimer(gettimeofday()+4, sub {
      asyncOutput($tHash->{CL}, "Timeout reading answer for $cmd");
      delete($hash->{asyncGet});
    }, $tHash, 0);
  }

  $cmd = MQTT2_buildCmd($hash, \@a, $cmd);
  return if(!$cmd);
  IOWrite($hash, split(" ",$cmd,2));

  return undef;
}

#############################
sub
MQTT2_DEVICE_Set($@)
{
  my ($hash, @a) = @_;
  return "Not enough arguments for set" if(!defined($a[1]));

  my ($sets,$cmdList) = MQTT2_getCmdHash(AttrVal($hash->{NAME}, "setList", ""));
  my $cmdName = $a[1];
  my $cmd = $sets->{$cmdName};
  return SetExtensions($hash, $cmdList, @a) if(!$cmd);
  return undef if(IsDisabled($hash->{NAME}));

  $cmd = MQTT2_buildCmd($hash, \@a, $cmd);
  return if(!$cmd);
  IOWrite($hash, split(" ",$cmd,2));
  readingsSingleUpdate($hash, "state", $cmdName, 1);
  return undef;
}


sub
MQTT2_DEVICE_Attr($$)
{
  my ($type, $dev, $attrName, $param) = @_;
  my $hash = $defs{$dev};

  if($attrName eq "devicetopic") {
    $hash->{DEVICETOPIC} = ($type eq "del" ? $hash->{NAME} : $param);
    return undef;
  }

  if($attrName =~ m/(.*)List/) {
    my $atype = $1;

    if($type eq "del") {
      MQTT2_DEVICE_delReading($dev) if($atype eq "reading");
      return undef;
    }

    return "$dev attr $attrName: more parameters needed" if(!$param); #90145

    foreach my $el (split("\n", $param)) {
      my ($par1, $par2) = split(" ", $el, 2);
      next if(!$par1);

      (undef, $par2) = split(" ", $par2, 2) if($type eq "get");
      return "$dev attr $attrName: more parameters needed" if(!$par2);

      if($atype eq "reading") {
        if($par2 =~ m/^{.*}$/) {
          my $ret = perlSyntaxCheck($par2, 
                ("%TOPIC"=>1, "%EVENT"=>"0 1 2 3 4 5 6 7 8 9",
                 "%NAME"=>$dev, "%DEVICETOPIC"=>$hash->{DEVICETOPIC}));
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
    MQTT2_DEVICE_addReading($dev, $param) if($atype eq "reading");
  }

  if($attrName eq "bridgeRegexp" && $type eq "set") {
    foreach my $el (split("\n", $param)) {
      my ($par1, $par2) = split(" ", $el, 2);
      next if(!$par1);
      return "$dev attr $attrName: more parameters needed" if(!$par2);
      eval { "Hallo" =~ m/^$par1$/ };
      return "$dev $attrName regexp error: $@" if($@);
      $modules{MQTT2_DEVICE}{defptr}{bridge}{$par1} = $par2;
    }
  }

  return undef;
}

sub
MQTT2_DEVICE_delReading($)
{
  my ($name) = @_;
  my $dp = $modules{MQTT2_DEVICE}{defptr}{re};
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
    $modules{MQTT2_DEVICE}{defptr}{re}{$re}{$name} = $code if($re && $code);
  }
}


#####################################
sub
MQTT2_DEVICE_Rename($$)
{
  my ($new, $old) = @_;
  MQTT2_DEVICE_delReading($old);
  MQTT2_DEVICE_addReading($new, AttrVal($new, "readingList", ""));
  return undef;
}

#####################################
sub
MQTT2_DEVICE_Undef($$)
{
  my ($hash, $arg) = @_;
  MQTT2_DEVICE_delReading($arg);
  delete $modules{MQTT2_DEVICE}{defptr}{cid}{$hash->{CID}} if($hash->{CID});
  return undef;
}

1;

=pod
=item summary    devices communicating via the MQTT2_SERVER or MQTT2_CLIENT
=item summary_DE &uuml;ber den MQTT2_SERVER oder MQTT2_CLIENT kommunizierende Ger&auml;te
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

    <a name="bridgeRegexp"></a>
    <li>bridgeRegexp &lt;regexp&gt; newClientId ...<br>
      Used to automatically redirect some types of topics to different
      MQTT2_DEVICE instances. The regexp is checked against the
      clientid:topic:message and topic:message. The newClientId is a perl
      expression!. Example:
      <ul>
        attr zigbee2mqtt bridgeRegexp zigbee2mqtt/0x00158d0001([^:]*):.*
                "zigbee_$1"
      </ul>
      will create different MQTT2_DEVICE instances for different hex numbers in
      the topic. Note: the newClientId is enclosed in "", as it is a perl
      expression, should be unique, and the automatically created device will
      be created also with this name.

      Multiple tuples of &lt;regexp&gt; newClientId are separated by newline.
      </li><br>

    <a name="devicetopic"></a>
    <li>devicetopic value<br>
      replace $DEVICETOPIC in the topic part of readingList, setList and
      getList with value. if not set, $DEVICETOPIC will be replaced with the
      name of the device.
      </li><br>

    <li><a href="#disable">disable</a><br>
        <a href="#disabledForIntervals">disabledForIntervals</a></li><br>

    <a name="readingList"></a>
    <li>readingList &lt;regexp&gt; [readingName|perl-Expression] ...
      <br>
      If the regexp matches topic:message or cid:topic:message either set
      readingName to the published message, or evaluate the perl expression,
      which has to return a hash consisting of readingName=>readingValue
      entries.
      You can define multiple such tuples, separated by newline, the newline
      does not have to be entered in the FHEMWEB frontend. cid is the client-id
      of the sending device.<br>
      Example:<br>
      <code>
        &nbsp;&nbsp;attr dev readingList\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;myDev/temp:.* temperature\<br>
        &nbsp;&nbsp;&nbsp;&nbsp;myDev/hum:.* { { humidity=>$EVTPART0 } }<br>
      </code><br>
      Notes:
      <ul>
        <li>in the perl expression the variables $TOPIC, $NAME, $DEVICETOPIC 
          and $EVENT are available (the letter containing the whole message),
          as well as $EVTPART0, $EVTPART1, ... each containing a single word of
          the message.</li>
        <li>the helper function json2nameValue($EVENT) can be used to parse a
          json encoded value. Importing all values from a Sonoff device with a
          Tasmota firmware can be done with:
          <ul><code>
            attr sonoff_th10 readingList tele/sonoff/S.* {
                json2nameValue($EVENT) }
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
        <li>arguments to the set command will be appended to the message
          published (not for the perl expression)</li>
        <li>the command arguments are available as $EVENT, $EVTPART0, etc.,
          bot in the perl expression and the "normal" topic variant.</li>
        <li>the perl expression must return a string containing the topic and
          the message separated by a space.</li>
        <li>SetExtensions is activated</li>
        <li>if the topic name ends with :r, then the retain flag is set</li>
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
        <li>the command arguments are available as $EVENT, $EVTPART0, etc.
          </li>
        <li>the perl expression must return a string containing the topic and
          the message separated by a space.</li>
      </ul>
      </li><br>

  </ul>
</ul>

=end html
=cut
