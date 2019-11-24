########################################################################################################################
# $Id: $
#########################################################################################################################
#       50_SSChatBot.pm
#
#       (c) 2019 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This Module can be used to operate as Bot for Synology Chat.
#       It's based on and uses Synology Chat Web Hook.
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
#########################################################################################################################
# 
# Definition: define <name> SSChatBot <ServerAddr> [ServerPort] [Protocol]
# 
# Example of defining a Bot: define SynChatBot SSChatBot 192.168.2.20 [5000] [HTTP(S)]
#

package main;

use strict;                           
use warnings;
eval "use JSON;1;" or my $SSChatBotMM = "JSON";                   # Debian: apt-get install libjson-perl
use Data::Dumper;                                                 # Perl Core module
use MIME::Base64;
use Time::HiRes;
use HttpUtils;                                                    
use Encode;
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;
                                                    
# no if $] >= 5.017011, warnings => 'experimental';

# Versions History intern
our %SSChatBot_vNotesIntern = (
  "1.0.0"  => "20.11.2019  initial "
);

# Versions History extern
our %SSChatBot_vNotesExtern = (
  "1.0.0"  => "12.12.2015 initial "
);

my %SSChatBot_errlist = (
  100 => "Unknown error",
  102 => "API does not exist- may be the Chat server package is stopped",
  120 => "payload has wrong format",
  404 => "bot is not legal",
  407 => "record is not valid",
);

# Standardvariablen und Forward-Deklaration                                          
use vars qw(%SSChatBot_vHintsExt_en);
use vars qw(%SSChatBot_vHintsExt_de);

################################################################
sub SSChatBot_Initialize($) {
 my ($hash) = @_;
 $hash->{DefFn}             = "SSChatBot_Define";
 $hash->{UndefFn}           = "SSChatBot_Undef";
 $hash->{DeleteFn}          = "SSChatBot_Delete"; 
 $hash->{SetFn}             = "SSChatBot_Set";
 $hash->{GetFn}             = "SSChatBot_Get";
 $hash->{AttrFn}            = "SSChatBot_Attr";
 $hash->{DelayedShutdownFn} = "SSChatBot_DelayedShutdown";
 $hash->{FW_deviceOverview} = 1;
 
 $hash->{AttrList} = "disable:1,0 ".
                     "recepUser:--wait#for#userlist-- ".
                     "showTokenInLog:1,0 ".
                     "httptimeout ".
                     $readingFnAttributes;   
         
 eval { FHEM::Meta::InitMod( __FILE__, $hash ) };           # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return;   
}

################################################################
# define SynChatBot SSChatBot 192.168.2.10 [5000] [HTTP(S)] 
#         ($hash)     [1]         [2]        [3]      [4]  
#
################################################################
sub SSChatBot_Define($@) {
  my ($hash, $def) = @_;
  my $name         = $hash->{NAME};
  
 return "Error: Perl module ".$SSChatBotMM." is missing. Install it on Debian with: sudo apt-get install libjson-perl" if($SSChatBotMM);
  
  my @a = split("[ \t][ \t]*", $def);
  
  if(int(@a) < 2) {
      return "You need to specify more parameters.\n". "Format: define <name> SSChatBot <ServerAddress> [Port] [HTTP(S)]";
  }
        
  my $serveraddr = $a[2];
  my $serverport = $a[3] ? $a[3] : 5000;
  my $proto      = $a[4] ? lc($a[4]) : "http";
  
  $hash->{SERVERADDR}            = $serveraddr;
  $hash->{SERVERPORT}            = $serverport;
  $hash->{MODEL}                 = "ChatBot";         
  $hash->{PROTOCOL}              = $proto;
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                         # Modul Meta.pm nicht vorhanden
  
  # benötigte API's in $hash einfügen
  $hash->{HELPER}{APIINFO}        = "SYNO.API.Info";                             # Info-Seite für alle API's, einzige statische Seite !                                                    
  $hash->{HELPER}{CHATEXTERNAL}   = "SYNO.Chat.External"; 
    
  # Versionsinformationen setzen
  SSChatBot_setVersionInfo($hash);
  
  # Token lesen
  SSChatBot_getToken($hash,1,"botToken");
  
  # Index der Sendequeue initialisieren
  $data{SSChatBot}{$name}{sendqueue}{index} = 0;
  
  readingsBeginUpdate($hash); 
  readingsBulkUpdate($hash,"state", "Initialized");                              # Init state
  readingsEndUpdate($hash,1);              

  # initiale Routinen nach Start ausführen , verzögerter zufälliger Start
  RemoveInternalTimer($hash, "SSChatBot_initonboot");
  InternalTimer(gettimeofday()+int(rand(15)), "SSChatBot_initonboot", $hash, 0);  

return undef;
}

################################################################
# Die Undef-Funktion wird aufgerufen wenn ein Gerät mit delete 
# gelöscht wird oder bei der Abarbeitung des Befehls rereadcfg, 
# der ebenfalls alle Geräte löscht und danach das 
# Konfigurationsfile neu einliest. 
# Funktion: typische Aufräumarbeiten wie das 
# saubere Schließen von Verbindungen oder das Entfernen von 
# internen Timern, sofern diese im Modul zum Pollen verwendet 
# wurden.
################################################################
sub SSChatBot_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  
  delete $data{SSChatBot}{$name};
  RemoveInternalTimer($hash);
   
return undef;
}

#######################################################################################################
# Mit der X_DelayedShutdown Funktion kann eine Definition das Stoppen von FHEM verzögern um asynchron 
# hinter sich aufzuräumen.  
# Je nach Rückgabewert $delay_needed wird der Stopp von FHEM verzögert (0|1).
# Sobald alle nötigen Maßnahmen erledigt sind, muss der Abschluss mit CancelDelayedShutdown($name) an 
# FHEM zurückgemeldet werden. 
#######################################################################################################
sub SSChatBot_DelayedShutdown($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

return 0;
}

#################################################################
# Wenn ein Gerät in FHEM gelöscht wird, wird zuerst die Funktion 
# X_Undef aufgerufen um offene Verbindungen zu schließen, 
# anschließend wird die Funktion X_Delete aufgerufen. 
# Funktion: Aufräumen von dauerhaften Daten, welche durch das 
# Modul evtl. für dieses Gerät spezifisch erstellt worden sind. 
# Es geht hier also eher darum, alle Spuren sowohl im laufenden 
# FHEM-Prozess, als auch dauerhafte Daten bspw. im physikalischen 
# Gerät zu löschen die mit dieser Gerätedefinition zu tun haben. 
#################################################################
sub SSChatBot_Delete($$) {
  my ($hash, $arg) = @_;
  my $name  = $hash->{NAME};
  my $index = $hash->{TYPE}."_".$hash->{NAME}."_botToken";
  
  # gespeicherte Credentials löschen
  setKeyValue($index, undef);
    
return undef;
}

################################################################
sub SSChatBot_Attr($$$$) {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my ($do,$val,$cache);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
       
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
		if(SSChatBot_IsModelCam($hash)) {
            $val = ($do == 1 ? "inactive" : "off");
		} else {
		    $val = ($do == 1 ? "disabled" : "initialized");
		}
		
		if ($do == 1) {
		    RemoveInternalTimer($hash);
		} else {
		    InternalTimer(gettimeofday()+int(rand(30)), "SSChatBot_initonboot", $hash, 0);
		}
    
        readingsSingleUpdate($hash, "state", $val, 1);
    }
    
    if ($cmd eq "set") {
        if ($aName =~ m/httptimeout/) {
            unless ($aVal =~ /^\d+$/) { return " The Value for $aName is not valid. Use only figures 1-9 !";}
        }       
    }
    
return undef;
}

################################################################
sub SSChatBot_Set($@) {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];
  my $prop1   = $a[3];
  my $prop2   = $a[4];
  my $prop3   = $a[5];
  my $success;
  my $setlist;
        
  return if(IsDisabled($name));
 
  if(!$hash->{TOKEN}) {
      # initiale setlist für neue Devices
      $setlist = "Unknown argument $opt, choose one of ".
	             "botToken "
                 ;  
  } else {
      $setlist = "Unknown argument $opt, choose one of ".
                 "botToken ".
                 "listSendqueue:noArg ".
                 "sendItem:textField-long "
                 ;
  }
 
  if ($opt eq "botToken") {
      $prop =~ /^(%22)(.*)(%22)$/ if($prop);
      return "The token you entered was incomplete ! \n".
             "Take the complete string after \"&token=\" from the Synology Chat \"Integration->Bots->incoming URL\" menu. \n".
             "The token has the form like \"%22U6FOMH9IgT2WECJceaIW0fNwEiVVfqWQFP7gJQUJ6vpaGo8Z1SJkOGP7zlVIscCp%22\" " if (!$1 || !$3);         
      ($success) = SSChatBot_setToken($hash,$2,"botToken");
	  
	  if($success) {
		  return "botToken saved successfully";
	  } else {
          return "Error while saving botToken - see logfile for details";
	  }
      
  } elsif ($opt eq "listSendqueue") {
        my $sub = sub ($) { 
            my ($idx) = @_; 
            my $ret;
            foreach my $key (reverse sort keys %{$data{SSChatBot}{$name}{sendqueue}{entries}{$idx}}) {
                $ret .= ", " if($ret);
                $ret .= $key."=>".$data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{$key};
            }
            return $ret;
        };
	    
        my $sq;
	    foreach my $idx (sort{$a<=>$b}keys %{$data{SSChatBot}{$name}{sendqueue}{entries}}) { 
            $sq .= $idx." => ".$sub->($idx)."\n"; 			
		}
	    return $sq;
  
  } elsif ($opt eq "sendItem") {
       # text="First line of message to post.\nAlso you can have a second line of message." users="user1"
       # text="<https://www.synology.com>" users="user1"
       # text="Check this!! <https://www.synology.com|Click here> for details!" users="user1,user2" 
       # text="a fun image" fileUrl="http://imgur.com/xxxxx" users="user1,user2"  
       my $cmd = join(" ", @a);
       my ($text,$users,$fileUrl);
       my($a, $h) = parseParams($cmd);
       if($h) {
           $text    = $h->{text}    if(defined $h->{text});
           $users   = $h->{users}   if(defined $h->{users});
           $fileUrl = $h->{fileUrl} if(defined $h->{fileUrl});
       }
       
       return "Your sendstring is incorrect. It must contain at least the \"text\" tag like 'text=\"...\" '." if(!$text);
       
       $users = AttrVal($name,"recepUser", "") if(!$users);
       return "You haven't defined any receptor for send the message to. ".
              "You have to use the \"users\" tag or define default receptors with attribute \"recepUser\"." if(!$users);
       
       # User aufsplitten und zu jedem die ID ermitteln
       my @ua = split(/,/, $users);
       foreach (@ua) {
           next if(!$_);
           my $uid = $hash->{HELPER}{USERS}{$_}{id};
           return "The receptor \"$_\" seems to be unknown because its ID coulnd't be found." if(!$uid);
           
           # Eintrag zur SendQueue hinzufügen
           # Werte: (name,opmode,method,userid,text,fileUrl,channel,attachment)
           SSChatBot_addQueue($name, "sendItem", "chatbot", $uid, $text, $fileUrl, "", "");
       }
       
       SSChatBot_getapisites($name);
  
  } else {
      return "$setlist"; 
  }
  
return;
}

################################################################
sub SSChatBot_Get($@) {
    my ($hash, @a) = @_;
    return "\"get X\" needs at least an argument" if ( @a < 2 );
    my $name = shift @a;
    my $opt = shift @a;
	my $arg = shift @a;
	my $arg1 = shift @a;
	my $arg2 = shift @a;
	my $ret = "";
	my $getlist;

    if(!$hash->{TOKEN}) {
        return;
        
	} else {
	    $getlist = "Unknown argument $opt, choose one of ".
				   "storedToken:noArg ".
                   "chatUserlist:noArg ".
                   "chatChannellist:noArg ".
                   "versionNotes " 
                   ;
	}
		  
    return if(IsDisabled($name));             
              
    if ($opt eq "storedToken") {
	    if (!$hash->{TOKEN}) {return "Token of $name is not set - make sure you've set it with \"set $name botToken <TOKEN>\"";}
        # Token abrufen
        my ($success, $token) = SSChatBot_getToken($hash,0,"botToken");
        unless ($success) {return "Token couldn't be retrieved successfully - see logfile"};
        
        return "Stored Token to act as Synology Chat Bot:\n".
               "=========================================\n".
               "$token \n"
               ;   
    
	} elsif ($opt eq "chatUserlist") {
        # übergebenen CL-Hash (FHEMWEB) in Helper eintragen 
	    SSChatBot_getclhash($hash,1);
        
        # Eintrag zur SendQueue hinzufügen
        # Werte: (name,opmode,method,userid,text,fileUrl,channel,attachment)
        SSChatBot_addQueue($name, "chatUserlist", "user_list", "", "", "", "", "");
        
        SSChatBot_getapisites($name);
    
    } elsif ($opt eq "chatChannellist") {
        # übergebenen CL-Hash (FHEMWEB) in Helper eintragen 
	    SSChatBot_getclhash($hash,1);
        
        # Eintrag zur SendQueue hinzufügen
        # Werte: (name,opmode,method,userid,text,fileUrl,channel,attachment)
        SSChatBot_addQueue($name, "chatChannellist", "channel_list", "", "", "", "", "");
        
        SSChatBot_getapisites($name);
    
    } elsif ($opt =~ /versionNotes/) {
	  my $header  = "<b>Module release information</b><br>";
      my $header1 = "<b>Helpful hints</b><br>";
      my %hs;
	  
	  # Ausgabetabelle erstellen
	  my ($ret,$val0,$val1);
      my $i = 0;
	  
      $ret  = "<html>";
      
      # Hints
      if(!$arg || $arg =~ /hints/ || $arg =~ /[\d]+/) {
          $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header1 <br>");
          $ret .= "<table class=\"block wide internals\">";
          $ret .= "<tbody>";
          $ret .= "<tr class=\"even\">";  
          if($arg && $arg =~ /[\d]+/) {
              my @hints = split(",",$arg);
              foreach (@hints) {
                  if(AttrVal("global","language","EN") eq "DE") {
                      $hs{$_} = $SSChatBot_vHintsExt_de{$_};
                  } else {
                      $hs{$_} = $SSChatBot_vHintsExt_en{$_};
                  }
              }                      
          } else {
              if(AttrVal("global","language","EN") eq "DE") {
                  %hs = %SSChatBot_vHintsExt_de;
              } else {
                  %hs = %SSChatBot_vHintsExt_en; 
              }
          }          
          $i = 0;
          foreach my $key (SSChatBot_sortVersion("desc",keys %hs)) {
              $val0 = $hs{$key};
              $ret .= sprintf("<td style=\"vertical-align:top\"><b>$key</b>  </td><td style=\"vertical-align:top\">$val0</td>" );
              $ret .= "</tr>";
              $i++;
              if ($i & 1) {
                  # $i ist ungerade
                  $ret .= "<tr class=\"odd\">";
              } else {
                  $ret .= "<tr class=\"even\">";
              }
          }
          $ret .= "</tr>";
          $ret .= "</tbody>";
          $ret .= "</table>";
          $ret .= "</div>";
      }
	  
      # Notes
      if(!$arg || $arg =~ /rel/) {
          $ret .= sprintf("<div class=\"makeTable wide\"; style=\"text-align:left\">$header <br>");
          $ret .= "<table class=\"block wide internals\">";
          $ret .= "<tbody>";
          $ret .= "<tr class=\"even\">";
          $i = 0;
          foreach my $key (SSChatBot_sortVersion("desc",keys %SSChatBot_vNotesExtern)) {
              ($val0,$val1) = split(/\s/,$SSChatBot_vNotesExtern{$key},2);
              $ret .= sprintf("<td style=\"vertical-align:top\"><b>$key</b>  </td><td style=\"vertical-align:top\">$val0  </td><td>$val1</td>" );
              $ret .= "</tr>";
              $i++;
              if ($i & 1) {
                  # $i ist ungerade
                  $ret .= "<tr class=\"odd\">";
              } else {
                  $ret .= "<tr class=\"even\">";
              }
          }
          $ret .= "</tr>";
          $ret .= "</tbody>";
          $ret .= "</table>";
          $ret .= "</div>";
	  }
      
      $ret .= "</html>";
					
	  return $ret;
  
    } else {
        return "$getlist";
	}

return $ret;                                                        # not generate trigger out of command
}

######################################################################################
#                   initiale Startroutinen nach Restart FHEM
######################################################################################
sub SSChatBot_initonboot ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash, "SSChatBot_initonboot");
  
  if ($init_done == 1) {
     RemoveInternalTimer($hash);                                                                     # alle Timer löschen
     
     CommandGet(undef, "$name chatUserlist");     
  
  } else {
      InternalTimer(gettimeofday()+3, "SSChatBot_initonboot", $hash, 0);
  }
  
return;
}

######################################################################################
#                            Eintrag zur SendQueue hinzufügen
######################################################################################
sub SSChatBot_addQueue ($$$$$$$$) {
    my ($name,$opmode,$method,$userid,$text,$fileUrl,$channel,$attachment) = @_;
    my $hash                = $defs{$name};

   $data{SSChatBot}{$name}{sendqueue}{index}++;
   my $index = $data{SSChatBot}{$name}{sendqueue}{index};
   
   my $pars = {'opmode'     => $opmode,   
               'method'     => $method, 
               'userid'     => $userid,
               'channel'    => $channel,
               'text'       => $text,
               'attachment' => $attachment,
               'fileUrl'    => $fileUrl,  
               'retryCount' => 0,               
              };
				      
   $data{SSChatBot}{$name}{sendqueue}{entries}{$index} = $pars;   
   
return;
}


#############################################################################################
#              Erfolg einer Rückkehrroutine checken und ggf. Send-Retry ausführen
#              bzw. den SendQueue-Eintrag bei Erfolg löschen
#              $name  = Name des Chatbot-Devices
#              $retry = 0 -> Opmode erfolgreich (DS löschen), 
#                       1 -> Opmode nicht erfolgreich (Abarbeitung verzögert wiederholen)
#############################################################################################
sub SSChatBot_checkretry ($$) {  
  my ($name,$retry) = @_;
  my $hash          = $defs{$name};  
  my $idx           = $hash->{OPIDX};
  
  if(!$retry) {
      # Befehl erfolgreich, Senden nur neu starten wenn weitere Einträge in SendQueue
      delete $hash->{OPIDX};
      delete $data{SSChatBot}{$name}{sendqueue}{entries}{$idx};
      Log3($name, 4, "$name - Opmode \"$hash->{OPMODE}\" finished successfully, Sendqueue index \"$idx\" deleted.");
      return SSChatBot_chatop($name) if((sort{$a<=>$b}keys %{$data{SSChatBot}{$name}{sendqueue}{entries}})[0]);      # nächsten Eintrag abarbeiten wenn SendQueue nicht leer
  
  } else {
      # Befehl nicht erfolgreich, (verzögertes) Senden einplanen
      $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{retryCount}++;
      my $rc = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{retryCount};
      
      my $rs = 0;
      if($rc <= 5) {
          $rs = 5;
      } elsif ($rc < 10) {
          $rs = 20;
      } elsif ($rc < 15) {
          $rs = 60;
      } elsif ($rc < 20) {
          $rs = 1800;
      } elsif ($rc < 25) {
          $rs = 3600;
      } else {
          $rs = 86400;
      }
      
      Log3($name, 2, "$name - ERROR - \"$hash->{OPMODE}\" index \"$idx\" finished faulty. Restart SendQueue in $rs seconds (retryCount $rc).");
      
      RemoveInternalTimer($hash, "SSChatBot_chatop");
      InternalTimer(gettimeofday()+$rs, "SSChatBot_chatop", "$name", 0);
  }

return;
}

#############################################################################################################################
#######    Begin Kameraoperationen mit NonblockingGet (nicht blockierender HTTP-Call)                                 #######
#############################################################################################################################
sub SSChatBot_getapisites($) {
   my ($name)       = @_;
   my $hash         = $defs{$name};
   my $serveraddr   = $hash->{SERVERADDR};
   my $serverport   = $hash->{SERVERPORT};
   my $proto        = $hash->{PROTOCOL}; 
   my $apiinfo      = $hash->{HELPER}{APIINFO};                # Info-Seite für alle API's, einzige statische Seite ! 
   my $chatexternal = $hash->{HELPER}{CHATEXTERNAL};   
   my $url;
   my $param;
  
   # API-Pfade und MaxVersions ermitteln 
   Log3($name, 4, "$name - ####################################################"); 
   Log3($name, 4, "$name - ###            start Chat operation                 "); 
   Log3($name, 4, "$name - ####################################################"); 
   
   if ($hash->{HELPER}{APIPARSET}) {
       # API-Hashwerte sind bereits gesetzt -> Abruf überspringen
	   Log3($name, 4, "$name - API hashvalues already set - ignore get apisites");
       return SSChatBot_chatop($name);
   }

   my $httptimeout = AttrVal($name,"httptimeout",4);
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout: $httptimeout s");

   # URL zur Abfrage der Eigenschaften der  API's
   $url = "$proto://$serveraddr:$serverport/webapi/query.cgi?api=$apiinfo&method=Query&version=1&query=$chatexternal";

   Log3($name, 4, "$name - Call-Out: $url");
   
   $param = {
               url      => $url,
               timeout  => $httptimeout,
               hash     => $hash,
               method   => "GET",
               header   => "Accept: application/json",
               callback => \&SSChatBot_getapisites_parse
            };
   HttpUtils_NonblockingGet ($param);  
} 

####################################################################################  
#      Auswertung Abruf apisites
####################################################################################
sub SSChatBot_getapisites_parse ($) {
   my ($param, $err, $myjson) = @_;
   my $hash         = $param->{hash};
   my $name         = $hash->{NAME};
   my $serveraddr   = $hash->{SERVERADDR};
   my $serverport   = $hash->{SERVERPORT};
   my $chatexternal = $hash->{HELPER}{CHATEXTERNAL};   

   my ($chatexternalmaxver,$chatexternalpath);
  
    if ($err ne "") {
	    # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
        Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
       
        readingsSingleUpdate($hash, "Error", $err, 1);
        
        SSChatBot_checkretry($name,1);
        return;
		
    } elsif ($myjson ne "") {          
        # Evaluiere ob Daten im JSON-Format empfangen wurden
        ($hash, my $success) = SSChatBot_evaljson($hash,$myjson);
        
        unless ($success) {return;}
        
        my $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
        $success = $data->{'success'};
    
        if ($success) {
            my $logstr;
                        
          # Pfad und Maxversion von "SYNO.Chat.External" ermitteln
            my $chatexternalpath   = $data->{'data'}->{$chatexternal}->{'path'};
            $chatexternalpath      =~ tr/_//d if (defined($chatexternalpath));
            my $chatexternalmaxver = $data->{'data'}->{$chatexternal}->{'maxVersion'}; 
       
            $logstr = defined($chatexternalpath) ? "Path of $chatexternal selected: $chatexternalpath" : "Path of $chatexternal undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
            $logstr = defined($chatexternalmaxver) ? "MaxVersion of $chatexternal selected: $chatexternalmaxver" : "MaxVersion of $chatexternal undefined - Surveillance Station may be stopped";
            Log3($name, 4, "$name - $logstr");
			       
            # ermittelte Werte in $hash einfügen
            $hash->{HELPER}{CHATEXTERNALPATH}   = $chatexternalpath;
            $hash->{HELPER}{CHATEXTERNALMAXVER} = $chatexternalmaxver;        
       
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode","none");
            readingsBulkUpdate($hash,"Error","none");
            readingsEndUpdate($hash,1);
			
			# Webhook Hash values sind gesetzt
			$hash->{HELPER}{APIPARSET} = 1;
                        
        } else {
            my $error = "couldn't get Synology Chat API informations";
       
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode","none");
            readingsBulkUpdate($hash,"Error",$error);
            readingsEndUpdate($hash, 1);

            Log3($name, 2, "$name - ERROR - the API-Query couldn't be executed successfully");                    
            
            SSChatBot_checkretry($name,1);    
            return;
        }
	}
    
return SSChatBot_chatop($name);
}

#############################################################################################
#                                     Ausführung Operation
#############################################################################################
sub SSChatBot_chatop ($) {  
   my ($name) = @_;
   my $hash               = $defs{$name};
   my $proto              = $hash->{PROTOCOL};
   my $serveraddr         = $hash->{SERVERADDR};
   my $serverport         = $hash->{SERVERPORT};
   # my $opmode             = $hash->{OPMODE};
   my $chatexternal       = $hash->{HELPER}{CHATEXTERNAL}; 
   my $chatexternalpath   = $hash->{HELPER}{CHATEXTERNALPATH};
   my $chatexternalmaxver = $hash->{HELPER}{CHATEXTERNALMAXVER};
   my ($url,$httptimeout,$param,$error);
   
   # Token abrufen
   my ($success, $token) = SSChatBot_getToken($hash,0,"botToken");
   unless ($success) {
       $error = "The botToken couldn't be retrieved";
       
       readingsBeginUpdate($hash);
       readingsBulkUpdate($hash,"Errorcode","none");
       readingsBulkUpdate($hash,"Error",$error);
       readingsEndUpdate($hash, 1);

       Log3($name, 2, "$name - ERROR - $error"); 
       
       SSChatBot_checkretry($name,1);
       return;
   }
   
   # den nächsten Eintrag aus "SendQueue" verarbeiten
   my $idx = (sort{$a<=>$b}keys %{$data{SSChatBot}{$name}{sendqueue}{entries}})[0];
   if(!$idx) {
       Log3($name, 4, "$name - SendQueue is empty. Nothing to do ..."); 
       return;
   }
   $hash->{OPMODE} = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{opmode};
   $hash->{OPIDX}  = $idx;
   my $opmode      = $hash->{OPMODE};
   my $method      = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{method};
   my $userid      = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{userid};
   my $channel     = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{channel};
   my $text        = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{text};
   my $attachment  = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{attachment};
   my $fileUrl     = $data{SSChatBot}{$name}{sendqueue}{entries}{$idx}{fileUrl};
   Log3($name, 4, "$name - start SendQueue entry index \"$idx\" ($hash->{OPMODE}) for operation."); 

   $httptimeout   = AttrVal($name, "httptimeout", 4);
   
   Log3($name, 5, "$name - HTTP-Call will be done with httptimeout: $httptimeout s");

   if ($opmode =~ /^chatUserlist$|^chatChannellist$/) {
      $url = "$proto://$serveraddr:$serverport/webapi/$chatexternalpath?api=$chatexternal&version=$chatexternalmaxver&method=$method&token=\"$token\"";
   }
   
   if ($opmode eq "sendItem") {
      # Form: payload={"text": "a fun image", "file_url": "http://imgur.com/xxxxx" "user_ids": [5]} 
      #       payload={"text": "First line of message to post in the channel" "user_ids": [5]}
      #       payload={"text": "Check this!! <https://www.synology.com|Click here> for details!" "user_ids": [5]}
      
      $url  = "$proto://$serveraddr:$serverport/webapi/$chatexternalpath?api=$chatexternal&version=$chatexternalmaxver&method=$method&token=\"$token\"";
      $url .= "&payload={";
      $url .= "\"text\": \"$text\","        if($text);
      $url .= "\"file_url\": \"$fileUrl\"," if($fileUrl);
      $url .= "\"user_ids\": [$userid]"     if($userid);
      $url .= "}";
   }

   Log3($name, 4, "$name - Call-Out: $url");
   
   $param = {
            url      => $url,
            timeout  => $httptimeout,
            hash     => $hash,
            method   => "GET",
            header   => "Accept: application/json",
            callback => \&SSChatBot_chatop_parse
            };
   
   HttpUtils_NonblockingGet ($param);   
} 
  
#############################################################################################
#                                Callback from SSChatBot_chatop
#############################################################################################
sub SSChatBot_chatop_parse ($) {  
   my ($param, $err, $myjson) = @_;
   my $hash               = $param->{hash};
   my $name               = $hash->{NAME};
   my $proto              = $hash->{PROTOCOL};
   my $serveraddr         = $hash->{SERVERADDR};
   my $serverport         = $hash->{SERVERPORT};
   my $opmode             = $hash->{OPMODE};
   my ($rectime,$data,$success);
   my ($error,$errorcode);
   
   my $lang = AttrVal("global","language","EN");
   
   if ($err ne "") {
        # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
        Log3($name, 2, "$name - error while requesting ".$param->{url}." - $err");
        
        readingsSingleUpdate($hash, "Error", $err, 1);    

        SSChatBot_checkretry($name,1);        
        return;
   
   } elsif ($myjson ne "") {    
        # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
        # Evaluiere ob Daten im JSON-Format empfangen wurden 
        ($hash,$success,$myjson) = SSChatBot_evaljson($hash,$myjson);        
        unless ($success) {
            Log3($name, 4, "$name - Data returned: ".$myjson);
            return;
        }
        
        $data = decode_json($myjson);
        
        # Logausgabe decodierte JSON Daten
        Log3($name, 5, "$name - JSON returned: ". Dumper $data);
   
        $success = $data->{'success'};

        if ($success) {       

            if ($opmode eq "chatUserlist") {    
                my %users = ();   
                my ($un,$ui,$st,$nn,$em,$uids);           
				my $i    = 0;
                
                my $out  = "<html>";
                $out    .= "<b>Synology Chat Server visible Users</b> <br><br>";
                $out    .= "<table class=\"roomoverview\" style=\"text-align:left; border:1px solid; padding:5px; border-spacing:5px; margin-left:auto; margin-right:auto;\">";
                $out    .= "<tr><td> <b>Username</b> </td><td> <b>ID</b> </td><td> <b>state</b> </td><td> <b>Nickname</b> </td><td> <b>Email</b> </td><td></tr>";
                $out    .= "<tr><td>  </td><td> </td><td> </td><td> </td><td> </td><td></tr>";
                
                while ($data->{'data'}->{'users'}->[$i]) {
                    my $deleted = SSChatBot_jboolmap($data->{'data'}->{'users'}->[$i]->{'deleted'});
                    my $isdis   = SSChatBot_jboolmap($data->{'data'}->{'users'}->[$i]->{'is_disabled'});
                    if($deleted ne "true" && $isdis ne "true") {
                        $un = $data->{'data'}->{'users'}->[$i]->{'username'};
                        $ui = $data->{'data'}->{'users'}->[$i]->{'user_id'};
                        $st = $data->{'data'}->{'users'}->[$i]->{'status'};
                        $nn = $data->{'data'}->{'users'}->[$i]->{'nickname'};
                        $em = $data->{'data'}->{'users'}->[$i]->{'user_props'}->{'email'};
                        $users{$un}{id}       = $ui;
                        $users{$un}{status}   = $st;
                        $users{$un}{nickname} = $nn;
                        $users{$un}{email}    = $em;
                        $uids                .= "," if($uids);
                        $uids                .= $un;
                        $out                 .= "<tr><td> $un </td><td> $ui </td><td> $st </td><td>  $nn </td><td> $em </td><td></tr>";
                    }
					$i++;
                }
                $hash->{HELPER}{USERS} = \%users if(%users);
                
                my @newa;
                my @deva = split(" ", $hash->{".AttrList"});
                foreach (@deva) {
                     push @newa, $_ if($_ !~ /recepUser/);
                }
                push @newa, ($uids?"recepUser:multiple-strict,$uids ":"recepUser:--no#userlist#selectable-- ");
                $hash->{".AttrList"} = join(" ", @newa);
                
                $out .= "</table>";
                $out .= "</html>";
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);  

				# Ausgabe Popup der User-Daten (nach readingsEndUpdate positionieren sonst 
                # "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)	    
				asyncOutput($hash->{HELPER}{CL}{1},"$out");
				delete($hash->{HELPER}{CL});                
			
            } elsif ($opmode eq "chatChannellist") {    
                my %channels = ();   
                my ($cn,$ci,$cr,$mb,$ty,$cids);             
				my $i    = 0;
                
                my $out  = "<html>";
                $out    .= "<b>Synology Chat Server visible Channels</b> <br><br>";
                $out    .= "<table class=\"roomoverview\" style=\"text-align:left; border:1px solid; padding:5px; border-spacing:5px; margin-left:auto; margin-right:auto;\">";
                $out    .= "<tr><td> <b>Channelname</b> </td><td> <b>ID</b> </td><td> <b>Creator</b> </td><td> <b>Members</b> </td><td> <b>Type</b> </td><td></tr>";
                $out    .= "<tr><td>  </td><td> </td><td> </td><td> </td><td> </td><td></tr>";
                
                while ($data->{'data'}->{'channels'}->[$i]) {
                    my $cn = SSChatBot_jboolmap($data->{'data'}->{'channels'}->[$i]->{'name'});
                    if($cn) {
                        $ci = $data->{'data'}->{'channels'}->[$i]->{'channel_id'};
                        $cr = $data->{'data'}->{'channels'}->[$i]->{'creator_id'};
                        $mb = $data->{'data'}->{'channels'}->[$i]->{'members'};
                        $ty = $data->{'data'}->{'channels'}->[$i]->{'type'};
                        $channels{$cn}{id}       = $ci;
                        $channels{$cn}{creator}  = $cr;
                        $channels{$cn}{members}  = $mb;
                        $channels{$cn}{type}     = $ty;
                        $cids                .= "," if($cids);
                        $cids                .= $cn;
                        $out                 .= "<tr><td> $cn </td><td> $ci </td><td> $cr </td><td>  $mb </td><td> $ty </td><td></tr>";
                    }
					$i++;
                }
                $hash->{HELPER}{CHANNELS} = \%channels if(%channels);
                
                $out .= "</table>";
                $out .= "</html>";
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);  

				# Ausgabe Popup der User-Daten (nach readingsEndUpdate positionieren sonst 
                # "Connection lost, trying reconnect every 5 seconds" wenn > 102400 Zeichen)	    
				asyncOutput($hash->{HELPER}{CL}{1},"$out");
				delete($hash->{HELPER}{CL});                
			
            } elsif ($opmode eq "sendItem") {

                readingsBeginUpdate($hash);
                readingsBulkUpdate($hash,"Errorcode","none");
                readingsBulkUpdate($hash,"Error","none");
                readingsEndUpdate($hash, 1);             

            }            

            SSChatBot_checkretry($name,0);
            readingsSingleUpdate($hash,"state", "connected", 1);
           
        } else {
            # die API-Operation war fehlerhaft
            # Errorcode aus JSON ermitteln
            $errorcode = $data->{'error'}->{'code'};

            # Fehlertext zum Errorcode ermitteln
            $error = SSChatBot_experror($hash,$errorcode);
			
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"Errorcode", $errorcode);
            readingsBulkUpdate($hash,"Error",     $error);
            readingsBulkUpdate($hash,"state",     "disconnected") if($errorcode =~ /102/);
            readingsEndUpdate($hash, 1);
       
            Log3($name, 2, "$name - ERROR - Operation $opmode was not successful. Errorcode: $errorcode - $error");
            
            SSChatBot_checkretry($name,1);
        }
                
       undef $data;
       undef $myjson;
   }

return;
}

###############################################################################
#   Test ob JSON-String empfangen wurde
###############################################################################
sub SSChatBot_evaljson($$) { 
  my ($hash,$myjson) = @_;
  my $OpMode  = $hash->{OPMODE};
  my $name    = $hash->{NAME};
  my $success = 1;
  
  eval {decode_json($myjson)} or do {
          $success = 0;
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,"Errorcode","none");
          readingsBulkUpdate($hash,"Error","malformed JSON string received");
          readingsEndUpdate($hash, 1);  
  };
  
return($hash,$success,$myjson);
}

###############################################################################
#                       JSON Boolean Test und Mapping
###############################################################################
sub SSChatBot_jboolmap($){ 
  my ($bool)= @_;
  
  if(JSON::is_bool($bool)) {
      $bool = $bool?"true":"false";
  }
  
return $bool;
}


##############################################################################
#  Auflösung Errorcodes SVS API
#  Übernahmewerte sind $hash, $errorcode
##############################################################################
sub SSChatBot_experror ($$) {
  my ($hash,$errorcode) = @_;
  my $device = $hash->{NAME};
  my $error;
  
  unless (exists($SSChatBot_errlist{"$errorcode"})) {$error = "Message of errorcode \"$errorcode\" not found. Please turn to Synology Web API-Guide."; return ($error);}

  # Fehlertext aus Hash-Tabelle %errorlist ermitteln
  $error = $SSChatBot_errlist{"$errorcode"};
  
return ($error);
}

################################################################
# sortiert eine Liste von Versionsnummern x.x.x
# Schwartzian Transform and the GRT transform
# Übergabe: "asc | desc",<Liste von Versionsnummern>
################################################################
sub SSChatBot_sortVersion (@){
  my ($sseq,@versions) = @_;

  my @sorted = map {$_->[0]}
			   sort {$a->[1] cmp $b->[1]}
			   map {[$_, pack "C*", split /\./]} @versions;
			 
  @sorted = map {join ".", unpack "C*", $_}
            sort
            map {pack "C*", split /\./} @versions;
  
  if($sseq eq "desc") {
      @sorted = reverse @sorted;
  }
  
return @sorted;
}

######################################################################################
#                            botToken speichern
######################################################################################
sub SSChatBot_setToken ($$@) {
    my ($hash, $token, $ao) = @_;
    my $name           = $hash->{NAME};
    my ($success, $credstr, $index, $retcode);
    my (@key,$len,$i);   
    
    $credstr = encode_base64($token);
    
    # Beginn Scramble-Routine
    @key = qw(1 3 4 5 6 3 2 1 9);
    $len = scalar @key;  
    $i = 0;  
    $credstr = join "",  
            map { $i = ($i + 1) % $len;  
            chr((ord($_) + $key[$i]) % 256) } split //, $credstr; 
    # End Scramble-Routine    
       
    $index   = $hash->{TYPE}."_".$hash->{NAME}."_".$ao;
    $retcode = setKeyValue($index, $credstr);
    
    if ($retcode) { 
        Log3($name, 2, "$name - Error while saving Token - $retcode");
        $success = 0;
    } else {
        ($success, $token) = SSChatBot_getToken($hash,1,$ao);        # Credentials nach Speicherung lesen und in RAM laden ($boot=1)
    }

return ($success);
}

######################################################################################
#                             botToken lesen
######################################################################################
sub SSChatBot_getToken ($$$) {
    my ($hash,$boot, $ao) = @_;
    my $name               = $hash->{NAME};
    my ($success, $token, $index, $retcode, $credstr);
    my (@key,$len,$i);
    
    if ($boot) {
        # mit $boot=1 botToken von Platte lesen und als scrambled-String in RAM legen
        $index               = $hash->{TYPE}."_".$hash->{NAME}."_".$ao;
        ($retcode, $credstr) = getKeyValue($index);
    
        if ($retcode) {
            Log3($name, 2, "$name - Unable to read botToken from file: $retcode");
            $success = 0;
        }  

        if ($credstr) {
            # beim Boot scrambled botToken in den RAM laden
            $hash->{HELPER}{TOKEN} = $credstr;
    
            # "TOKEN" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung
            $hash->{TOKEN} = "Set";
            $success = 1;
        }
    
    } else {
        # boot = 0 -> botToken aus RAM lesen, decoden und zurückgeben
        $credstr = $hash->{HELPER}{TOKEN};
        
        if($credstr) {
            # Beginn Descramble-Routine
            @key = qw(1 3 4 5 6 3 2 1 9); 
            $len = scalar @key;  
            $i = 0;  
            $credstr = join "",  
            map { $i = ($i + 1) % $len;  
            chr((ord($_) - $key[$i] + 256) % 256) }  
            split //, $credstr;   
            # Ende Descramble-Routine
            
            $token = decode_base64($credstr);
            
            my $logtok = AttrVal($name, "showTokenInLog", "0") == 1 ? $token : "********";
        
            Log3($name, 4, "$name - botToken read from RAM: $logtok");
        
        } else {
            Log3($name, 2, "$name - botToken not set in RAM !");
        }
    
        $success = (defined($token)) ? 1 : 0;
    }

return ($success, $token);        
}

#############################################################################################
#             Leerzeichen am Anfang / Ende eines strings entfernen           
#############################################################################################
sub SSChatBot_trim ($) {
  my $str = shift;
  $str =~ s/^\s+|\s+$//g;

return ($str);
}

#############################################################################################
# Clienthash übernehmen oder zusammenstellen
# Identifikation ob über FHEMWEB ausgelöst oder nicht -> erstellen $hash->CL
#############################################################################################
sub SSChatBot_getclhash($;$$) {      
  my ($hash,$nobgd)= @_;
  my $name  = $hash->{NAME};
  my $ret;
  
  if($nobgd) {
      # nur übergebenen CL-Hash speichern, 
	  # keine Hintergrundverarbeitung bzw. synthetische Erstellung CL-Hash
	  $hash->{HELPER}{CL}{1} = $hash->{CL};
	  return undef;
  }

  if (!defined($hash->{CL})) {
      # Clienthash wurde nicht übergeben und wird erstellt (FHEMWEB Instanzen mit canAsyncOutput=1 analysiert)
	  my $outdev;
	  my @webdvs = devspec2array("TYPE=FHEMWEB:FILTER=canAsyncOutput=1:FILTER=STATE=Connected");
	  my $i = 1;
      foreach (@webdvs) {
          $outdev = $_;
          next if(!$defs{$outdev});
		  $hash->{HELPER}{CL}{$i}->{NAME} = $defs{$outdev}{NAME};
          $hash->{HELPER}{CL}{$i}->{NR}   = $defs{$outdev}{NR};
		  $hash->{HELPER}{CL}{$i}->{COMP} = 1;
          $i++;				  
      }
  } else {
      # übergebenen CL-Hash in Helper eintragen
	  $hash->{HELPER}{CL}{1} = $hash->{CL};
  }
	  
  # Clienthash auflösen zur Fehlersuche (aufrufende FHEMWEB Instanz
  if (defined($hash->{HELPER}{CL}{1})) {
      for (my $k=1; (defined($hash->{HELPER}{CL}{$k})); $k++ ) {
	      Log3($name, 4, "$name - Clienthash number: $k");
          while (my ($key,$val) = each(%{$hash->{HELPER}{CL}{$k}})) {
              $val = $val?$val:" ";
              Log3($name, 4, "$name - Clienthash: $key -> $val");
          }
	  }
  } else {
      Log3($name, 2, "$name - Clienthash was neither delivered nor created !");
	  $ret = "Clienthash was neither delivered nor created. Can't use asynchronous output for function.";
  }
  
return ($ret);
}

#############################################################################################
#                          Versionierungen des Moduls setzen
#                  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#############################################################################################
sub SSChatBot_setVersionInfo($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (SSChatBot_sortVersion("desc",keys %SSChatBot_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
	  # META-Daten sind vorhanden
	  $modules{$type}{META}{version} = "v".$v;                                        # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SSChatBot}{META}}
	  if($modules{$type}{META}{x_version}) {                                          # {x_version} ( nur gesetzt wenn $Id: 50_SSChatBot.pm 20534 2019-11-18 17:50:17Z DS_Starter $ im Kopf komplett! vorhanden )
		  $modules{$type}{META}{x_version} =~ s/1.1.1/$v/g;
	  } else {
		  $modules{$type}{META}{x_version} = $v; 
	  }
	  return $@ unless (FHEM::Meta::SetInternals($hash));                             # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 50_SSChatBot.pm 20534 2019-11-18 17:50:17Z DS_Starter $ im Kopf komplett! vorhanden )
	  if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
	      # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
		  # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
	      use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );                                          
      }
  } else {
	  # herkömmliche Modulstruktur
	  $hash->{VERSION} = $v;
  }
  
return;
}

#############################################################################################
#                                       Hint Hash EN           
#############################################################################################
%SSChatBot_vHintsExt_en = (
);

#############################################################################################
#                                       Hint Hash DE           
#############################################################################################
%SSChatBot_vHintsExt_de = (

);

1;

=pod
=item summary    module to use a Synology Chat Bot
=item summary_DE Modul zur Installation eines Synology Chat Bot
=begin html

<a name="SSChatBot"></a>
<h3>SSChatBot</h3>
<ul>

  <a name="SSChatBotdefine"></a>
  <b>Define</b>
  <br>
  <ul>
  </ul>
  <br>  
  
  <a name="SSChatBotset"></a>
  <b>Set </b>
  <br>
  <ul>    
  </ul>
  <br>


<a name="SSChatBotget"></a>
<b>Get</b>
  <br>
  <ul>
  </ul>
  <br>

<a name="SSChatBotattr"></a>
<b>Attributes</b>
  <br>
  <ul>
  </ul>
  <br>

</ul>


=end html
=begin html_DE

<a name="SSChatBot"></a>
<h3>SSChatBot</h3>
<ul>


<a name="SSChatBotdefine"></a>
<b>Definition</b>
  <br>
  <ul>    
  </ul>
  <br>
  
<a name="SSChatBotset"></a>
<b>Set </b>
  <br>
  <ul>
  </ul>
  <br>

<a name="SSChatBotget"></a>
<b>Get</b>
  <br>
  <ul>
  </ul>
  <br>

<a name="SSChatBotattr"></a>
<b>Attribute</b>
  <br>
  <ul>  
 </ul>
 <br>
 
</ul>

=end html_DE

=for :application/json;q=META.json 50_SSChatBot.pm
{
  "abstract": "Integration of Synology Chat server into FHEM.",
  "x_lang": {
    "de": {
      "abstract": "Integration des Synology Chat Servers in FHEM."
    }
  },
  "keywords": [
    "synology",
    "synologychat",
    "chatbot",
    "chat"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "JSON": 0,
        "Data::Dumper": 0,
        "MIME::Base64": 0,
        "Time::HiRes": 0,
        "HttpUtils": 0,
        "Encode": 0        
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/SSChatBot_-_Integration des Synology Chat Servers in FHEM",
      "title": "SSChatBot - Integration des Synology Chat Servers in FHEM"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/50_SSChatBot.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/50_SSChatBot.pm"
      }      
    }
  }
}
=end :application/json;q=META.json

=cut
