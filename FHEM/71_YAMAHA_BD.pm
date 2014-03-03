# $Id$
##############################################################################
#
#     71_YAMAHA_BD.pm
#     An FHEM Perl module for controlling Yamaha Blu-Ray players
#     via network connection. As the interface is standardized
#     within all Yamaha Blue-Ray players, this module should work
#     with any player which has an ethernet or wlan connection.
#
#     Copyright by Markus Bloch
#     e-mail: Notausstieg0309@googlemail.com
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday sleep);
use HttpUtils;
 
sub YAMAHA_BD_Get($@);
sub YAMAHA_BD_Define($$);
sub YAMAHA_BD_GetStatus($;$);
sub YAMAHA_BD_Attr(@);
sub YAMAHA_BD_ResetTimer($;$);
sub YAMAHA_BD_Undefine($$);




###################################
sub
YAMAHA_BD_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "YAMAHA_BD_Get";
  $hash->{SetFn}     = "YAMAHA_BD_Set";
  $hash->{DefFn}     = "YAMAHA_BD_Define";
  $hash->{AttrFn}    = "YAMAHA_BD_Attr";
  $hash->{UndefFn}   = "YAMAHA_BD_Undefine";

  $hash->{AttrList}  = "do_not_notify:0,1 disable:0,1 request-timeout:1,2,3,4,5 model ".
                      $readingFnAttributes;
}

###################################
sub
YAMAHA_BD_GetStatus($;$)
{
    my ($hash, $local) = @_;
    my $name = $hash->{NAME};
    my $power;
    
    $local = 0 unless(defined($local));

    return "" if(!defined($hash->{helper}{ADDRESS}) or !defined($hash->{helper}{ON_INTERVAL}) or !defined($hash->{helper}{OFF_INTERVAL}));

    my $device = $hash->{helper}{ADDRESS};

    # get the model informations if no informations are available
    if(defined($hash->{MODEL}) or not defined($hash->{FIRMWARE}))
    {
		YAMAHA_BD_getModel($hash);
    }

    Log3 $name, 4, "YAMAHA_BD: Requesting system status";
    my $return = YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Service_Info>GetParam</Service_Info></System></YAMAHA_AV>");
    
    
    
    
  
    if(not defined($return) or $return eq "")
    {
		readingsSingleUpdate($hash, "state", "absent", 1);
		YAMAHA_BD_ResetTimer($hash) unless($local == 1);
		return;
    }
  
    readingsBeginUpdate($hash);
    if($return =~ /<Error_Info>(.+?)<\/Error_Info>/)
    {
        readingsBulkUpdate($hash, "error", lc($1));
    
    }
  
    Log3 $name, 4, "YAMAHA_BD: Requesting power state";
    $return = YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><Main_Zone><Power_Control><Power>GetParam</Power></Power_Control></Main_Zone></YAMAHA_AV>");
    
    if($return =~ /<Power>(.+?)<\/Power>/)
    {
       $power = $1;
       
		if($power eq "Standby" or $power eq "Network Standby")
		{	
			$power = "off";
		}
       readingsBulkUpdate($hash, "power", lc($power));
       readingsBulkUpdate($hash, "state", lc($power));
    }
    
    
	Log3 $name, 4, "YAMAHA_BD: Requesting playing info";
    $return = YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><Main_Zone><Play_Info>GetParam</Play_Info></Main_Zone></YAMAHA_AV>");
    
	if(defined($return))
	{
		if($return =~ /<Status>(.+?)<\/Status>/)
		{
			readingsBulkUpdate($hash, "playStatus", lc($1));
        }
        
        if($return =~ /<Chapter>(.+?)<\/Chapter>/)
		{
			readingsBulkUpdate($hash, "currentChapter", lc($1));
        }
        
        if($return =~ /<File_Name>(.+?)<\/File_Name>/)
		{
			readingsBulkUpdate($hash, "currentMedia", $1);
        }
        
        if($return =~ /<Disc_Type>(.+?)<\/Disc_Type>/)
		{
			readingsBulkUpdate($hash, "discType", $1);
        }
        
        if($return =~ /<Input_Info><Status>(.+?)<\/Status><\/Input_Info/)
        {
    		readingsBulkUpdate($hash, "input", $1);	
        }
        elsif($return =~ /<Input_Info>(.+?)<\/Input_Info/)
        {
    		readingsBulkUpdate($hash, "input", $1);
        }
        
        if($return =~ /<Tray>(.+?)<\/Tray>/)
        {
			readingsBulkUpdate($hash, "trayStatus", lc($1));
        }
        
        if($return =~ /<Current_PlayTime>(.+?)<\/Current_PlayTime>/)
        {
            readingsBulkUpdate($hash, "playTimeCurrent", YAMAHA_BD_formatTimestamp($1));
        }    
         
        if($return =~ /<Total_Time>(.+?)<\/Total_Time>/)
        {
            readingsBulkUpdate($hash, "playTimeTotal", YAMAHA_BD_formatTimestamp($1));
        }
	    
    }
    else
    {
    
        Log3 $name, 3, "YAMAHA_BD: Received no response for playing info request";
    }
    
    
    readingsEndUpdate($hash, 1);
    
    YAMAHA_BD_ResetTimer($hash) unless($local == 1);
    
    Log3 $name, 4, "YAMAHA_BD $name: ".$hash->{STATE};
    
    return $hash->{STATE};
}

###################################
sub
YAMAHA_BD_Get($@)
{
    my ($hash, @a) = @_;
    my $what;
    my $return;
	
    return "argument is missing" if(int(@a) != 2);
    
    $what = $a[1];
    
    if(exists($hash->{READINGS}{$what}))
    {
        YAMAHA_BD_GetStatus($hash, 1);

        if(defined($hash->{READINGS}{$what}))
        {
			return $hash->{READINGS}{$what}{VAL};
		}
		else
		{
			return "no such reading: $what";
		}
    }
    else
    {
		$return = "unknown argument $what, choose one of";
		
		foreach my $reading (keys %{$hash->{READINGS}})
		{
			$return .= " $reading:noArg";
		}
		
		return $return;
	}
}


###################################
sub
YAMAHA_BD_Set($@)
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    my $result = "";
    
    return "No Argument given" if(!defined($a[1]));  
    
    # get the model informations if no informations are available
    if(defined($hash->{MODEL}) or not defined($hash->{FIRMWARE}))
    {
		YAMAHA_BD_getModel($hash);
    }
    
    my $what = $a[1];
    my $usage = "Unknown argument $what, choose one of on:noArg off:noArg statusRequest:noArg tray:open,close remoteControl:up,down,left,right,return,enter,OSDonScreen,OSDstatus,topMenu,popupMenu,red,green,blue,yellow,0,1,2,3,4,5,6,7,8,9,setup,home,clear fast:forward,reverse slow:forward,reverse skip:forward,reverse play:noArg pause:noArg stop:noArg";

    # Depending on the status response, use the short or long Volume command

		if($what eq "on")
		{
		
			$result = YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Power_Control><Power>On</Power></Power_Control></Main_Zone></YAMAHA_AV>");

			if(defined($result) and $result =~ /RC="0"/ and $result =~ /<Power><\/Power>/)	
			{
				# As the player startup takes about 5 seconds, the status will be already set, if the return code of the command is 0.
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "power", "on");
				readingsBulkUpdate($hash, "state","on");
				readingsEndUpdate($hash, 1);
				return undef;
			}
			else
			{
				return "Could not set power to on";
			}
		
		}
		elsif($what eq "off")
		{
			$result = YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Power_Control><Power>Network Standby</Power></Power_Control></Main_Zone></YAMAHA_AV>");
			
			if(not defined($result) or not $result =~ /RC="0"/)
			{
				# if the returncode isn't 0, than the command was not successful
				return "Could not set power to off";
			}
			
	    }
	    elsif($what eq "remoteControl")
	    {
			if($a[2] eq "up")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Cursor>Up</Cursor></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "down")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Cursor>Down</Cursor></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "left")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Cursor>Left</Cursor></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "right")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Cursor>Right</Cursor></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "enter")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Cursor>Enter</Cursor></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "return")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Cursor>Return</Cursor></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "OSDonScreen")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><OSD>OnScreen</OSD></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "OSDstatus")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><OSD>Status</OSD></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "topMenu")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Menu>TOP MENU</Menu></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "popupMenu")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Menu>POPUP MENU</Menu></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "red")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Color>RED</Color></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "green")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Color>GREEN</Color></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "blue")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Color>BLUE</Color></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "yellow")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Color>YELLOW</Color></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "0")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>0</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "1")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>1</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "2")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>2</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "3")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>3</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "4")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>4</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "5")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>5</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "6")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>6</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "7")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>7</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "8")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>8</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "9")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>9</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "setup")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Function>SETUP</Function></Remote_Control></Main_Zone></YAMAHA_AV>");
			} 
            elsif($a[2] eq "home")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Function>HOME</Function></Remote_Control></Main_Zone></YAMAHA_AV>");
			} 
            elsif($a[2] eq "clear")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Function>CLEAR</Function></Remote_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "subtitle")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Stream>SUBTITLE</Stream></Play_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "angle")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Stream>ANGLE</Stream></Play_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "pictureInPicture")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Stream>PinP</Stream></Play_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "secondVideo")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Stream>2nd Video</Stream></Play_Control></Main_Zone></YAMAHA_AV>");
			}
            elsif($a[2] eq "secondAudio")
			{
			    YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Stream>2nd Audio</Stream></Play_Control></Main_Zone></YAMAHA_AV>");
			}
			else
			{
			    return $usage;
			}
	    }
        elsif($what eq "tray")
		{
			if($a[2] eq "open")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Tray_Control><Tray>Open</Tray></Tray_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "close")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Tray_Control><Tray>Close</Tray></Tray_Control></Main_Zone></YAMAHA_AV>");
			}	
		}
        elsif($what eq "skip")
		{
			if($a[2] eq "forward")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Skip>Fwd</Skip></Play_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "reverse")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Skip>Rev</Skip></Play_Control></Main_Zone></YAMAHA_AV>");
			}	
		}
        elsif($what eq "fast")
		{
			if($a[2] eq "forward")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Fast>Fwd</Fast></Play_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "reverse")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Fast>Rev</Fast></Play_Control></Main_Zone></YAMAHA_AV>");
			}	
		}
        elsif($what eq "slow")
		{
			if($a[2] eq "forward")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Slow>Fwd</Slow></Play_Control></Main_Zone></YAMAHA_AV>");
			}
			elsif($a[2] eq "reverse")
			{
			    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Slow>Rev</Slow></Play_Control></Main_Zone></YAMAHA_AV>");
			}	
		}
        elsif($what eq "play")
		{
                YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Play>Play</Play></Play_Control></Main_Zone></YAMAHA_AV>");
		}
        elsif($what eq "pause")
		{
                YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Play>Pause</Play></Play_Control></Main_Zone></YAMAHA_AV>");
		}
        elsif($what eq "stop")
		{
                YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Play>Stop</Play></Play_Control></Main_Zone></YAMAHA_AV>");
		}
		elsif($what eq "statusRequest")
		{
			# Will be executed anyway on the end of the function			
		}
	    else
	    {
			return $usage;
	    }
	
    
    # Call the GetStatus() Function to retrieve the new values after setting something (with local flag, so the internal timer is not getting interupted)
    YAMAHA_BD_GetStatus($hash, 1);
    
    return undef;
    
}


#############################
sub
YAMAHA_BD_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    my $name = $hash->{NAME};
    
    if(! @a >= 3)
    {
	my $msg = "wrong syntax: define <name> YAMAHA_BD <ip-or-hostname> [<statusinterval>] [<presenceinterval>]";
	Log 2, $msg;
	return $msg;
    }

    my $address = $a[2];
  
    $hash->{helper}{ADDRESS} = $address;
    
    # if an update interval was given which is greater than zero, use it.
    if(defined($a[3]) and $a[3] > 0)
    {
		$hash->{helper}{OFF_INTERVAL}=$a[3];
    }
    else
    {
		$hash->{helper}{OFF_INTERVAL}=30;
    }
    
    # if a second update interval is given, use this as ON_INTERVAL, otherwise use OFF_INTERVAL instead.
    if(defined($a[4]) and $a[4] > 0)
    {
		$hash->{helper}{ON_INTERVAL}=$a[4];
    }
    else
    {
		$hash->{helper}{ON_INTERVAL}=$hash->{helper}{OFF_INTERVAL};
    } 

    unless(exists($hash->{helper}{AVAILABLE}) and ($hash->{helper}{AVAILABLE} == 0))
    {
    	$hash->{helper}{AVAILABLE} = 1;
    	readingsSingleUpdate($hash, "presence", "present", 1);
    }

    # start the status update timer
    $hash->{helper}{DISABLED} = 0 unless(exists($hash->{helper}{DISABLED}));
	YAMAHA_BD_ResetTimer($hash, 2);
  
  return undef;
}

##########################
sub
YAMAHA_BD_Attr(@)
{
    my @a = @_;
    my $hash = $defs{$a[1]};

    if($a[0] eq "set" && $a[2] eq "disable")
    {
        if($a[3] eq "0")
        {
             $hash->{helper}{DISABLED} = 0;
             YAMAHA_BD_GetStatus($hash, 1);
        }
        elsif($a[3] eq "1")
        {
            $hash->{helper}{DISABLED} = 1;
        }
    }
    elsif($a[0] eq "del" && $a[2] eq "disable")
    {
        $hash->{helper}{DISABLED} = 0;
        YAMAHA_BD_GetStatus($hash, 1);
    }

    # Start/Stop Timer according to new disabled-Value
    YAMAHA_BD_ResetTimer($hash);
    
    return undef;
}

#############################
sub
YAMAHA_BD_Undefine($$)
{
    my($hash, $name) = @_;
  
    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);
    return undef;
}


#############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################



#############################
sub
YAMAHA_BD_SendCommand($$;$)
{
    my ($hash, $command, $loglevel) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    my $response;
     
    Log3 $name, 5, "YAMAHA_BD: execute on $name: $command";
    
    # In case any URL changes must be made, this part is separated in this function".
    
    $response = GetFileFromURL("http://".$address.":50100/YamahaRemoteControl/ctrl", AttrVal($name, "request-timeout", 4) , "<?xml version=\"1.0\" encoding=\"utf-8\"?>".$command, 1, ($hash->{helper}{AVAILABLE} ? undef : 5));
    
    Log3 $name, 5, "YAMAHA_BD: got response for $name: $response" if(defined($response));
    
    unless(defined($response))
    {
	
		if((not exists($hash->{helper}{AVAILABLE})) or (exists($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 1))
		{
			Log3 $name, 3, "YAMAHA_BD: could not execute command on device $name. Please turn on your device in case of deactivated network standby or check for correct hostaddress.";
			readingsSingleUpdate($hash, "presence", "absent", 1);
		}
    }
    else
    {
		if (defined($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 0)
		{
			Log3 $name, 3, "YAMAHA_BD: device $name reappeared";
			readingsSingleUpdate($hash, "presence", "present", 1);            
		}
    }
    
    $hash->{helper}{AVAILABLE} = (defined($response) ? 1 : 0);
    
    return $response;

}


#############################
# resets the StatusUpdate Timer according to the device state and respective interval
sub
YAMAHA_BD_ResetTimer($;$)
{
    my ($hash, $interval) = @_;
    
    RemoveInternalTimer($hash);
    
    if($hash->{helper}{DISABLED} == 0)
    {
        if(defined($interval))
        {
            InternalTimer(gettimeofday()+$interval, "YAMAHA_BD_GetStatus", $hash, 0);
        }
        elsif(exists($hash->{READINGS}{presence}{VAL}) and $hash->{READINGS}{presence}{VAL} eq "present" and exists($hash->{READINGS}{power}{VAL}) and $hash->{READINGS}{power}{VAL} eq "on")
        {
            InternalTimer(gettimeofday()+$hash->{helper}{ON_INTERVAL}, "YAMAHA_BD_GetStatus", $hash, 0);
        }
        else
        {
            InternalTimer(gettimeofday()+$hash->{helper}{OFF_INTERVAL}, "YAMAHA_BD_GetStatus", $hash, 0);
        }
    }
}




#############################
# queries the player model, system-id, version
sub YAMAHA_BD_getModel($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    my $response;
    my $desc_url;
    
    $response = YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Config>GetParam</Config></System></YAMAHA_AV>");
    
    Log3 $name, 3, "YAMAHA_BD: could not get system configuration from device $name. Please turn on the device or check for correct hostaddress!" if (not defined($response) and defined($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 1);
    
    if(defined($response) and $response =~ /<Model_Name>(.+?)<\/Model_Name>.*<System_ID>(.+?)<\/System_ID>.*<Version>(.+?)<\/Version>/)
    {
        $hash->{MODEL} = $1;
        $hash->{SYSTEM_ID} = $2;
        $hash->{FIRMWARE} = $3;
    }
    else
    {
		return undef;
    }
    
    
    $hash->{MODEL} =~ s/\s*YAMAHA\s*//g;
    
	$attr{$name}{"model"} = $hash->{MODEL};
	
   
}

#############################
# formats a 3 byte Hex Value into human readable time duration
sub YAMAHA_BD_formatTimestamp($) 
{
    my ($hex) = @_;
    
    my ($hour) = sprintf("%02d", unpack("s", pack "s", hex(substr($hex, 0, 2))));
    my ($min) =  sprintf("%02d", unpack("s", pack "s", hex(substr($hex, 2, 2))));
    my ($sec) =  sprintf("%02d", unpack("s", pack "s", hex(substr($hex, 4, 2))));
    
    return "$hour:$min:$sec";
    
    
}

1;


=pod
=begin html

<a name="YAMAHA_BD"></a>
<h3>YAMAHA_BD</h3>
<ul>

  <a name="YAMAHA_BDdefine"></a>
  <b>Define</b>
  <ul>
    <code>
    define &lt;name&gt; YAMAHA_BD &lt;ip-address&gt; [&lt;status_interval&gt;]
    <br><br>
    define &lt;name&gt; YAMAHA_BD &lt;ip-address&gt; [&lt;off_status_interval&gt;] [&lt;on_status_interval&gt;]
    </code>
    <br><br>

    This module controls Blu-Ray players from Yamaha via network connection. You are able
    to switch your player on and off, query it's power state,
    control the playback, open and close the tray and send all remote control commands.<br><br>
    Defining a YAMAHA_BD device will schedule an internal task (interval can be set
    with optional parameter &lt;status_interval&gt; in seconds, if not set, the value is 30
    seconds), which periodically reads the status of the player (power state, current disc, tray status,...)
    and triggers notify/filelog commands.
    <br><br>
    Different status update intervals depending on the power state can be given also. 
    If two intervals are given to the define statement, the first interval statement represents the status update 
    interval in seconds in case the device is off, absent or any other non-normal state. The second 
    interval statement is used when the device is on.
   
    Example:<br><br>
    <ul><code>
       define BD_Player YAMAHA_BD 192.168.0.10
       <br><br>
       # With custom status interval of 60 seconds<br>
       define BD_Player YAMAHA_BD 192.168.0.10 60 
       <br><br>
       # With custom "off"-interval of 60 seconds and "on"-interval of 10 seconds<br>
       define BD_Player YAMAHA_BD 192.168.0.10 60 10
    </code></ul>
   
  </ul>
  <br><br>
  <a name="YAMAHA_BDset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>
    Currently, the following commands are defined.
<br><br>
<ul>
<li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device</li>
<li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; shuts down the device </li>
<li><b>tray</b> open,close &nbsp;&nbsp;-&nbsp;&nbsp; open or close the disc tray</li>
<li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device</li>
<li><b>remoteControl</b> up,down,... &nbsp;&nbsp;-&nbsp;&nbsp; sends remote control commands as listed in the following chapter</li>
</ul><br>
<u>Playback control commands</u>
<ul>
<li><b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; start playing the current media</li>
<li><b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; pause the current media playback</li>
<li><b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; stop the current media playback</li>
<li><b>skip</b> forward,reverse &nbsp;&nbsp;-&nbsp;&nbsp; skip the current track or chapter</li>
<li><b>fast</b> forward,reverse &nbsp;&nbsp;-&nbsp;&nbsp; fast forward or reverse playback</li>
<li><b>slow</b> forward,reverse &nbsp;&nbsp;-&nbsp;&nbsp; slow forward or reverse playback</li>


</ul>
</ul><br><br>
<u>Remote control</u><br><br>
<ul>
    The following commands are available:<br><br>

    <u>Number Buttons (0-9):</u><br><br>
    <ul><code>
    remoteControl 0<br>
    remoteControl 1<br>
    remoteControl 2<br>
    ...<br>
    remoteControl 9<br>
    </code></ul><br><br>
    
    <u>Cursor Selection:</u><br><br>
    <ul><code>
    remoteControl up<br>
    remoteControl down<br>
    remoteControl left<br>
    remoteControl right<br>
    remoteControl enter<br>
    remoteControl return<br>
    </code></ul><br><br>

    <u>Menu Selection:</u><br><br>
    <ul><code>
    remoteControl OSDonScreen<br>
    remoteControl OSDstatus<br>
    remoteControl popupMenu<br>
    remoteControl topMenu<br>
    remoteControl setup<br>
    remoteControl home<br>
    remoteControl clear<br>
    </code></ul><br><br>
    
    <u>Color Buttons:</u><br><br>
    <ul><code>
    remoteControl red<br>
    remoteControl green<br>
    remoteControl yellow<br>
    remoteControl blue<br>
    </code></ul><br><br>

    The button names are the same as on your remote control.<br><br>
  
  </ul>

  <a name="YAMAHA_BDget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt;</code>
    <br><br>
    Currently, the get command only returns the reading values. For a specific list of possible values, see section "Generated Readings/Events".
	<br><br>
  </ul>
  <a name="YAMAHA_BDattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a name="disable">disable</a></li>
	Optional attribute to disable the internal cyclic status update of the player. Manual status updates via statusRequest command is still possible.
	<br><br>
	Possible values: 0 => perform cyclic status update, 1 => don't perform cyclic status updates.<br><br>
	<li><a name="request-timeout">request-timeout</a></li>
	Optional attribute change the response timeout in seconds for all queries to the player.
	<br><br>
	Possible values: 1-5 seconds. Default value is 4 seconds.<br><br>
  </ul>
  <b>Generated Readings/Events:</b><br>
  <ul>
  <li><b>input</b> - The current playback source (can be "DISC", "USB" or "Network")</li>
  <li><b>discType</b> - The current type of disc, which is inserted (e.g. "No Disc", "CD", "DVD", "BD",...)</li>
  <li><b>error</b> - indicates an hardware error of the player (can be "none", "fan error" or "usb overcurrent")</li>
  <li><b>power</b> - Reports the power status of the player or zone (can be "on" or "off")</li>
  <li><b>presence</b> - Reports the presence status of the player or zone (can be "absent" or "present"). In case of an absent device, it cannot be controlled via FHEM anymore.</li>
  <li><b>trayStatus</b> - The disc tray status (can be "open" or "close")</li>
  <li><b>state</b> - Reports the current power state and an absence of the device (can be "on", "off" or "absent")</li>
  <br><br><u>Input dependent Readings/Events:</u><br>
  <li><b>currentChapter</b> - Number of the current DVD/BD Chapter (only at DVD/BD's)</li>
  <li><b>currentMedia</b> - Name of the current file (only at USB)</li>
  <li><b>playTimeCurrent</b> - current timecode of played media</li>
  <li><b>playTimeTotal</b> - the total time of the current movie (only at DVD/BD's)</li>
  <li><b>playStatus</b> - indicates if the player plays media or not (can be "play", "pause", "stop", "fast fwd", "fast rev", "slow fwd", "slow rev")</li>
  </ul>
<br>
  <b>Implementator's note</b><br>
  <ul>
  <li>Some older models (e.g. BD-S671) cannot be controlled over networked by delivery. A <u><b>firmware update is neccessary</b></u> to control theese models via FHEM</li> 
   <li>The module is only usable if you activate "Network Control" on your player. Otherwise it is not possible to communicate with the player.</li>
  </ul>
  <br>
</ul>


=end html
=begin html_DE

<a name="YAMAHA_BD"></a>
<h3>YAMAHA_BD</h3>
<ul>

  <a name="YAMAHA_BDdefine"></a>
  <b>Definition</b>
  <ul>
    <code>define &lt;name&gt; YAMAHA_BD &lt;IP-Addresse&gt; [&lt;Status_Interval&gt;]
    <br><br>
    define &lt;name&gt; YAMAHA_BD &lt;IP-Addresse&gt; [&lt;Off_Interval&gt;] [&lt;On_Interval&gt;]
    </code>
    <br><br>

    Dieses Modul steuert Blu-Ray Player des Herstellers Yamaha &uuml;ber die Netzwerkschnittstelle.
    Es bietet die M&ouml;glichkeit den Player an-/auszuschalten, die Schublade zu &ouml;ffnen und schlie&szlig;en,
    die Wiedergabe beeinflussen, s&auml;mtliche Fernbedieungs-Befehle zu senden, sowie den aktuellen Status abzufragen.
    <br><br>
    Bei der Definition eines YAMAHA_BD-Moduls wird eine interne Routine in Gang gesetzt, welche regelm&auml;&szlig;ig 
    (einstellbar durch den optionalen Parameter <code>&lt;Status_Interval&gt;</code>; falls nicht gesetzt ist der Standardwert 30 Sekunden)
    den Status des Players abfragt und entsprechende Notify-/FileLog-Definitionen triggert.
    <br><br>
    Sofern 2 Interval-Argumente &uuml;bergeben werden, wird der erste Parameter <code>&lt;Off_Interval&gt;</code> genutzt
    sofern der Player ausgeschaltet oder nicht erreichbar ist. Der zweiter Parameter <code>&lt;On_Interval&gt;</code> 
    wird verwendet, sofern der Player eingeschaltet ist. 
    <br><br>
    Beispiel:<br><br>
    <ul><code>
       define BD_Player YAMAHA_BD 192.168.0.10
       <br><br>
       # Mit modifiziertem Status Interval (60 Sekunden)<br>
       define BD_Player YAMAHA_BD 192.168.0.10 60
       <br><br>
       # Mit gesetztem "Off"-Interval (60 Sekunden) und "On"-Interval (10 Sekunden)<br>
       define BD_Player YAMAHA_BD 192.168.0.10 60 10
    </code></ul><br><br>
  </ul>

  <a name="YAMAHA_BDset"></a>
  <b>Set-Kommandos </b>
  <ul>
    <code>set &lt;Name&gt; &lt;Kommando&gt; [&lt;Parameter&gt;]</code>
    <br><br>
    Aktuell werden folgende Kommandos unterst&uuml;tzt.
<br><br>
<ul>
<li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; schaltet den Player ein</li>
<li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; schaltet den Player aus </li>
<li><b>tray</b> open,close &nbsp;&nbsp;-&nbsp;&nbsp; &ouml;ffnet oder schlie&szlig;t die Schublade</li>
<li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; fragt den aktuellen Status ab</li>
<li><b>remoteControl</b> up,down,... &nbsp;&nbsp;-&nbsp;&nbsp; sendet Fernbedienungsbefehle wie im folgenden Kapitel beschrieben.</li>
</ul><br>
<u>Wiedergabespezifische Kommandos</u>
<ul>
<li><b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; startet die Wiedergabe des aktuellen Mediums</li>
<li><b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; pausiert die Wiedergabe</li>
<li><b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; stoppt die Wiedergabe</li>
<li><b>skip</b> forward,reverse &nbsp;&nbsp;-&nbsp;&nbsp; &uuml;berspringt das aktuelle Kapitel oder den aktuellen Titel</li>
<li><b>fast</b> forward,reverse &nbsp;&nbsp;-&nbsp;&nbsp; schneller Vor- oder R&uuml;cklauf</li>
<li><b>slow</b> forward,reverse &nbsp;&nbsp;-&nbsp;&nbsp; langsamer Vor- oder R&uuml;cklauf</li>


</ul>
<br><br>
</ul>
<u>Fernbedienung</u><br><br>
<ul>
    Es stehen folgende Befehle zur Verf&uuml;gung:<br><br>

    <u>Zahlen Tasten (0-9):</u><br><br>
    <ul><code>
    remoteControl 0<br>
    remoteControl 1<br>
    remoteControl 2<br>
    ...<br>
    remoteControl 9<br>
    </code></ul><br><br>
    
    <u>Cursor Steuerung:</u><br><br>
    <ul><code>
    remoteControl up<br>
    remoteControl down<br>
    remoteControl left<br>
    remoteControl right<br>
    remoteControl enter<br>
    remoteControl return<br>
    </code></ul><br><br>

    <u>Men&uuml; Auswahl:</u><br><br>
    <ul><code>
    remoteControl OSDonScreen<br>
    remoteControl OSDstatus<br>
    remoteControl popupMenu<br>
    remoteControl topMenu<br>
    remoteControl setup<br>
    remoteControl home<br>
    remoteControl clear<br>
    </code></ul><br><br>
    
    <u>Farbtasten:</u><br><br>
    <ul><code>
    remoteControl red<br>
    remoteControl green<br>
    remoteControl yellow<br>
    remoteControl blue<br>
    </code></ul><br><br>
    Die Befehlsnamen entsprechen den Tasten auf der Fernbedienung.<br><br>
  </ul>

  <a name="YAMAHA_BDget"></a>
  <b>Get-Kommandos</b>
  <ul>
    <code>get &lt;Name&gt; &lt;Readingname&gt;</code>
    <br><br>
    Aktuell stehen via GET lediglich die Werte der Readings zur Verf&uuml;gung. Eine genaue Auflistung aller m&ouml;glichen Readings folgen unter "Generierte Readings/Events".
  </ul>
  <br><br>
  <a name="YAMAHA_BDattr"></a>
  <b>Attribute</b>
  <ul>
  
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a name="disable">disable</a></li>
	Optionales Attribut zur Deaktivierung des zyklischen Status-Updates. Ein manuelles Update via statusRequest-Befehl ist dennoch m&ouml;glich.
	<br><br>
	M&ouml;gliche Werte: 0 => zyklische Status-Updates, 1 => keine zyklischen Status-Updates.<br><br>
	<li><a name="request-timeout">request-timeout</a></li>
	Optionales Attribut. Maximale Dauer einer Anfrage in Sekunden zum Player.
	<br><br>
	M&ouml;gliche Werte: 1-5 Sekunden. Standartwert ist 4 Sekunden<br><br>
  </ul>
  <b>Generierte Readings/Events:</b><br>
  <ul>
  <li><b>input</b> - Die aktuelle Wiedergabequelle ("DISC", "USB" oder "Network")</li>
  <li><b>discType</b> - Die Art der eingelegten Disc (z.B "No Disc" => keine Disc eingelegt, "CD", "DVD", "BD",...)</li>
  <li><b>error</b> - zeigt an, ob ein interner Fehler im Player vorliegt ("none" => kein Fehler, "fan error" => L&uuml;fterdefekt, "usb overcurrent" => USB Spannungsschutz)</li>
  <li><b>power</b> - Der aktuelle Betriebsstatus ("on" => an, "off" => aus)</li>
  <li><b>presence</b> - Die aktuelle Empfangsbereitschaft ("present" => empfangsbereit, "absent" => nicht empfangsbereit, z.B. Stromausfall)</li>
  <li><b>trayStatus</b> - Der Status der Schublade("open" => ge&ouml;ffnet, "close" => geschlossen)</li>
  <li><b>state</b> - Der aktuelle Schaltzustand (power-Reading) oder die Abwesenheit des Ger&auml;tes (m&ouml;gliche Werte: "on", "off" oder "absent")</li>
  <br><br><u>Quellenabh&auml;ngige Readings/Events:</u><br>
  <li><b>currentChapter</b> - Das aktuelle Kapitel eines DVD- oder Blu-Ray-Films</li>
  <li><b>currentMedia</b> -  Der Name der aktuell wiedergebenden Datei (Nur bei der Wiedergabe &uuml;ber USB)</li>
  <li><b>playTimeCurrent</b> - Der aktuelle Timecode an dem sich die Wiedergabe momentan befindet.</li>
  <li><b>playTimeTotal</b> - Die komplette Spieldauer des aktuellen Films (Nur bei der Wiedergabe von DVD/BD's)</li>
  <li><b>playStatus</b> - Wiedergabestatus des aktuellen Mediums</li>
  </ul>
<br>
  <b>Hinweise des Autors</b>
  <ul>
   <li>Einige &auml;ltere Player-Modelle (z.B. BD-S671) k&ouml;nnen im Auslieferungszustand nicht via Netzwerk gesteuert werden. Um eine Steuerung via FHEM zu erm&ouml;glichen ist ein <u><b>Firmware-Update notwending</b></u>!</li> 
    <li>Dieses Modul ist nur nutzbar, wenn die Option "Netzwerksteuerung" am Player aktiviert ist. Ansonsten ist die Steuerung nicht m&ouml;glich.</li>
  </ul>
  <br>
</ul>
=end html_DE

=cut

