##############################################
# $Id: 10_FBDECT.pm 2779 2013-02-21 08:52:27Z rudolfkoenig $
package main;

# TODO: test multi-dev, test on the FB

use strict;
use warnings;
use SetExtensions;

sub FBDECT_Parse($$@);
sub FBDECT_Set($@);
sub FBDECT_Get($@);
sub FBDECT_Cmd($$@);

my @fbdect_models = qw(
  "AVM FRITZ!Dect Powerline 546E"
  "AVM FRITZ!Dect 200"
);

my %fbdect_payload = (
   7 => { n=>"connected" },
   8 => { n=>"disconnected" },
  10 => { n=>"configChanged" },
  15 => { n=>"state",       fmt=>'hex($pyld)?"on":"off"' },
  18 => { n=>"current",     fmt=>'sprintf("%0.4f A", hex($pyld)/10000)' },
  19 => { n=>"voltage",     fmt=>'sprintf("%0.3f V", hex($pyld)/1000)' },
  20 => { n=>"power",       fmt=>'sprintf("%0.2f W", hex($pyld)/100)' },
  21 => { n=>"energy",      fmt=>'sprintf("%0.0f Wh",hex($pyld))' },
  22 => { n=>"powerFactor", fmt=>'sprintf("%0.3f", hex($pyld))' },
  23 => { n=>"temperature", fmt=>'sprintf("%0.1f C", hex($pyld)/10)' },
);


sub
FBDECT_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}     = ".*";
  $hash->{SetFn}     = "FBDECT_Set";
  $hash->{GetFn}     = "FBDECT_Get";
  $hash->{DefFn}     = "FBDECT_Define";
  $hash->{UndefFn}   = "FBDECT_Undef";
  $hash->{ParseFn}   = "FBDECT_Parse";
  $hash->{AttrList}  = 
    "IODev do_not_notify:1,0 ignore:1,0 dummy:1,0 showtime:1,0 ".
    "loglevel:0,1,2,3,4,5,6 $readingFnAttributes " .
    "model:".join(",", sort @fbdect_models);
}


#############################
sub
FBDECT_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name   = shift @a;
  my $type = shift(@a); # always FBDECT

  my $u = "wrong syntax for $name: define <name> FBDECT id props";
  return $u if(int(@a) != 2);

  my $id = shift @a;
  return "define $name: wrong id ($id): need a number"
                   if( $id !~ m/^\d+$/i );
  $hash->{id} = $id;
  $hash->{props} = shift @a;

  $modules{FBDECT}{defptr}{$id} = $hash;
  AssignIoPort($hash);
  return undef;
}
 
###################################
my %sets = ("on"=>1, "off"=>1);
sub
FBDECT_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $cmd = $a[1];

  if(!$sets{$cmd}) {
    return SetExtensions($hash, join(" ", sort keys %sets), @a);
  }
  my $relay = sprintf("%08x%04x0000%08x", 15, 4, $cmd eq "on" ? 1 : 0);
  my $msg = sprintf("%04x0000%08x$relay", $hash->{id}, length($relay)/2);
  IOWrite($hash, "07", $msg);
  readingsSingleUpdate($hash, "state", "set_$cmd", 1);
  return undef;
}

my %gets = ("devInfo"=>1);
sub
FBDECT_Get($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $cmd = ($a[1] ? $a[1] : "");

  if(!$gets{$cmd}) {
    return "Unknown argument $cmd, choose one of ".join(" ", sort keys %gets);
  }

  if($cmd eq "devInfo") {
    my @answ = FBAHA_getDevList($hash->{IODev}, $hash->{id});
    return $answ[0] if(@answ == 1);
    my $d = pop @answ;
    my $state = "inactive" if($answ[0] =~ m/ inactive,/);
    while($d) {
      my ($ptyp, $plen, $pyld) = FBDECT_decodePayload($d);
      if($ptyp eq "state" && 
         ReadingsVal($hash->{NAME}, $ptyp, "") ne $pyld) {
        readingsSingleUpdate($hash, $ptyp, ($state ? $state : $pyld), 1);
      }
      push @answ, "  $ptyp: $pyld";
      $d = substr($d, 16+$plen*2);
    }
    return join("\n", @answ);
  }
  return undef;
}

###################################
sub
FBDECT_Parse($$@)
{
  my ($iodev, $msg, $local) = @_;
  my $ioName = $iodev->{NAME};

  my $mt = substr($msg, 0, 2);
  if($mt ne "07" && $mt ne "04") {
    Log 1, "FBDECT: unknown message type $mt";
    return;
  }

  my $id = hex(substr($msg, 16, 4));
  my $hash = $modules{FBDECT}{defptr}{$id};
  if(!$hash) {
    my $ret = "UNDEFINED FBDECT_$id FBDECT $id switch";
    Log 1, $ret;
    DoTrigger("global", $ret);
    return "";
  }

  readingsBeginUpdate($hash);

  if($mt eq "07") {
    my $d = substr($msg, 32);
    while($d) {
      my ($ptyp, $plen, $pyld) = FBDECT_decodePayload($d);
      readingsBulkUpdate($hash, $ptyp, $pyld);
      $d = substr($d, 16+$plen*2);
    }
  }
  if($mt eq "04") {
    my @answ = FBAHA_configInd(substr($msg,16), $id);
    my $state = "";
    if($answ[0] =~ m/ inactive,/) {
      $state = "inactive";

    } else {
      my $d = pop @answ;
      while($d) {
        my ($ptyp, $plen, $pyld) = FBDECT_decodePayload($d);
        last if(!$plen);
        push @answ, "  $ptyp: $pyld";
        $d = substr($d, 16+$plen*2);
      }
      # Ignore the rest, is too confusing.
      @answ = grep /state:/, @answ;
      (undef, $state) = split(": ", $answ[0], 2);
    }
    readingsBulkUpdate($hash, "state", $state);
  }

  readingsEndUpdate($hash, 1);

  return $hash->{NAME};
}

sub
FBDECT_decodePayload($)
{
  my ($d) = @_;
  my $ptyp = hex(substr($d, 0, 8));
  my $plen = hex(substr($d, 8, 4));
  my $pyld = substr($d, 16, $plen*2);
  if($fbdect_payload{$ptyp}) {
    $pyld = eval $fbdect_payload{$ptyp}{fmt} if($fbdect_payload{$ptyp}{fmt});
    $ptyp = $fbdect_payload{$ptyp}{n};
  }
  return ($ptyp, $plen, $pyld);
}

#####################################
sub
FBDECT_Undef($$)
{
  my ($hash, $arg) = @_;
  my $homeId = $hash->{homeId};
  my $id = $hash->{id};
  delete $modules{FBDECT}{defptr}{$id};
  return undef;
}

1;

=pod
=begin html

<a name="FBDECT"></a>
<h3>FBDECT</h3>
<ul>
  This module is used to control AVM FRITZ!DECT devices via FHEM, see also the
  <a href="#FBAHA">FBAHA</a> module for the base.
  <br><br>
  <a name="FBDECTdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FBDECT &lt;homeId&gt; &lt;id&gt; [classes]</code>
  <br>
  <br>
  &lt;id&gt; is the id of the device, the classes argument ist ignored for now.
  <br>
  Example:
  <ul>
    <code>define lamp FBDECT 16 switch,powerMeter</code><br>
  </ul>
  <b>Note:</b>Usually the device is created via
  <a href="#autocreate">autocreate</a>
  </ul>
  <br>
  <br

  <a name="FBDECTset"></a>
  <b>Set</b>
  <ul>
  <li>on/off<br>
  set the device on or off.</li>
  <li>
   <a href="#setExtensions">set extensions</a> are supported.</li>
  </ul>
  <br>

  <a name="FBDECTget"></a>
  <b>Get</b>
  <ul>
  <li>devInfo<br>
  report device information</li>
  </ul>
  <br>

  <a name="FBDECTattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#model">model</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

  <a name="FBDECTevents"></a>
  <b>Generated events:</b>
  <ul>
    <li>on</li>
    <li>off</li>
    <li>set_on</li>
    <li>set_off</li>
    <li>current: $v A</li>
    <li>voltage: $v V</li>
    <li>power: $v W</li>
    <li>energy: $v Wh</li>
    <li>powerFactor: $v"</li>
    <li>temperature: $v C</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="FBDECT"></a>
<h3>FBDECT</h3>
<ul>
  Dieses Modul wird verwendet, um AVM FRITZ!DECT Ger&auml;te via FHEM zu
  steuern, siehe auch das <a href="#FBAHA">FBAHA</a> Modul f&uumlr die
  Anbindung an das FRITZ!Box.
  <br><br>
  <a name="FBDECTdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FBDECT &lt;homeId&gt; &lt;id&gt; [classes]</code>
  <br>
  <br>
  &lt;id&gt; ist das Ger&auml;te-ID, das Argument wird z.Zt ignoriert.
  <br>
  Beispiel:
  <ul>
    <code>define lampe FBDECT 16 switch,powerMeter</code><br>
  </ul>
  <b>Achtung:</b>FBDECT Eintr&auml;ge werden noralerweise per 
  <a href="#autocreate">autocreate</a> angelegt.
  </ul>
  <br>
  <br

  <a name="FBDECTset"></a>
  <b>Set</b>
  <ul>
  <li>on/off<br>
  Ger&auml;t einschalten bzw. ausschalten.</li>
  <li>
  Die <a href="#setExtensions">set extensions</a> werden unterst&uuml;tzt.</li>
  </ul>
  <br>

  <a name="FBDECTget"></a>
  <b>Get</b>
  <ul>
  <li>devInfo<br>
  meldet Ger&auml;te-Informationen.</li>
  </ul>
  <br>

  <a name="FBDECTattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#model">model</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

  <a name="FBDECTevents"></a>
  <b>Generierte events:</b>
  <ul>
    <li>on</li>
    <li>off</li>
    <li>set_on</li>
    <li>set_off</li>
    <li>current: $v A</li>
    <li>voltage: $v V</li>
    <li>power: $v W</li>
    <li>energy: $v Wh</li>
    <li>powerFactor: $v"</li>
    <li>temperature: $v C</li>
  </ul>
</ul>
=end html_DE

=cut
