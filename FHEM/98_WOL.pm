##############################################
# $Id$
package main;

use strict;
use warnings;
use IO::Socket;
use Time::HiRes qw(gettimeofday);

sub
WOL_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "WOL_Set";
  $hash->{DefFn}     = "WOL_Define";
  $hash->{UndefFn}   = "WOL_Undef";
  $hash->{AttrList}  = "shutdownCmd loglevel:0,1,2,3,4,5,6";
}

###################################
sub
WOL_Set($@)
{
  my ($hash, @a) = @_;

  return "no set value specified" if(int(@a) < 2);
  return "Unknown argument $a[1], choose one of refresh on" if($a[1] eq "?");

  
  my $name = shift @a;
  my $v = join(" ", @a);
  my $logLevel = GetLogLevel($name,2);

  Log $logLevel, "WOL set $name $v";
  
  if($v eq "on") 
  {
    eval {
      for(my $i = 1; $i <= 3; $i++) {
        wake($hash, $logLevel);
      }
    };
    if ($@){
      ### catch block
      Log $logLevel, "WOL error: $@";
    };
    Log $logLevel, "WOL waking $name";
    
  } elsif ($v eq "refresh") 
  {
    WOL_GetUpdate($hash);
  } elsif ($v eq "off") {
    my $cmd = AttrVal($name, "shutdownCmd", "");
    if ($cmd eq "")
    {
      Log $logLevel, "No shutdown command given!";
      return "no shutdown command given (see shutdownCmd attribute)!"
    }
    `$cmd`;
  } else
  {
    return "unknown argument $v, choose one of refresh, on";
  }
  
  $hash->{CHANGED}[0] = $v;
  $hash->{STATE} = $v;
  $hash->{READINGS}{state}{TIME} = TimeNow();
  $hash->{READINGS}{state}{VAL} = $v;
  
  return undef;
}

sub
WOL_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> WOL MAC_ADRESS IP";
  return $u if(int(@a) < 4);
  
  $hash->{MAC} = $a[2];
  $hash->{IP} = $a[3];
  $hash->{INTERVAL} = 600;
  
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "WOL_GetUpdate", $hash, 0);
  return undef;
}

sub WOL_Undef($$) {

  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}

sub WOL_GetUpdate($)
{
  my ($hash) = @_;
  
  my $ip = $hash->{IP};
  #if (system("ping -q -c 1 $ip > /dev/null") == 0)
  ####
  #changed 2013-07-27 by UliM
  #based on Thread http://forum.fhem.de/index.php?t=msg&th=11823&goto=69801&rid=86#msg_69801
 #if (`ping -c 1 $ip`      =~ m/100/)
  if (`ping -c 1 -w 1 $ip` =~ m/100%/)
  {
    $hash->{READINGS}{state}{VAL} = "off";
    $hash->{READINGS}{isRunning}{VAL} = "false";
  } else
  {
    $hash->{READINGS}{state}{VAL} = "on";
    $hash->{READINGS}{isRunning}{VAL} = "true";
  }
  $hash->{READINGS}{state}{TIME} = TimeNow();
  $hash->{READINGS}{isRunning}{TIME} = TimeNow();
  
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "WOL_GetUpdate", $hash, 0);
}

sub wake
{
  my ($hash, $logLevel) = @_;
  my $mac = $hash->{MAC};
  
  Log $logLevel, "trying to wake $mac";

  my $response = `/usr/bin/ether-wake $mac`;
  Log $logLevel, "trying etherwake with response: $response";
  
  wol_by_udp($mac);
  Log $logLevel, "trying direct socket via UDP";
}

# method to wake via lan, taken from Net::Wake package
sub wol_by_udp {
  my ($mac_addr, $host, $port) = @_;

  # use the discard service if $port not passed in
  if (! defined $host) { $host = '255.255.255.255' }
  if (! defined $port || $port !~ /^\d+$/ ) { $port = 9 }

  my $sock = new IO::Socket::INET(Proto=>'udp') or die "socket : $!";
  die "Can't create WOL socket" if(!$sock);
  
  my $ip_addr = inet_aton($host);
  my $sock_addr = sockaddr_in($port, $ip_addr);
  $mac_addr =~ s/://g;
  my $packet = pack('C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16);

  setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1) or die "setsockopt : $!";
  
  send($sock, $packet, 0, $sock_addr) or die "send : $!";
  close ($sock);

  return 1;
}

1;

=pod
=begin html

<a name="WOL"></a>
<h3>WOL</h3>
<ul>
  <a name="WOLdefine"></a>
  <h4>Define</h4>
  <ul>
    <code>define &lt;name&gt; WOL &lt;MAC&gt; &lt;IP&gt;
          &lt;unitcode&gt;</code>
    <br><br>

    Defines a WOL device via its MAC and IP address.<br><br>

    Example:
    <ul>
      <code>define computer1 WOL 72:11:AC:4D:37:13 192.168.0.24</code><br>
    </ul>
    Notes:
    <ul>
      <li>Module uses <code>ether-wake</code> on FritzBoxes.</li>
      <li>For other computers the WOL implementation of <a href="http://search.cpan.org/~clintdw/Net-Wake-0.02/lib/Net/Wake.pm">Net::Wake</a> is used</li>
    </ul>
  </ul>

  <a name="WOLset"></a>
  <h4>Set </h4>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    refresh           # checks whether the computer is currently running
    on                # sends a magic packet to the defined MAC address
    </pre>

    Examples:
    <ul>
      <code>set computer1 on</code><br>
      <code>set computer1 refresh</code><br>
    </ul>
  </ul>

  <a name="WOLattr"></a>
  <h4>Attributes</h4> 
  <ul>
    <li><a name="owtherm_stateAL"><code>attr &lt;name&gt; shutdownCmd &lt;string&gt;</code></a>
                <br />Custom command executed to shutdown a remote machine, i.e. <code>sh /path/to/some/shell/script.sh</code></li>
  </ul>
</ul>

=end html
=cut
