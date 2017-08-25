#######################################################################################################
# $Id:  $
#######################################################################################################
#       93_Log2Syslog.pm
#
#       (c) 2017 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#       The module based on idea and input from betateilchen 92_rsyslog.pm
#
#       Implements the Syslog Protocol of RFC 5424  https://tools.ietf.org/html/rfc5424
#       and RFC 3164 https://tools.ietf.org/html/rfc3164 and
#       TLS Transport according to RFC5425 https://tools.ietf.org/pdf/rfc5425.pdf as well
#
#######################################################################################################
#  Versions History:
#
# 2.5.1      24.08.2017       some fixes
# 2.5.0      23.08.2017       TLS encryption available, new readings, $readingFnAttributes
# 2.4.1      21.08.2017       changes in sub charfilter, change PROCID to $hash->{SEQNO}
#                             switch to non-blocking in subs event/fhem_log
# 2.4.0      20.08.2017       new sub Log3Syslog for entries in local fhemlog only -> verbose support
# 2.3.1      19.08.2017       commandref revised
# 2.3.0      18.08.2017       new parameter "ident" in DEF, sub setidex, charfilter
# 2.2.0      17.08.2017       set BSD data length, set only acceptable characters (USASCII) in payload
#                             commandref revised
# 2.1.0      17.08.2017       sub setsock created
# 2.0.0      16.08.2017       create syslog without SYS::SYSLOG
# 1.1.1      13.08.2017       registrate fhem_log to %loginform in case of sending fhem-log
#                             attribute timeout, commandref revised
# 1.1.0      26.07.2017       add regex search to sub fhem_log
# 1.0.0      25.07.2017       initial version

package main;

use strict;
use warnings;
eval "use IO::Socket::INET;1" or my $MissModulSocket = "IO::Socket::INET";
eval "use Net::Domain qw(hostfqdn);1"  or my $MissModulNDom = "Net::Domain";

##################################################
# Forward declarations
#
sub Log3Syslog($$$);

my $Log2SyslogVn = "2.5.1";

# Mappinghash BSD-Formatierung Monat
my %Log2Syslog_BSDMonth = (
  "01" => "Jan",
  "02" => "Feb",
  "03" => "Mar",
  "04" => "Apr",
  "05" => "May",
  "06" => "Jun",
  "07" => "Jul",
  "08" => "Aug",
  "09" => "Sep",
  "10" => "Oct",
  "11" => "Nov",
  "12" => "Dec"
);

# Längenvorgaben nach RFC3164
my %RFC3164len = ("TAG"  => 32,           # max. Länge TAG-Feld
                  "DL"   => 1024          # max. Lange Message insgesamt
   			     );
				 
# Längenvorgaben nach RFC5425
my %RFC5425len = ("DL" => 8192           # max. Lange Message insgesamt mit TLS
                  );

#####################################
sub Log2Syslog_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}    = "Log2Syslog_Define";
  $hash->{UndefFn}  = "Log2Syslog_Undef";
  $hash->{DeleteFn} = "Log2Syslog_Delete";
  $hash->{AttrFn}   = "Log2Syslog_Attr";
  $hash->{NotifyFn} = "event_log";

  $hash->{AttrList} = "addStateEvent:1,0 ".
                      "disable:1,0 ".
                      "addTimestamp:0,1 ".
					  "logFormat:BSD,IETF ".
					  "TLS:1,0 ".
					  "timeout ".
	                  "type:UDP,TCP ".
	                  "port ".
					  $readingFnAttributes
                      ;
return undef;   
}

##############################################################
sub Log2Syslog_Define($@) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  
  return "Error: Perl module ".$MissModulSocket." is missing. Install it on Debian with: sudo apt-get install libio-socket-multicast-perl" if($MissModulSocket);
  return "Error: Perl module ".$MissModulNDom." is missing." if($MissModulNDom);
		
  if (int(devspec2array('TYPE=Log2Syslog')) > 1) {
      my @ldvs = devspec2array('TYPE=Log2Syslog');
	  my $ldvs = shift(@ldvs);
      return "Log2Syslog device '$ldvs' is already defined. Only one device can be defined ! ";
  }
  
  # Example:        define  splunklog Log2Syslog  splunk.myds.me    ident        event:.*        fhem:.*
  return "wrong syntax, use: define <name> Log2Syslog <host> [ident:<ident>] [event:<regexp>] [fhem:<regexp>] "
        if(int(@a)-3 < 0);
		
  delete($hash->{HELPER}{EVNTLOG});
  delete($hash->{HELPER}{FHEMLOG});
  delete($hash->{HELPER}{IDENT});
  
  setidrex($hash,$a[3]) if($a[3]);
  setidrex($hash,$a[4]) if($a[4]);
  setidrex($hash,$a[5]) if($a[5]);
  
  return "Bad regexp: starting with *" 
     if((defined($hash->{HELPER}{EVNTLOG}) && $hash->{HELPER}{EVNTLOG} =~ m/^\*/) || (defined($hash->{HELPER}{FHEMLOG}) && $hash->{HELPER}{FHEMLOG} =~ m/^\*/));
  eval { "Hallo" =~ m/^$hash->{HELPER}{EVNTLOG}$/ } if($hash->{HELPER}{EVNTLOG});
  return "Bad regexp: $@" if($@);
  eval { "Hallo" =~ m/^$hash->{HELPER}{FHEMLOG}$/ } if($hash->{HELPER}{FHEMLOG});
  return "Bad regexp: $@" if($@);
		
  $hash->{PEERHOST}         = $a[2];                        # Destination Host (Syslog Server)
  $hash->{MYHOST}           = hostfqdn ();                  # FQDN eigener Host
  $hash->{SEQNO}            = 1;                            # PROCID in IETF, wird kontinuierlich hochgezählt
  $hash->{VERSION}          = $Log2SyslogVn;
  $logInform{$hash->{NAME}} = "fhem_log";                   # Funktion die in hash %loginform für $name eingetragen wird
  $hash->{HELPER}{SSLVER}   = "n.a.";                       # Initialisierung
  $hash->{HELPER}{SSLALGO}  = "n.a.";                       # Initialisierung
  $hash->{HELPER}{LTIME}    = time();                       # Init Timestmp f. Ratenbestimmung
  $hash->{HELPER}{OLDSEQNO} = $hash->{SEQNO};               # Init Sequenznummer f. Ratenbestimmung
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "SSL_Version", "n.a.");
  readingsBulkUpdate($hash, "SSL_Algorithm", "n.a.");
  readingsBulkUpdate($hash, "Transfered_logs_per_minute", 0);
  readingsBulkUpdate($hash, "state", "initialized");
  readingsEndUpdate($hash,1);
  
return undef;
}

sub Log2Syslog_Undef($$) {
  my ($hash, $name) = @_;
return undef;
}

sub Log2Syslog_Delete($$) {
  my ($hash, $arg) = @_;
  delete $logInform{$hash->{NAME}};
return undef;
}

################################################################
sub Log2Syslog_Attr {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my $do;
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        my $val = ($do == 1 ?  "disabled" : "active");
		
        readingsSingleUpdate($hash, "state", $val, 1);
    }
	
    if ($aName eq "TLS") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        if ($do == 0) {		
            $hash->{HELPER}{SSLVER}  = "n.a.";
            $hash->{HELPER}{SSLALGO} = "n.a.";
			readingsSingleUpdate($hash, "SSL_Version", "n.a.", 1);
            readingsSingleUpdate($hash, "SSL_Algorithm", "n.a.", 1);
		}
    }
	
	if ($cmd eq "set" && $aName =~ /port|timeout/) {
        if($aVal !~ m/^\d+$/) { return " The Value of \"$aName\" is not valid. Use only figures !";}
	}
    
return undef;
}

#################################################################################
#                               Eventlogging
#################################################################################
sub event_log($$) {
  # $hash is my entry, $dev is the entry of the changed device
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};
  my $rex  = $hash->{HELPER}{EVNTLOG};
  my ($prival,$sock,$data,$pid);
  
  return if(IsDisabled($name) || !$rex);
  my $events = deviceEvents($dev, AttrVal($name, "addStateEvent", 0));
  return if(!$events);

  my $n   = $dev->{NAME};
  my $max = int(@{$events});
  my $tn  = $dev->{NTFY_TRIGGERTIME};
  my $ct  = $dev->{CHANGETIME};
  
  $sock = setsock($hash);
  
  if(defined($sock)) { 
      for (my $i = 0; $i < $max; $i++) {
          my $txt = $events->[$i];
          $txt = "" if(!defined($txt));
          $txt = charfilter($hash,$txt);
	  
	      my $tim          = (($ct && $ct->[$i]) ? $ct->[$i] : $tn);
          my ($date,$time) = split(" ",$tim);
	  
	      if($n =~ m/^$rex$/ || "$n:$txt" =~ m/^$rex$/ || "$tim:$n:$txt" =~ m/^$rex$/) {				  
              my $otp  = "$n $txt";
              $otp     = "$tim $otp" if AttrVal($name,'addTimestamp',0);
	          $prival  = setprival($txt);

	          ($data,$pid) = setpayload($hash,$prival,$date,$time,$otp,"event");	
              next if(!$data);			  
          
			  my $ret = syswrite $sock, $data."\n";
			  if($ret && $ret > 0) {
			      trate($hash);      
				  Log3Syslog($name, 4, "$name - Payload sequence $pid sent\n");	
              } else {
                  my $err = $!;
				  Log3Syslog($name, 4, "$name - Warning - Payload sequence $pid NOT sent: $err\n");	
		          readingsSingleUpdate($hash, "state", "write error: $err", 1) if($err ne OldValue($name));			      		  
			  }
          }
      }
      
      if(AttrVal($name, "TLS", 0)) {
	      shutdown($sock, 1);
		  $sock->close(SSL_no_shutdown => 1);
	  } else {
	      $sock->close();
	  }
   }
  
return "";
}

#################################################################################
#                               FHEM system logging
#################################################################################
sub fhem_log($$) {
  my ($name,$raw) = @_;                              
  my $hash = $defs{$name};
  my $rex  = $hash->{HELPER}{FHEMLOG};
  my ($prival,$sock,$err,$ret,$data,$pid);
  
  return if(IsDisabled($name) || !$rex);
	
  my ($date,$time,$vbose,undef,$txt) = split(" ",$raw,5);
  $txt = charfilter($hash,$txt);
  $date =~ s/\./-/g;
  my $tim = $date." ".$time;
  
  if($txt =~ m/^$rex$/ || "$vbose: $txt" =~ m/^$rex$/) {  	
      my $otp  = "$vbose: $txt";
      $otp     = "$tim $otp" if AttrVal($name,'addTimestamp',0);
	  $prival  = setprival($txt,$vbose);
	  
      ($data,$pid) = setpayload($hash,$prival,$date,$time,$otp,"fhem");	
	  return if(!$data);
	  
      $sock = setsock($hash);
	  
      if (defined($sock)) {
	      $ret = syswrite $sock, $data."\n" if($data);
		  if($ret && $ret > 0) {
		      trate($hash);  
		      Log3Syslog($name, 4, "$name - Payload sequence $pid sent\n");	
          } else {
              my $err = $!;
			  Log3Syslog($name, 4, "$name - Warning - Payload sequence $pid NOT sent: $err\n");	
		      readingsSingleUpdate($hash, "state", "write error: $err", 1) if($err ne OldValue($name));			      		  
	      }
		  
		  if(AttrVal($name, "TLS", 0)) {
              shutdown($sock, 1);
		      $sock->close(SSL_no_shutdown => 1);
		  } else {
              shutdown($sock, 1);
		      $sock->close();
		  }
	  }
  }

return;
}

###############################################################################
#              Helper für ident & Regex setzen 
###############################################################################
sub setidrex ($$) { 
  my ($hash,$a) = @_;
     
  $hash->{HELPER}{EVNTLOG} = (split("event:",$a))[1] if(lc($a) =~ m/^event:.*/);
  $hash->{HELPER}{FHEMLOG} = (split("fhem:",$a))[1] if(lc($a) =~ m/^fhem:.*/);
  $hash->{HELPER}{IDENT}   = (split("ident:",$a))[1] if(lc($a) =~ m/^ident:.*/);
  
return;
}

###############################################################################
#              Zeichencodierung für Payload filtern 
###############################################################################
sub charfilter ($$) { 
  my ($hash,$txt) = @_;
  my $name   = $hash->{NAME};

  # nur erwünschte Zeichen in payload, ASCII %d32-126
  $txt =~ s/ß/ss/g;
  $txt =~ s/ä/ae/g;
  $txt =~ s/ö/oe/g;
  $txt =~ s/ü/ue/g;
  $txt =~ s/Ä/Ae/g;
  $txt =~ s/Ö/Oe/g;
  $txt =~ s/Ü/Ue/g;
  $txt =~ s/€/EUR/g;
  $txt =~ tr/ A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\]^_`{|}~//cd;      
  
return($txt);
}

###############################################################################
#                        erstelle Socket 
###############################################################################
sub setsock ($) { 
  my ($hash)  = @_;
  my $name    = $hash->{NAME};
  my $host    = $hash->{PEERHOST};
  my $port    = AttrVal($name, "TLS", 0)?AttrVal($name, "port", 6514):AttrVal($name, "port", 514);
  my $type    = lc(AttrVal($name, "type", "udp"));
  my $st      = "active";
  my $timeout = AttrVal($name, "timeout", 0.5);
  my ($sock,$lo,$sslver,$sslalgo);
 
  if(AttrVal($name, "TLS", 0)) {
      # TLS gesicherte Verbindung
      # TLS Transport nach RFC5425 https://tools.ietf.org/pdf/rfc5425.pdf
	  $attr{$name}{type} = "TCP" if(AttrVal($name, "type", "UDP") ne "TCP");
	  $sslver  = "n.a.";
      $sslalgo = "n.a.";
	  eval "use IO::Socket::SSL";
	  if($@) {
          $st = "$@";
      } else {
	      $sock = IO::Socket::INET->new(PeerHost => $host, PeerPort => $port, Proto => 'tcp', Blocking => 0);
	      if (!$sock) {
		      $st = "unable open socket for $host, $type, $port";
		  } else {
		      $sock->blocking(1);
		      eval { IO::Socket::SSL->start_SSL($sock, 
						    			        SSL_verify_mode => "SSL_VERIFY_PEER",
		                                        SSL_version => "TLSv12",
								    	        SSL_hostname => $host,
									            SSL_veriycn_scheme => "rfc5425",
									            SSL_veriycn_publicsuffix => '',
												Timeout => $timeout
									            ) || undef $sock; };
		      if (!$sock) {
			      undef $sock;
		          $st = "SSL error: ".IO::Socket::SSL::errstr();
		      } else  {
			      $sslver  = $sock->get_sslversion();
			      $sslalgo = $sock->get_fingerprint();
			      $sslalgo = (split("\\\$",$sslalgo))[0];
			      $lo = "Socket opened for Host: $host, Protocol: $type, Port: $port, TLS: 0";
		      }
		  }
	  }     
  } else {
      # erstellt ungesicherte Socket Verbindung
	  $sslver  = "n.a.";
      $sslalgo = "n.a.";
      $sock = new IO::Socket::INET (PeerHost => $host, PeerPort => $port, Proto => $type, Timeout => $timeout ); 

      if (!$sock) {
	      undef $sock;
          $st = "unable open socket for $host, $type, $port";
      } else {
          $sock->blocking(0);
          # Logausgabe (nur in das fhem Logfile !)
          $lo = "Socket opened for Host: $host, Protocol: $type, Port: $port, TLS: 0";
      }
  }

  readingsSingleUpdate($hash, "state", $st, 1) if($st ne OldValue($name));
  
  if($sslver ne $hash->{HELPER}{SSLVER}) {
      readingsSingleUpdate($hash, "SSL_Version", $sslver, 1);
	  $hash->{HELPER}{SSLVER} = $sslver;
  }
  if($sslalgo ne $hash->{HELPER}{SSLALGO}) {
      readingsSingleUpdate($hash, "SSL_Algorithm", $sslalgo, 1);
	  $hash->{HELPER}{SSLALGO} = $sslalgo;
  }
  
  Log3Syslog($name, 5, "$name - $lo") if($lo);
  
return($sock);
}

###############################################################################
#               set PRIVAL (severity & facility)
###############################################################################
sub setprival ($;$$) { 
  my ($txt,$vbose) = @_;
  my $prival;
  
  # Priority = (facility * 8) + severity 
  # https://tools.ietf.org/pdf/rfc5424.pdf
  
  # determine facility
  my $fac = 5;                                    # facility by syslogd
  
  # calculate severity
  # mapping verbose level to severity
  # 0: Critical        -> 2
  # 1: Error           -> 3
  # 2: Warning         -> 4
  # 3: Notice          -> 5
  # 4: Informational   -> 6
  # 5: Debug           -> 7
  
  my $sv = 5;                                      # notice (default)
  
  if ($vbose) {
      # map verbose to severity 
	  $sv = 2 if ($vbose == 0);
	  $sv = 3 if ($vbose == 1);
	  $sv = 4 if ($vbose == 2);
	  $sv = 5 if ($vbose == 3);
	  $sv = 6 if ($vbose == 4);
      $sv = 7 if ($vbose == 5);
  }
                                         
  $sv = 3 if (lc($txt) =~ m/error/);              # error condition
  $sv = 4 if (lc($txt) =~ m/warning/);            # warning conditions
  
  $prival = ($fac*8)+$sv;
   
return($prival);
}

###############################################################################
#               erstellen Payload für Syslog
###############################################################################
sub setpayload ($$$$$$) { 
  my ($hash,$prival,$date,$time,$otp,$lt) = @_;
  my $name   = $hash->{NAME};
  my $ident  = ($hash->{HELPER}{IDENT}?$hash->{HELPER}{IDENT}:$name)."_".$lt;
  my $myhost = $hash->{MYHOST}?$hash->{MYHOST}:"0.0.0.0";
  my $lf     = AttrVal($name, "logFormat", "IETF");
  my $data;
  
  return undef,undef if(!$otp);
  my $pid = $hash->{SEQNO};                     # PayloadID zur Nachverfolgung der Eventabfolge 
  $hash->{SEQNO}++;

  my ($year,$month,$day) = split("-",$date);
  
  if ($lf eq "BSD") {
      # BSD Protokollformat https://tools.ietf.org/html/rfc3164
      $time  = (split(".",$time))[0] if($time =~ m/\./);   # msec ist nicht erlaubt
	  $month = $Log2Syslog_BSDMonth{$month};               # Monatsmapping, z.B. 01 -> Jan
	  $day   =~ s/0/ / if($day =~ m/^0.*$/);               # in Tagen < 10 muss 0 durch Space ersetzt werden
	  $ident = substr($ident,0, $RFC3164len{TAG});         # Länge TAG Feld begrenzen
	  no warnings 'uninitialized'; 
      $data  = "<$prival>$month $day $time $myhost $ident: : $otp";
	  use warnings;
	  $data = substr($data,0, $RFC3164len{DL});     # Länge Total begrenzen
  }
  
  if ($lf eq "IETF") {
      # IETF Protokollformat https://tools.ietf.org/html/rfc5424 
	  my $mid = "FHEM";                             # message ID, identify type of message, e.g. for firewall filter
	  my $tim = $date."T".$time;
	  no warnings 'uninitialized'; 
      $data   = "<$prival>1 $tim $myhost $ident $pid $mid - : $otp";
	  use warnings;
  }
  
  if($data=~/\s$/){$data=~s/\s$//;}
  my $dl = length($data)+1;                         # Länge muss ! für TLS stimmen, sonst keine Ausgabe !
  
  # wenn Transport Layer Security (TLS) -> Transport Mapping for Syslog https://tools.ietf.org/pdf/rfc5425.pdf
  if(AttrVal($name, "TLS", 0)) {
	  $data = "$dl $data";
	  $data = substr($data,0, $RFC5425len{DL});     # Länge Total begrenzen 
	  Log3Syslog($name, 4, "$name - SSL-Payload created with length: ".(($dl>$RFC5425len{DL})?$RFC5425len{DL}:$dl) ); 
  } 
  
  my $ldat = ($dl>130)?(substr($data,0, 130)." ..."):$data;
  Log3Syslog($name, 4, "$name - Payload sequence $pid created:\n$ldat");		
  
return($data,$pid);
}

###############################################################################
#               eigene Log3-Ableitung - Schleife vermeiden
###############################################################################
sub Log3Syslog($$$) {
  my ($dev, $loglevel, $text) = @_;
  our ($logopened,$currlogfile);
  
  $dev = $dev->{NAME} if(defined($dev) && ref($dev) eq "HASH");
     
  if(defined($dev) &&
     defined($attr{$dev}) &&
     defined (my $devlevel = $attr{$dev}{verbose})) {
    return if($loglevel > $devlevel);

  } else {
    return if($loglevel > $attr{global}{verbose});

  }

  my ($seconds, $microseconds) = gettimeofday();
  my @t = localtime($seconds);
  my $nfile = ResolveDateWildcards($attr{global}{logfile}, @t);
  OpenLogfile($nfile) if(!$currlogfile || $currlogfile ne $nfile);

  my $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d",
          $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0]);
  if($attr{global}{mseclog}) {
    $tim .= sprintf(".%03d", $microseconds/1000);
  }

  if($logopened) {
    print LOG "$tim $loglevel: $text\n";
  } else {
    print "$tim $loglevel: $text\n";
  }

return undef;
}

###############################################################################
#                          Bestimmung Übertragungsrate
###############################################################################
sub trate($) {
  my ($hash) = @_;
  
  if ($hash->{HELPER}{LTIME}+60 <= time()) {
      my $div = (time()-$hash->{HELPER}{LTIME})/60;
      my $spm = sprintf "%.0f", ($hash->{SEQNO} - $hash->{HELPER}{OLDSEQNO})/$div;
      $hash->{HELPER}{OLDSEQNO} = $hash->{SEQNO};
      $hash->{HELPER}{LTIME}    = time();
	  
	  my $ospm = ReadingsVal($hash->{NAME}, "Transfered_logs_per_minute", 0);
	  if($spm != $ospm) {
          readingsSingleUpdate($hash, "Transfered_logs_per_minute", $spm, 1);
      }
  }
  
return; 
}

1;

=pod
=item helper
=item summary    forwards FHEM system logs and/or events to a syslog server
=item summary_DE leitet FHEM Systemlogs und/oder Events an einen Syslog-Server weiter

=begin html

<a name="Log2Syslog"></a>
<h3>Log2Syslog</h3>
<ul>
  Send FHEM system log entries and/or FHEM events to an external syslog server. <br>
  The syslog protocol has been implemented according the specifications of <a href="https://tools.ietf.org/html/rfc5424"> RFC5424 (IETF)</a>,
  <a href="https://tools.ietf.org/html/rfc3164"> RFC3164 (BSD)</a> and the TLS transport protocol according the 
  <a href="https://tools.ietf.org/pdf/rfc5425.pdf"> RFC5425</a>. <br>	
  <br>
  
  <b>Prerequisits</b>
  <ul>
    <br/>
    The additional perl module "IO::Socket::INET" must be installed on your system. <br>
	Install this package from cpan or by <br><br>
    
	<code>apt-get install libio-socket-multicast-perl (only on Debian based installations) </code><br>
  </ul>
  <br>
  
  <a name="Log2Syslogdefine"></a>
  <b>Define</b>
  <ul>
    <br>
    <code>define &lt;name&gt; Log2Syslog &lt;destination host&gt; [ident:&lt;ident&gt;] [event:&lt;regexp&gt;] [fhem:&lt;regexp&gt;]</code><br>
    <br>
	
	&lt;destination host&gt; = host where the syslog server is running <br>
	[ident:&lt;ident&gt;] = optional program identifier. If not set the device name will be used as default <br>
	[event:&lt;regexp&gt;] = optional regex to filter events for logging  <br>
	[fhem:&lt;regexp&gt;] = optional regex to filter fhem system log for logging <br><br>
	
	After definition the new device sends all new appearing fhem systemlog entries and events to the destination host, 
	port=514/UDP format:IETF, immediately without further settings if the regex for fhem or event were set. <br>
	Without setting regex no fhem system log or event log will be forwarded. <br><br>
	
	The verbose level of FHEM system logs will convert into equivalent syslog severity level. <br>
	Thurthermore the message text will be scanned for signal terms "warning" and "error" (with case insensitivity). 
	Dependent off the severity will be set equivalent as well. If a severity is already set by verbose level, it wil be overwritten
    by the level according to the signal term found in the message text. <br><br>
	
	<b>Lookup table Verbose-Level to Syslog severity level: </b><br><br>
    <ul>  
    <table>  
    <colgroup> <col width=40%> <col width=60%> </colgroup>
	  <tr><td> <b>verbose-Level</b> </td><td> <b>Schweregrad in Syslog</b> </td></tr>
      <tr><td> 0    </td><td> Critical </td></tr>
      <tr><td> 1    </td><td> Error </td></tr>
      <tr><td> 2    </td><td> Warning </td></tr>
      <tr><td> 3    </td><td> Notice </td></tr>
      <tr><td> 4    </td><td> Informational </td></tr>
      <tr><td> 5    </td><td> Debug </td></tr>
    </table>
    </ul>     
    <br>
    
	<br>
    Example to log anything: <br>
    <br/>
    <code>define splunklog Log2Syslog fhemtest 192.168.2.49 ident:Test event:.* fhem:.* </code><br>
    <br/>
    will produce output like this raw example of a splunk syslog server:<br/>
    <pre>Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM - : LogDB sql_processing_time: 0.2306
Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM - : LogDB background_processing_time: 0.2397
Aug 18 21:06:45 fhemtest.myds.me 1 2017-08-18T21:06:45 fhemtest.myds.me Test_event 13339 FHEM - : LogDB CacheUsage: 21
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.760 fhemtest.myds.me Test_fhem 13339 FHEM - : 4: CamTER - Informations of camera Terrasse retrieved
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.095 fhemtest.myds.me Test_fhem 13339 FHEM - : 4: CamTER - CAMID already set - ignore get camid
    </pre>
		
  </ul>
  <br>

  
  <a name="Log2Syslogattr"></a>
  <b>Attributes</b>
  <ul>
    <br/>
    <a name="addTimestamp"></a>
    <li><code>addTimestamp [0|1]</code><br>
        <br/>
        If set to 1, fhem timestamps will be logged too.<br/>
        Default behavior is to not log these timestamps, because syslog uses own timestamps.<br/>
        Maybe useful if mseclog is activated in fhem.<br/>
        <br/>
        Example output (raw) of a Splunk syslog server: <br>
        <pre>Aug 18 21:26:55 fhemtest.myds.me 1 2017-08-18T21:26:55 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:55 USV state: OL
Aug 18 21:26:54 fhemtest.myds.me 1 2017-08-18T21:26:54 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:54 Bezug state: done
Aug 18 21:26:54 fhemtest.myds.me 1 2017-08-18T21:26:54 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:54 recalc_Bezug state: Next: 21:31:59
        </pre>
    </li><br>

    <li><code>addStateEvent [0|1]</code><br>
        <br>
        If set to 1, events will be completed with "state" if a state-event appears.<br/>
		Default behavior is without getting "state".
    </li><br>
	
    <li><code>disable [0|1]</code><br>
        <br>
        disables the device.
    </li><br>
	
    <li><code>logFormat [BSD|IETF]</code><br>
        <br>
        Set the syslog protocol format. <br>
		Default value is "IETF" if not specified. 
		</li><br>
	
    <li><code>type [TCP|UDP]</code><br>
        <br>
        Sets the socket type which should be used. You can choose UDP or TCP. <br>
		Default value is "UDP" if not specified.
    </li><br>
	
    <li><code>port</code><br>
        <br>
        The port of the syslog server is listening. Default port is 514 if not specified.
    </li><br>
	
    <li><code>timeout</code><br>
        <br>
        Timeout for connection to the syslog server (TCP).
    </li><br>
	
    <li><code>verbose</code><br>
        <br>
        To avoid loops, the output of verbose level of the Log2Syslog-Devices will only be reported into the local FHEM Logfile and
		no forwarded.
    </li><br>
	
	</ul>
    <br/>
  
</ul>

=end html
=begin html_DE

<a name="Log2Syslog"></a>
<h3>Log2Syslog</h3>
<ul>
  Sendet FHEM Systemlog Einträge und/oder Events an einen externen Syslog-Server weiter. <br>
  Die Implementierung des Syslog-Protokolls erfolgte entsprechend den Vorgaben von <a href="https://tools.ietf.org/html/rfc5424"> RFC5424 (IETF)</a>,
  <a href="https://tools.ietf.org/html/rfc3164"> RFC3164 (BSD)</a> sowie dem TLS Transport Protokoll nach 
  <a href="https://tools.ietf.org/pdf/rfc5425.pdf"> RFC5425</a>. <br>	
  <br>
  
  <b>Voraussetzungen</b>
  <ul>
    <br/>
    Es wird das Perl Modul "IO::Socket::INET" benötigt und muss installiert sein. <br>
    Das Modul kann über CPAN oder mit <br><br>
	
    <code>apt-get install libio-socket-multicast-perl (auf Debian Linux Systemen) </code><br><br>
	
	installiert werden.
  </ul>
  <br/>
  
  <a name="Log2Syslogdefine"></a>
  <b>Definition</b>
  <ul>
    <br>
    <code>define &lt;name&gt; Log2Syslog &lt;Zielhost&gt; [ident:&lt;ident&gt;] [event:&lt;regexp&gt;] [fhem:&lt;regexp&gt;] </code><br>
    <br>

	&lt;Zielhost&gt; = Host (Name oder IP-Adresse) auf dem der Syslog-Server läuft <br>
	[ident:&lt;ident&gt;] = optionaler Programm Identifier. Wenn nicht gesetzt wird per default der Devicename benutzt. <br>
	[event:&lt;regexp&gt;] = optionaler regulärer Ausdruck zur Filterung von Events zur Weiterleitung <br>
	[fhem:&lt;regexp&gt;] = optionaler regulärer Ausdruck zur Filterung von FHEM Logs zur Weiterleitung <br><br>
	
	Direkt nach der Definition sendet das neue Device alle neu auftretenden FHEM Systemlog Einträge und Events ohne weitere 
	Einstellungen an den Zielhost, Port=514/UDP Format=IETF, wenn reguläre Ausdrücke für Events/FHEM angegeben wurden. <br>
	Wurde kein Regex gesetzt, erfolgt keine Weiterleitung von Events oder FHEM Systemlogs. <br><br>
	
	Die Verbose-Level der FHEM Systemlogs werden in entsprechende Schweregrade der Syslog-Messages umgewandelt. <br>
	Weiterhin wird der Meldungstext der FHEM Systemlogs und Events nach den Signalwörtern "warning" und "error" durchsucht 
	(Groß- /Kleinschreibung wird nicht beachtet). Davon abhängig wird der Schweregrad ebenfalls äquivalent gesetzt und überschreibt 
    einen eventuell bereits durch Verbose-Level gesetzten Schweregrad.	<br><br>
	
	<b>Umsetzungstabelle Verbose-Level in Syslog-Schweregrad Stufe: </b><br><br>
    <ul>  
    <table>  
    <colgroup> <col width=40%> <col width=60%> </colgroup>
	  <tr><td> <b>Verbose-Level</b> </td><td> <b>Schweregrad in Syslog</b> </td></tr>
      <tr><td> 0    </td><td> Critical </td></tr>
      <tr><td> 1    </td><td> Error </td></tr>
      <tr><td> 2    </td><td> Warning </td></tr>
      <tr><td> 3    </td><td> Notice </td></tr>
      <tr><td> 4    </td><td> Informational </td></tr>
      <tr><td> 5    </td><td> Debug </td></tr>
    </table>
    </ul>     
    <br>	
    
	<br>
    Beispiel:<br/>
    <br/>
    <code>define splunklog Log2Syslog fhemtest 192.168.2.49 ident:Test event:.* fhem:.* </code><br/>
    <br/>
    Es werden alle Events weitergeleitet wie deses Beispiel der raw-Ausgabe eines Splunk Syslog Servers zeigt::<br/>
    <pre>Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM - : LogDB sql_processing_time: 0.2306
Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM - : LogDB background_processing_time: 0.2397
Aug 18 21:06:45 fhemtest.myds.me 1 2017-08-18T21:06:45 fhemtest.myds.me Test_event 13339 FHEM - : LogDB CacheUsage: 21
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.760 fhemtest.myds.me Test_fhem 13339 FHEM - : 4: CamTER - Informations of camera Terrasse retrieved
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.095 fhemtest.myds.me Test_fhem 13339 FHEM - : 4: CamTER - CAMID already set - ignore get camid
    </pre>

	Der Aufbau der Payload unterscheidet sich je nach verwendeten logFormat. <br><br>
	
	<b>logFormat IETF:</b> <br><br>
	"&lt;PRIVAL&gt;1 TIME MYHOST IDENT PID MID - : MESSAGE" <br><br>
		
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
	  <tr><td> PRIVAL   </td><td> Priority Wert (kodiert aus "facility" und "severity") </td></tr>
      <tr><td> TIME     </td><td> Timestamp nach RFC5424 </td></tr>
      <tr><td> MYHOST   </td><td> Internal MYHOST </td></tr>
      <tr><td> IDENT    </td><td> Ident-Tag aus DEF wenn angegeben, sonst der eigene Devicename. Die Angabe wird mit "_fhem" (FHEM-Log) bzw. "_event" (Event-Log) ergänzt. </td></tr>
      <tr><td> PID      </td><td> fortlaufende Payload-ID </td></tr>
      <tr><td> MID      </td><td> fester Wert "FHEM" </td></tr>
      <tr><td> MESSAGE  </td><td> der zu übertragende Datensatz </td></tr>
    </table>
    </ul>     
    <br>	
	
	<b>logFormat BSD:</b> <br><br>
	"&lt;PRIVAL&gt;MONAT TAG TIME MYHOST IDENT: : MESSAGE" <br><br>
		
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
	  <tr><td> PRIVAL   </td><td> Priority Wert (kodiert aus "facility" und "severity") </td></tr>
      <tr><td> MONAT    </td><td> Monatsangabe nach RFC3164 </td></tr>
	  <tr><td> TAG      </td><td> Tag des Monats nach RFC3164 </td></tr>
	  <tr><td> TIME     </td><td> Zeitangabe nach RFC3164 </td></tr>
      <tr><td> MYHOST   </td><td> Internal MYHOST </td></tr>
      <tr><td> IDENT    </td><td> Ident-Tag aus DEF wenn angegeben, sonst der eigene Devicename. Die Angabe wird mit "_fhem" (FHEM-Log) bzw. "_event" (Event-Log) ergänzt. </td></tr>
      <tr><td> MESSAGE  </td><td> der zu übertragende Datensatz </td></tr>
    </table>
    </ul>     
    <br>
  
  </ul>
  <br><br>
  
  
  <a name="Log2Syslogattr"></a>
  <b>Attribute</b>
  <ul>
    <br>
	
    <a name="addTimestamp"></a>
    <li><code>addTimestamp [0|1]</code><br>
        <br/>
        Wenn gesetzt, werden FHEM Timestamps im Datensatz mit übertragen.<br/>
        Per default werden die Timestamps nicht mit übertragen, da der Syslog-Server eigene Timestamps verwendet.<br/>
        Die Einstellung kann hilfeich sein wenn mseclog in FHEM aktiviert ist.<br/>
        <br/>
		
        Beispielausgabe (raw) eines Splunk Syslog Servers:<br/>
        <pre>Aug 18 21:26:55 fhemtest.myds.me 1 2017-08-18T21:26:55 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:55 USV state: OL
Aug 18 21:26:54 fhemtest.myds.me 1 2017-08-18T21:26:54 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:54 Bezug state: done
Aug 18 21:26:54 fhemtest.myds.me 1 2017-08-18T21:26:54 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:54 recalc_Bezug state: Next: 21:31:59
        </pre>
    </li><br>

    <li><code>addStateEvent [0|1]</code><br>
        <br>
        Wenn gesetzt, werden state-events mit dem Reading "state" ergänzt.<br/>
		Die Standardeinstellung ist ohne state-Ergänzung.
    </li><br>
	
    <li><code>disable [0|1]</code><br>
        <br>
        Das Device wird aktiviert | aktiviert.
    </li><br>
	
    <li><code>logFormat [BSD|IETF]</code><br>
        <br>
        Stellt das Protokollformat ein. <br>
		Der Standardwert ist "IETF". <br>
    </li><br>
	
    <li><code>type [TCP|UDP]</code><br>
        <br>
        Setzt den Protokolltyp der verwendet werden soll. Es kann UDP oder TCP gewählt werden. <br>
		Standard ist "UDP" wenn nichts spezifiziert ist.
    </li><br>
	
    <li><code>port</code><br>
        <br>
        Der verwendete Port des Syslog-Servers. Default Port ist 514 wenn nicht gesetzt.
    </li><br>
	
    <li><code>timeout</code><br>
        <br>
        Timeout für die Verbindung zum Syslog-Server (TCP).
    </li><br>
	
    <li><code>verbose</code><br>
        <br>
        Die Ausgaben der Verbose-Level von Log2Syslog-Devices werden ausschließlich im lokalen FHEM Logfile ausgegeben und
		nicht weitergeleitet um Schleifen zu vermeiden.
    </li><br>
	
	</ul>
    <br/>
  
</ul>
=end html_DE
=cut
