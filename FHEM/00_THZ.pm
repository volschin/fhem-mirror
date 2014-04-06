##############################################
# 00_THZ
# by immi 04/2014
# v. 0.082
# this code is based on the hard work of Robert; I just tried to port it
# http://robert.penz.name/heat-pump-lwz/
# http://heatpumpmonitor.penz.name/heatpumpmonitorwiki/
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
########################################################################################


package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use feature ":5.10";
use SetExtensions;

sub THZ_Read($);
sub THZ_ReadAnswer($);
sub THZ_Ready($);
sub THZ_Write($$);
sub THZ_Parse($);
sub THZ_Parse1($);
sub THZ_checksum($);
sub THZ_replacebytes($$$);
sub THZ_decode($);
sub THZ_overwritechecksum($);
sub THZ_encodecommand($$);
sub hex2int($);
sub quaters2time($);
sub time2quaters($);
sub THZ_debugread($);
sub THZ_GetRefresh($);
sub THZ_Refresh_all_gets($);



########################################################################################
#
# %sets - all supported protocols are listed
# 
########################################################################################

my %sets = (
	"p01RoomTempDayHC1"		=> {cmd2=>"0B0005", argMin => "13", argMax => "28"  },   
	"p02RoomTempNightHC1"		=> {cmd2=>"0B0008", argMin => "13", argMax => "28"  },
	"p03RoomTempStandbyHC1"		=> {cmd2=>"0B013D", argMin => "13", argMax => "28"  },
	"p01RoomTempDayHC2"		=> {cmd2=>"0C0005", argMin => "13", argMax => "28"  },
	"p02RoomTempNightHC2"		=> {cmd2=>"0C0008", argMin => "13", argMax => "28"  },
	"p03RoomTempStandbyHC2"		=> {cmd2=>"0C013D", argMin => "13", argMax => "28"  },
	"p04DHWsetDay"			=> {cmd2=>"0A0013", argMin => "13", argMax => "46"  },
	"p05DHWsetNight"		=> {cmd2=>"0A05BF", argMin => "13", argMax => "46"  },
	"p07FanStageDay"		=> {cmd2=>"0A056C", argMin =>  "0", argMax =>  "3"  },
	"p08FanStageNight"		=> {cmd2=>"0A056D", argMin =>  "0", argMax =>  "3"  },
	"p09FanStageStandby"		=> {cmd2=>"0A056F", argMin =>  "0", argMax =>  "3"  },
	"p99FanStageParty"		=> {cmd2=>"0A0570", argMin =>  "0", argMax =>  "3"  },
	"p75passiveCooling"		=> {cmd2=>"0A0575", argMin =>  "0", argMax =>  "2"  },
	"p37fanstage1-Airflow-inlet"	=> {cmd2=>"0A0576", argMin =>  "50", argMax =>  "300"},		#zuluft 
	"p38fanstage2-Airflow-inlet"	=> {cmd2=>"0A0577", argMin =>  "50", argMax =>  "300" },	#zuluft 
	"p39fanstage3-Airflow-inlet"	=> {cmd2=>"0A0578", argMin =>  "50", argMax =>  "300" },	#zuluft 
	"p40fanstage1-Airflow-outlet"	=> {cmd2=>"0A0579", argMin =>  "50", argMax =>  "300" },	#abluft extrated
	"p41fanstage2-Airflow-outlet"	=> {cmd2=>"0A057A", argMin =>  "50", argMax =>  "300" },	#abluft extrated
	"p42fanstage3-Airflow-outlet"	=> {cmd2=>"0A057B", argMin =>  "50", argMax =>  "300" },	#abluft extrated
	"p49SummerModeTemp"		=> {cmd2=>"0A0116", argMin =>  "11", argMax =>  "24" },		#threshold for summer mode !! 
	"p50SummerModeHysteresis"	=> {cmd2=>"0A05A2", argMin =>  "0.5", argMax =>  "5" },		#Hysteresis for summer mode !! 
	"holidayBegin_day"		=> {cmd2=>"0A011B", argMin =>  "1", argMax =>  "31"  }, 
	"holidayBegin_month"		=> {cmd2=>"0A011C", argMin =>  "1", argMax =>  "12"  },
	"holidayBegin_year"		=> {cmd2=>"0A011D", argMin =>  "12", argMax => "20"  },
	"holidayBegin-time"		=> {cmd2=>"0A05D3", argMin =>  "00:00", argMax =>  "23:59"},
	"holidayEnd_day"		=> {cmd2=>"0A011E", argMin =>  "1", argMax =>  "31"  }, 
	"holidayEnd_month"		=> {cmd2=>"0A011F", argMin =>  "1", argMax =>  "12"  },
	"holidayEnd_year"		=> {cmd2=>"0A0120", argMin =>  "12", argMax => "20"  }, 
	"holidayEnd-time"		=> {cmd2=>"0A05D4", argMin =>  "00:00", argMax =>  "23:59"}, # the answer look like  0A05D4-0D0A05D40029 for year 41 which is 10:15
	#"party-time"			=> {cmd2=>"0A05D1", argMin =>  "00:00", argMax =>  "23:59"}, # value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
	"programHC1_Mo_0"		=> {cmd2=>"0B1410", argMin =>  "00:00", argMax =>  "23:59"},  #1 is monday 0 is first prog; start and end; value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
	"programHC1_Mo_1"		=> {cmd2=>"0B1411", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Mo_2"		=> {cmd2=>"0B1412", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Tu_0"		=> {cmd2=>"0B1420", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Tu_1"		=> {cmd2=>"0B1421", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Tu_2"		=> {cmd2=>"0B1422", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_We_0"		=> {cmd2=>"0B1430", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_We_1"		=> {cmd2=>"0B1431", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_We_2"		=> {cmd2=>"0B1432", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Th_0"		=> {cmd2=>"0B1440", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Th_1"		=> {cmd2=>"0B1441", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Th_2"		=> {cmd2=>"0B1442", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Fr_0"		=> {cmd2=>"0B1450", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Fr_1"		=> {cmd2=>"0B1451", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Fr_2"		=> {cmd2=>"0B1452", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Sa_0"		=> {cmd2=>"0B1460", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Sa_1"		=> {cmd2=>"0B1461", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Sa_2"		=> {cmd2=>"0B1462", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_So_0"		=> {cmd2=>"0B1470", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_So_1"		=> {cmd2=>"0B1471", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_So_2"		=> {cmd2=>"0B1472", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Mo-Fr_0"		=> {cmd2=>"0B1480", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Mo-Fr_1"		=> {cmd2=>"0B1481", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Mo-Fr_3"		=> {cmd2=>"0B1482", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Sa-So_0"		=> {cmd2=>"0B1490", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Sa-So_1"		=> {cmd2=>"0B1491", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Sa-So_3"		=> {cmd2=>"0B1492", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Mo-So_0"		=> {cmd2=>"0B14A0", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Mo-So_1"		=> {cmd2=>"0B14A1", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC1_Mo-So_3"		=> {cmd2=>"0B14A2", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Mo_0"		=> {cmd2=>"0C1510", argMin =>  "00:00", argMax =>  "23:59"},  #1 is monday 0 is first prog; start and end; value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
	"programHC2_Mo_1"		=> {cmd2=>"0C1511", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Mo_2"		=> {cmd2=>"0C1512", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Tu_0"		=> {cmd2=>"0C1520", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Tu_1"		=> {cmd2=>"0C1521", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Tu_2"		=> {cmd2=>"0C1522", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_We_0"		=> {cmd2=>"0C1530", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_We_1"		=> {cmd2=>"0C1531", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_We_2"		=> {cmd2=>"0C1532", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Th_0"		=> {cmd2=>"0C1540", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Th_1"		=> {cmd2=>"0C1541", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Th_2"		=> {cmd2=>"0C1542", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Fr_0"		=> {cmd2=>"0C1550", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Fr_1"		=> {cmd2=>"0C1551", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Fr_2"		=> {cmd2=>"0C1552", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Sa_0"		=> {cmd2=>"0C1560", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Sa_1"		=> {cmd2=>"0C1561", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Sa_2"		=> {cmd2=>"0C1562", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_So_0"		=> {cmd2=>"0C1570", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_So_1"		=> {cmd2=>"0C1571", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_So_2"		=> {cmd2=>"0C1572", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Mo-Fr_0"		=> {cmd2=>"0C1580", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Mo-Fr_1"		=> {cmd2=>"0C1581", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Mo-Fr_3"		=> {cmd2=>"0C1582", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Sa-So_0"		=> {cmd2=>"0C1590", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Sa-So_1"		=> {cmd2=>"0C1591", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Sa-So_3"		=> {cmd2=>"0C1592", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Mo-So_0"		=> {cmd2=>"0C15A0", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Mo-So_1"		=> {cmd2=>"0C15A1", argMin =>  "00:00", argMax =>  "23:59"},
	"programHC2_Mo-So_3"		=> {cmd2=>"0C15A2", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Mo_0"		=> {cmd2=>"0A1710", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Mo_1"		=> {cmd2=>"0A1711", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Mo_2"		=> {cmd2=>"0A1712", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Tu_0"		=> {cmd2=>"0A1720", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Tu_1"		=> {cmd2=>"0A1721", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Tu_2"		=> {cmd2=>"0A1722", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_We_0"		=> {cmd2=>"0A1730", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_We_1"		=> {cmd2=>"0A1731", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_We_2"		=> {cmd2=>"0A1732", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Th_0"		=> {cmd2=>"0A1740", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Th_1"		=> {cmd2=>"0A1741", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Th_2"		=> {cmd2=>"0A1742", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Fr_0"		=> {cmd2=>"0A1750", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Fr_1"		=> {cmd2=>"0A1751", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Fr_2"		=> {cmd2=>"0A1752", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Sa_0"		=> {cmd2=>"0A1760", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Sa_1"		=> {cmd2=>"0A1761", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Sa_2"		=> {cmd2=>"0A1762", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_So_0"		=> {cmd2=>"0A1770", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_So_1"		=> {cmd2=>"0A1771", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_So_2"		=> {cmd2=>"0A1772", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Mo-Fr_0"		=> {cmd2=>"0A1780", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Mo-Fr_1"		=> {cmd2=>"0A1781", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Mo-Fr_2"		=> {cmd2=>"0A1782", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Sa-So_0"		=> {cmd2=>"0A1790", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Sa-So_1"		=> {cmd2=>"0A1791", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Sa-So_2"		=> {cmd2=>"0A1792", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Mo-So_0"		=> {cmd2=>"0A17A0", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Mo-So_1"		=> {cmd2=>"0A17A1", argMin =>  "00:00", argMax =>  "23:59"},
	"programDHW_Mo-So_2"		=> {cmd2=>"0A17A2", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Mo_0"		=> {cmd2=>"0A1D10", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Mo_1"		=> {cmd2=>"0A1D11", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Mo_2"		=> {cmd2=>"0A1D12", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Tu_0"		=> {cmd2=>"0A1D20", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Tu_1"		=> {cmd2=>"0A1D21", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Tu_2"		=> {cmd2=>"0A1D22", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_We_0"		=> {cmd2=>"0A1D30", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_We_1"		=> {cmd2=>"0A1D31", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_We_2"		=> {cmd2=>"0A1D32", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Th_0"		=> {cmd2=>"0A1D40", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Th_1"		=> {cmd2=>"0A1D41", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Th_2"		=> {cmd2=>"0A1D42", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Fr_0"		=> {cmd2=>"0A1D50", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Fr_1"		=> {cmd2=>"0A1D51", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Fr_2"		=> {cmd2=>"0A1D52", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Sa_0"		=> {cmd2=>"0A1D60", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Sa_1"		=> {cmd2=>"0A1D61", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Sa_2"		=> {cmd2=>"0A1D62", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_So_0"		=> {cmd2=>"0A1D70", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_So_1"		=> {cmd2=>"0A1D71", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_So_2"		=> {cmd2=>"0A1D72", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Mo-Fr_0"		=> {cmd2=>"0A1D80", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Mo-Fr_1"		=> {cmd2=>"0A1D81", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Mo-Fr_2"		=> {cmd2=>"0A1D82", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Sa-So_0"		=> {cmd2=>"0A1D90", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Sa-So_1"		=> {cmd2=>"0A1D91", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Sa-So_2"		=> {cmd2=>"0A1D92", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Mo-So_0"		=> {cmd2=>"0A1DA0", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Mo-So_1"		=> {cmd2=>"0A1DA1", argMin =>  "00:00", argMax =>  "23:59"},
	"programFan_Mo-So_2"		=> {cmd2=>"0A1DA2", argMin =>  "00:00", argMax =>  "23:59"}
  );




########################################################################################
#
# %gets - all supported protocols are listed without header and footer
#
########################################################################################

my %getsonly = (
#	"hallo"       			=> { },
#	"debug_read_raw_register_slow"	=> { },
	"Status_Sol_16"			=> {cmd2=>"16"},
	"Status_DHW_F3"			=> {cmd2=>"F3"},
	"Status_HC1_F4"			=> {cmd2=>"F4"},
	"Status_HC2_F5"			=> {cmd2=>"F5"},
	"history"			=> {cmd2=>"09"},
	"last10errors"			=> {cmd2=>"D1"},
        "allFB"     			=> {cmd2=>"FB"},
        "timedate" 			=> {cmd2=>"FC"},
        "firmware" 			=> {cmd2=>"FD"},
	"party-time"			=> {cmd2=>"0A05D1"} # value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
  );

my %gets=(%getsonly, %sets);

########################################################################################
#
# THZ_Initialize($)
# 
# Parameter hash
#
########################################################################################
sub THZ_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "THZ_Read";
  $hash->{WriteFn} = "THZ_Write";
  $hash->{ReadyFn} = "THZ_Ready";
  
# Normal devices
  $hash->{DefFn}   = "THZ_Define";
  $hash->{UndefFn} = "THZ_Undef";
  $hash->{GetFn}   = "THZ_Get";
  $hash->{SetFn}   = "THZ_Set";
  $hash->{AttrList}= "IODev do_not_notify:1,0  ignore:0,1 dummy:1,0 showtime:1,0 loglevel:0,1,2,3,4,5,6 "
		    ."interval_allFB:0,60,120,180,300,600,3600,7200,43200,86400 "
		    ."interval_history:0,3600,7200,28800,43200,86400 "
		    ."interval_last10errors:0,3600,7200,28800,43200,86400 "
		    . $readingFnAttributes;
}


########################################################################################
#
# THZ_define
#
# Parameter hash and configuration
#
########################################################################################
sub THZ_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $a[0];

  return "wrong syntax. Correct is: define <name> THZ ".
  				"{devicename[\@baudrate]|ip:port}"
  				 if(@a != 3);
  				
  DevIo_CloseDev($hash);
  my $dev  = $a[2];

  if($dev eq "none") {
    Log 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  
  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "THZ_Refresh_all_gets");
  return $ret;
}

########################################################################################
#
# THZ_Refresh_all_gets - Called once refreshes current reading for all gets and initializes the regular interval calls
#
# Parameter $hash
# 
########################################################################################
sub THZ_Refresh_all_gets($) {
  my ($hash) = @_;
  RemoveInternalTimer($hash);
  my $timedelay= 5;
  foreach  my $cmdhash  (keys %gets) {
    my %par = ( command => $cmdhash, hash => $hash );
    RemoveInternalTimer(\%par);
    InternalTimer(gettimeofday() + ($timedelay++) , "THZ_GetRefresh", \%par, 0); 
  }  #refresh all registers; the register with interval_command ne 0 will keep on refreshing
}


########################################################################################
#
# THZ_GetRefresh - Called in regular intervals to obtain current reading
#
# Parameter (hash => $hash, command => "allFB" )
# it get the intervall directly from a attribute; the register with interval_command ne 0 will keep on refreshing
########################################################################################
sub THZ_GetRefresh($) {
	my ($par)=@_;
	my $hash=$par->{hash};
	my $command=$par->{command};
	my $interval = AttrVal($hash->{NAME}, ("interval_".$command), 0);
	my $replyc = "";
	if (!($hash->{STATE} eq "disconnected")) {
	  if ($interval) {
			  $interval = 60 if ($interval < 60); #do not allow intervall <60 sec 
			  InternalTimer(gettimeofday()+ $interval, "THZ_GetRefresh", $par, 1) ;
	  }		
	  $replyc = THZ_Get($hash, $hash->{NAME}, $command);
	}
	return ($replyc);
}



#####################################
# THZ_Write -- simple write
# Parameter:  hash and message HEX
#
########################################################################################
sub THZ_Write($$) {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $bstring;
    $bstring = $msg;

  Log $ll5, "$hash->{NAME} sending $bstring";

  DevIo_SimpleWrite($hash, $bstring, 1);
}


#####################################
# sub THZ_Read($)
# called from the global loop, when the select for hash reports data
# used just for testing the interface
########################################################################################
sub THZ_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));

  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $ll2 = GetLogLevel($name,2);

  my $data = $hash->{PARTIAL} . uc(unpack('H*', $buf));
  
Log $ll5, "$name/RAW: $data";
Log $ll2, "$name/RAW: $data";
  
}



#####################################
#
# THZ_Ready($) - Cchecks the status
#
# Parameter hash
#
########################################################################################
sub THZ_Ready($)
{
  my ($hash) = @_;
  if($hash->{STATE} eq "disconnected")
  {
  select(undef, undef, undef, 0.1); #equivalent to sleep 100ms
  return DevIo_OpenDev($hash, 1, "THZ_Refresh_all_gets")
  }	
		
  
    # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  if($po) {
    my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
    return ($InBytes>0);
  }
  
}





#####################################
#
# THZ_Set - provides a method for setting the heatpump
#
# Parameters: hash and command to be sent to the interface
#
########################################################################################
sub THZ_Set($@){
  my ($hash, @a) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $ll2 = GetLogLevel($name,2);

  return "\"set $name\" needs at least two parameters: <device-parameter> and <value-to-be-modified>" if(@a < 2);
  my $cmd = $a[1];
  my $arg = $a[2];
  my $arg1 = "00:00";
  my ($err, $msg) =("", " ");
  my $cmdhash = $sets{$cmd};
  return "Unknown argument $cmd, choose one of " . join(" ", sort keys %sets) if(!defined($cmdhash));
  return "\"set $name $cmd\" needs at least one further argument: <value-to-be-modified>" if(!defined($arg));
  my $cmdHex2 = $cmdhash->{cmd2};
  my $argMax = $cmdhash->{argMax};
  my $argMin = $cmdhash->{argMin};
  if  ((substr($cmdHex2,0,6) eq "0A05D1") or (substr($cmdHex2,2,2) eq "1D") or (substr($cmdHex2,2,2)  eq "17") or (substr($cmdHex2,2,2) eq "15") or (substr($cmdHex2,2,2)  eq "14")) {
  ($arg, $arg1)=split('--', $arg);
  if (($arg ne "n.a.") and ($arg1 ne "n.a.")) {
    return "Argument does not match the allowed inerval Min $argMin ...... Max $argMax " if(($arg1 gt $argMax) or ($arg1 lt $argMin));
    return "Argument does not match the allowed inerval Min $argMin ...... Max $argMax " if(($arg gt $argMax) or ($arg lt $argMin));
    }
  }
  else {
  return "Argument does not match the allowed inerval Min $argMin ...... Max $argMax " if(($arg > $argMax) or ($arg < $argMin));
  }
  
  if 	((substr($cmdHex2,0,6) eq "0A0116") or (substr($cmdHex2,0,6) eq "0A05A2"))	 {$arg=$arg*10} #summermode
  elsif (substr($cmdHex2,0,4) eq "0A01")  {$arg=$arg*256}		        	# shift 2 times -- the answer look like  0A0120-3A0A01200E00  for year 14
  elsif  ((substr($cmdHex2,2,2) eq "1D") or (substr($cmdHex2,2,2)  eq "17") or (substr($cmdHex2,2,2) eq "15") or (substr($cmdHex2,2,2)  eq "14")) 	{$arg= time2quaters($arg) *256   + time2quaters($arg1)} # BeginTime-endtime, in the register is represented  begintime endtime
  #programFan_ (1D)  funziona;
  elsif  (substr($cmdHex2,0,6) eq "0A05D1") 		  			{$arg= time2quaters($arg1) *256 + time2quaters($arg)} # PartyBeginTime-endtime, in the register is represented endtime begintime
  #partytime (0A05D1) non funziona; 
  elsif  ((substr($cmdHex2,0,6) eq "0A05D3") or (substr($cmdHex2,0,6) eq "0A05D4")) 	{$arg= time2quaters($arg)} # holidayBeginTime-endtime
  elsif  ((substr($cmdHex2,0,5) eq "0A056") or (substr($cmdHex2,0,5) eq "0A057"))	{ } 				# fann speed: do not multiply
  else 			             {$arg=$arg*10} 
  #return ($arg);  
  THZ_Write($hash,  "02"); 			# STX start of text
  ($err, $msg) = THZ_ReadAnswer($hash);		#Expectedanswer1    is  "10"  DLE data link escape
  my $msgtmp= $msg;
  if ($msg eq "10") {
    $cmdHex2=THZ_encodecommand(($cmdHex2 . sprintf("%04X", $arg)),"set");
    THZ_Write($hash,  $cmdHex2); 		# send request   SOH start of heading -- Null 	-- ?? -- DLE data link escape -- EOT End of Text
    ($err, $msg) = THZ_ReadAnswer($hash);	#Expectedanswer     is "10",		DLE data link escape 
     }
   $msgtmp=  $msgtmp  ."\n" ."set--" . $cmdHex2  ."\n" . $msg; 
   if ($msg eq "10") {
      ($err, $msg) = THZ_ReadAnswer($hash);	#Expectedanswer  is "02"  -- STX start of text
     THZ_Write($hash,  "10"); 		    	# DLE data link escape  // ack datatranfer      
     ($err, $msg) = THZ_ReadAnswer($hash);	# Expectedanswer3 // read from the heatpump
      THZ_Write($hash,  "10");
     }
   elsif ($msg eq "1002") {
     THZ_Write($hash,  "10"); 		    	# DLE data link escape  // ack datatranfer      
     ($err, $msg) = THZ_ReadAnswer($hash);	# Expectedanswer3 // read from the heatpump
      THZ_Write($hash,  "10");
     }
   $msgtmp= $msgtmp ."\n" . $msg; 
   if (defined($err))  {return ($cmdHex2 . "-". $msg ."--" . $err);}
   else {
	sleep 1;
	$msg=THZ_Get($hash, $name, $cmd);
	$msgtmp= $msgtmp ."\n" . $msg;
	return ($msg);
	} 
}




#####################################
#
# THZ_Get - provides a method for polling the heatpump
#
# Parameters: hash and command to be sent to the interface
#
########################################################################################
sub THZ_Get($@){
  my ($hash, @a) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $ll2 = GetLogLevel($name,2);

  return "\"get $name\" needs one parameter" if(@a != 2);
  my $cmd = $a[1];
  my ($err, $msg) =("", " ");

   if ($cmd eq "debug_read_raw_register_slow") {
    THZ_debugread($hash);
    return ("all raw registers read and saved");
    } 
  
  
  my $cmdhash = $gets{$cmd};
  return "Unknown argument $cmd, choose one of " .
        join(" ", sort keys %gets) if(!defined($cmdhash));

           
	            		
  THZ_Write($hash,  "02"); 			# STX start of text
  ($err, $msg) = THZ_ReadAnswer($hash);		#Expectedanswer1    is  "10"  DLE data link escape
  
  my $cmdHex2 = $cmdhash->{cmd2};
   if(defined($cmdHex2) and ($msg eq "10") ) {
    $cmdHex2=THZ_encodecommand($cmdHex2,"get");
      THZ_Write($hash,  $cmdHex2); 		# send request   SOH start of heading -- Null 	-- ?? -- DLE data link escape -- EOT End of Text
     ($err, $msg) = THZ_ReadAnswer($hash);	#Expectedanswer2     is "1002",		DLE data link escape -- STX start of text
    }
    
   if($msg eq "1002") {
     THZ_Write($hash,  "10"); 		    	# DLE data link escape  // ack datatranfer      
     ($err, $msg) = THZ_ReadAnswer($hash);	# Expectedanswer3 // read from the heatpump
     THZ_Write($hash,  "10");
     }
   
   if (defined($err))  {return ($msg ."\n" . $err);}
   else {   
	($err, $msg) = THZ_decode($msg); 	#clean up and remove footer and header
        if (defined($err))  {return ($msg ."\n" . $err);}
	else {   
        $msg = THZ_Parse($msg);
	my $activatetrigger =1;
	readingsSingleUpdate($hash, $cmd, $msg, $activatetrigger);
	return ($msg);
	}    
    }    
}




#####################################
#
# THZ_ReadAnswer- provides a method for simple read
#
# Parameter hash and command to be sent to the interface
#
########################################################################################
sub THZ_ReadAnswer($) {
  my ($hash) = @_;
#--next line added in order to slow-down 100ms
  select(undef, undef, undef, 0.1);
#--
  my $buf = DevIo_SimpleRead($hash);
  return ("InterfaceNotRespondig", "") if(!defined($buf));

  my $name = $hash->{NAME};
  
  my $data =  uc(unpack('H*', $buf));
  return (undef, $data);
}

 
#####################################
#
# THZ_checksum - takes a string, removes the footer (4bytes) and computes checksum (without checksum of course)
#
# Parameter string
# returns the checksum 2bytes
#
########################################################################################
sub THZ_checksum($) {
  my ($stringa) = @_;
  my $ml = length($stringa) - 4;
  my $checksum = 0;
  for(my $i = 0; $i < $ml; $i += 2) {
    ($checksum= $checksum + hex(substr($stringa, $i, 2))) if ($i != 4);
  }
  return (sprintf("%02X", ($checksum %256)));
}

#####################################
#
# hex2int - convert from hex to int with sign 16bit
#
########################################################################################
sub hex2int($) {
  my ($num) = @_;
 $num = unpack('s', pack('S', hex($num)));
  return $num;
}

####################################
#
# quaters2time - convert from hex to time; specific to the week programm registers
#
# parameter 1 byte representing number of quarter from midnight
# returns   string representing time
#
# example: value 1E is converted to decimal 30 and then to a time  7:30 
########################################################################################
sub quaters2time($) {
  my ($num) = @_;
  return("n.a.") if($num eq "80"); 
  my $quarters= hex($num) %4;
  my $hour= (hex($num) - $quarters)/4 ;
  my $time = sprintf("%02u", ($hour)) . ":" . sprintf("%02u", ($quarters*15));
  return $time;
}




####################################
#
# time2quarters - convert from time to quarters in hex; specific to the week programm registers
#
# parameter: string representing time
# returns: 1 byte representing number of quarter from midnight
#
# example: a time  7:30  is converted to decimal 30 
########################################################################################
sub time2quaters($) {
   my ($stringa) = @_;
   return("128") if($stringa eq "n.a."); 
 my ($h,$m) = split(":", $stringa);
  $m = 0 if(!$m);
  $h = 0 if(!$h);
  my $num = $h*4 +  int($m/15);
  return ($num);
}


####################################
#
# THZ_replacebytes - replaces bytes in string
#
# parameters: string, bytes to be searched, replacing bytes 
# retunrns changed string
#
########################################################################################
sub THZ_replacebytes($$$) {
  my ($stringa, $find, $replace) = @_; 
  my $leng_str = length($stringa);
  my $leng_find = length($find);
  my $new_stringa ="";
  for(my $i = 0; $i < $leng_str; $i += 2) {
    if (substr($stringa, $i, $leng_find) eq $find){
      $new_stringa=$new_stringa . $replace;
      if ($leng_find == 4) {$i += 2;}
      }
    else {$new_stringa=$new_stringa . substr($stringa, $i, 2);};
  }
  return ($new_stringa);
}


## usage THZ_overwritechecksum("0100XX". $cmd."1003"); not needed anymore
sub THZ_overwritechecksum($) {
  my ($stringa) = @_;
  my $checksumadded=substr($stringa,0,4) . THZ_checksum($stringa) . substr($stringa,6);
  return($checksumadded);
}


####################################
#
# THZ_encodecommand - creates a telegram for the heatpump with a given command 
#
# usage THZ_encodecommand($cmd,"get") or THZ_encodecommand($cmd,"set");
# parameter string, 
# retunrns encoded string
#
########################################################################################

sub THZ_encodecommand($$) {
  my ($cmd,$getorset) = @_;
  my $header = "0100";
  $header = "0180" if ($getorset eq "set");	# "set" and "get" have differnt header
  my $footer ="1003";
  my $checksumadded=THZ_checksum($header . "XX" . $cmd . $footer) . $cmd;
  # each 2B byte must be completed by byte 18
  # each 10 byte must be repeated (duplicated)
  my $find = "10";
  my $replace = "1010";
  #$checksumadded =~ s/$find/$replace/g; #problems in 1% of the cases, in middle of a byte
  $checksumadded=THZ_replacebytes($checksumadded, $find, $replace);
  $find = "2B";
  $replace = "2B18";
  #$checksumadded =~ s/$find/$replace/g;
  $checksumadded=THZ_replacebytes($checksumadded, $find, $replace);
  return($header. $checksumadded .$footer);
}





####################################
#
# THZ_decode -	decodes a telegram from the heatpump -- no parsing here
#
# Each response has the same structure as request - header (four bytes), optional data and footer:
#   Header: 01
#    Read/Write: 00 for Read (get) response, 80 for Write (set) response; when some error occured, then device stores error code here; actually, I know only meaning of error 03 = unknown command
#    Checksum: ? 1 byte - the same algorithm as for request
#    Command: ? 1 byte - should match Request.Command
#    Data: ? only when Read, length depends on data type
#    Footer: 10 03
#
########################################################################################

sub THZ_decode($) {
  my ($message_orig) = @_;
  #  raw data received from device have to be de-escaped before header evaluation and data use:
  # - each sequece 2B 18 must be replaced with single byte 2B
  # - each sequece 10 10 must be replaced with single byte 10
    my $find = "1010";
    my $replace = "10";
    $message_orig=THZ_replacebytes($message_orig, $find, $replace);
    $find = "2B18";
    $replace = "2B";
    $message_orig=THZ_replacebytes($message_orig, $find, $replace);
  #check header and if ok 0100, check checksum and return the decoded msg
  if ("0100" eq substr($message_orig,0,4)) {
    if (THZ_checksum($message_orig) eq substr($message_orig,4,2)) {
        $message_orig =~ /0100(.*)1003/; 
        my $message = $1;
        return (undef, $message)
    }
    else {return (THZ_checksum($message_orig) . "crc_error", $message_orig)}; }

  if ("0103" eq substr($message_orig,0,4)) { return (" command not known", $message_orig)}; 

  if ("0102" eq substr($message_orig,0,4)) {  return (" CRC error in request", $message_orig)}
  else {return (" new error code " , $message_orig);}; 
}

########################################################################################
#
# THZ_Parse -0A01
#
########################################################################################
	
sub THZ_Parse($) {
  my ($message) = @_;
  given (substr($message,2,2)) {
  when ("0A")    {
      if (substr($message,4,4) eq "0116")						{$message = hex2int(substr($message, 8,4))/10 ." °C" }
      elsif ((substr($message,4,3) eq "011")	or (substr($message,4,3) eq "012")) 	{$message = hex(substr($message, 8,2))} #holiday						      # the answer look like  0A0120-3A0A01200E00  for year 14
      elsif ((substr($message,4,2) eq "1D") or (substr($message,4,2) eq "17")) 	{$message = quaters2time(substr($message, 8,2)) ."--". quaters2time(substr($message, 10,2))}  #value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30  
      elsif (substr($message,4,4) eq "05D1") 				 	{$message = quaters2time(substr($message, 10,2)) ."--". quaters2time(substr($message, 8,2))}  #like above but before stop then start !!!!
      elsif  ((substr($message,4,4) eq "05D3") or (substr($message,4,4) eq "05D4"))   		{$message = quaters2time(substr($message, 10,2)) }  #value 1Ch 28dec is 7 
      elsif  ((substr($message,4,3) eq "056")  or (substr($message,4,4) eq "0570")  or (substr($message,4,4) eq "0575"))		{$message = hex(substr($message, 8,4))}
      elsif  (substr($message,4,3) eq "057")						{$message = hex(substr($message, 8,4)) ." m3/h" }
      elsif  (substr($message,4,4) eq "05A2")						{$message = hex(substr($message, 8,4))/10 ." K" }
      else 										{$message = hex2int(substr($message, 8,4))/10 ." °C" }
  }  
  when ("0B")    {							   #set parameter HC1
      if (substr($message,4,2) eq "14")  {$message = quaters2time(substr($message, 8,2)) ."--". quaters2time(substr($message, 10,2))}  #value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
      else 				 {$message = hex2int(substr($message, 8,4))/10 ." °C"  }
  }
  when ("0C")    {							   #set parameter HC2
      if (substr($message,4,2) eq "15")  {$message = quaters2time(substr($message, 8,2)) ."--". quaters2time(substr($message, 10,2))}  #value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
      else 				 {$message = hex2int(substr($message, 8,4))/10 ." °C"  }
  }
  
    when ("16")    {                     #all16 Solar
    $message =
		"collector_temp: " 		. hex2int(substr($message, 4,4))/10 . " " .
        	"dhw_temp: " 			. hex2int(substr($message, 8,4))/10 . " " .
        	"flow_temp: "			. hex2int(substr($message,12,4))/10 . " " .
        	"ed_sol_pump_temp: "		. hex2int(substr($message,16,4))/10 . " " .
        	"x20: "	 	 		. hex2int(substr($message,20,4))    . " " .
        	"x24: "				. hex2int(substr($message,24,4))    . " " . 
		"x28: "				. hex2int(substr($message,28,4))    . " " . 
        	"x32: "				. hex2int(substr($message,32,4)) ;
  }
  
  
    when ("F3")    {                     #allF3 DHW
    $message =
		"dhw_temp: " 			. hex2int(substr($message, 4,4))/10 . " " .
        	"outside_temp: " 		. hex2int(substr($message, 8,4))/10 . " " .
        	"dhw_set_temp: "		. hex2int(substr($message,12,4))/10 . " " .
        	"comp_block_time: "		. hex2int(substr($message,16,4))    . " " .
        	"x20: " 			. hex2int(substr($message,20,4))    . " " .
        	"heat_block_time: "		. hex2int(substr($message,24,4))    . " " . 
		"x28: "				. hex2int(substr($message,28,4))    . " " . 
        	"x32: "				. hex2int(substr($message,32,4))    . " " .
        	"x36: "				. hex2int(substr($message,36,4))    . " " .
        	"x40: "				. hex2int(substr($message,40,4));
  }
  
  
  
  
  when ("F4")    {                     #allF4
    my %SomWinMode = ( "01" =>"winter", "02" => "summer");
    $message =
		"outside_temp: " 		. hex2int(substr($message, 4,4))/10 . " " .
        	"x08: " 			. hex2int(substr($message, 8,4))/10 . " " .
        	"return_temp: "			. hex2int(substr($message,12,4))/10 . " " .
        	"integral_heat: "		. hex2int(substr($message,16,4))    . " " .
        	"flow_temp: " 			. hex2int(substr($message,20,4))/10 . " " .
        	"heat-set_temp: "		. hex2int(substr($message,24,4))/10 . " " . #soll HC1
		"heat_temp: "			. hex2int(substr($message,28,4))/10 . " " . #ist
#	      	"x32: "				. hex2int(substr($message,32,4))/10 . " " .
        	"mode: "		        . $SomWinMode{(substr($message,38,2))}  . " " .
#		"x40: "				. hex2int(substr($message,40,4))/10 . " " .
		"integral_switch: "		. hex2int(substr($message,44,4))    . " " .
#		"x48: "				. hex2int(substr($message,40,4))/10 . " " .
#       	"x52: "				. hex2int(substr($message,52,4))/10 . " " .
        	"room-set-temp: "		. hex2int(substr($message,56,4))/10 ;
# 	     	"x60: " 			. hex2int(substr($message,60,4)) . " " .
# 	    	"x64: "				. hex2int(substr($message,64,4)) . " " .
#		"x68: "				. hex2int(substr($message,68,4)) . " " .
#       	"x72: "				. hex2int(substr($message,72,4)) . " " .
# 	     	"x76: "				. hex2int(substr($message,76,4)) . " " .
# 	    	"x80: "				. hex2int(substr($message,80,4))
		;
  }
  when ("F5")    {                     #allF5
    my %SomWinMode = ( "01" =>"winter", "02" => "summer");
    $message =
		"outside_temp: " 		. hex2int(substr($message, 4,4))/10 . " " .
        	"return_temp: " 		. hex2int(substr($message, 8,4))/10 . " " .
        	"vorlauftemp: "			. hex2int(substr($message,12,4))/10 . " " .
        	"heat_temp: "			. hex2int(substr($message,16,4))/10 . " " .
        	"heat-set_temp: " 		. hex2int(substr($message,20,4))/10 . " " .
        	"stellgroesse: "		. hex2int(substr($message,24,4))/10 . " " . 
	        "mode: "		        . $SomWinMode{(substr($message,30,2))}  ;
#	     	"x32: "				. hex2int(substr($message,32,4)) . " " .
#	    	"x36: "				. hex2int(substr($message,36,4)) . " " .
# 	  	"x40: "				. hex2int(substr($message,40,4)) . " " .
#		"x44: "				. hex2int(substr($message,44,4)) . " " .
#		"x48: " 			. hex2int(substr($message,48,4)) . " " .
#        	"x52: "				. hex2int(substr($message,52,4))
  }

  
  when ("FD")    {                     #firmware_ver
    $message = "version: " . hex(substr($message,4,4))/100 ;
  }
  when ("FC")    {                     #timedate 00 - 0F 1E 08 - 0D 03 0B
    my %weekday = ( "0" =>"Monday", "1" => "Tuesday", "2" =>"Wednesday", "3" => "Thursday", "4" => "Friday", "5" =>"Saturday", "6" => "Sunday" );
    $message = 	  "Weekday: "		. $weekday{hex(substr($message, 4,2))}    . " " .
            	  "Hour: " 		. hex(substr($message, 6,2)) . " Min: " . hex(substr($message, 8,2)) . " Sec: " . hex(substr($message,10,2)) . " " .
              	  "Date: " 		. (hex(substr($message,12,2))+2000)  .	"/"		. hex(substr($message,14,2)) . "/"		. hex(substr($message,16,2));
  }
  when ("FB")    {                     #allFB
    $message =    "outside_temp: " 				. hex2int(substr($message, 8,4))/10 . " " .
        	  "flow_temp: "					. hex2int(substr($message,12,4))/10 . " " .  #Vorlauf Temperatur
        	  "return_temp: "				. hex2int(substr($message,16,4))/10 . " " .  #Rücklauf Temperatur
        	  "hot_gas_temp: " 				. hex2int(substr($message,20,4))/10 . " " .  #Heißgas Temperatur		
        	  "dhw_temp: "					. hex2int(substr($message,24,4))/10 . " " .  #Speicher Temperatur current cilinder water temperature
        	  "flow_temp_HC2: "				. hex2int(substr($message,28,4))/10 . " " .  #Vorlauf TemperaturHK2
		  "evaporator_temp: "				. hex2int(substr($message,36,4))/10 . " " .  #Speicher Temperatur    
        	  "condenser_temp: "				. hex2int(substr($message,40,4))/10 . " " .  
        	  "Mixer_open: "				. ((hex(substr($message,45,1)) &  0b0001) / 0b0001) . " " .	#status bit
		  "Mixer_closed: "				. ((hex(substr($message,45,1)) &  0b0010) / 0b0010) . " " .	#status bit
		  "HeatPipeValve: "				. ((hex(substr($message,45,1)) &  0b0100) / 0b0100) . " " .	#status bit
		  "DiverterValve: "				. ((hex(substr($message,45,1)) &  0b1000) / 0b1000) . " " .	#status bit
		  "DHW_Pump: "					. ((hex(substr($message,44,1)) &  0b0001) / 0b0001) . " " .	#status bit
		  "HeatingCircuit_Pump: "			. ((hex(substr($message,44,1)) &  0b0010) / 0b0010) . " " .	#status bit
		  "Solar_Pump: "				. ((hex(substr($message,44,1)) &  0b1000) / 0b1000) . " " .	#status bit
		  "Compressor: "				. ((hex(substr($message,47,1)) &  0b1000) / 0b1000) . " " .	#status bit
		  "BoosterStage3: "				. ((hex(substr($message,46,1)) &  0b0001) / 0b0001) . " " .	#status bit
		  "BoosterStage2: "				. ((hex(substr($message,46,1)) &  0b0010) / 0b0010) . " " .	#status bit
		  "BoosterStage1: "				. ((hex(substr($message,46,1)) &  0b0100) / 0b0100). " " .	#status bit
		  "HighPressureSensor: "			. (1-((hex(substr($message,49,1)) &  0b0001) / 0b0001)) . " " .	#status bit  #P1 	inverterd?
		  "LowPressureSensor: "				. (1-((hex(substr($message,49,1)) &  0b0010) / 0b0010)) . " " .	#status bit  #P3  inverterd?
		  "EvaporatorIceMonitor: "			. ((hex(substr($message,49,1)) &  0b0100) / 0b0100). " " .	#status bit  #N3
		  "SignalAnode: "				. ((hex(substr($message,49,1)) &  0b1000) / 0b1000). " " .	#status bit  #S1
		  "EVU_release: "				. ((hex(substr($message,48,1)) &  0b0001) / 0b0001). " " . 	#status bit 
		  "OvenFireplace: "				. ((hex(substr($message,48,1)) &  0b0010) / 0b0010). " " .  	#status bit
		  "STB: "					. ((hex(substr($message,48,1)) &  0b0100) / 0b0100). " " .	#status bit  	
		  "OutputVentilatorPower: "			. hex(substr($message,50,4))/10  	. " " .
        	  "InputVentilatorPower: " 			. hex(substr($message,54,4))/10  	. " " .
        	  "MainVentilatorPower: "			. hex(substr($message,58,4))/10  	. " " .
        	  "OutputVentilatorSpeed: "			. hex(substr($message,62,4))/1   	. " " .  # m3/h
        	  "InputVentilatorSpeed: " 			. hex(substr($message,66,4))/1   	. " " .  # m3/h
        	  "MainVentilatorSpeed: "			. hex(substr($message,70,4))/1   	. " " .  # m3/h
                  "Outside_tempFiltered: "			. hex2int(substr($message,74,4))/10     . " " .
                  "Rel_humidity: "				. hex2int(substr($message,78,4))/10	. " " .
		  "DEW_point: "					. hex2int(substr($message,86,4))/1	. " " .
		  "P_Nd: "					. hex2int(substr($message,86,4))/100	. " " .	#bar
		  "P_Hd: "					. hex2int(substr($message,90,4))/100	. " " .  #bar
		  "Actual_power_Qc: "				. hex2int(substr($message,94,8))/1      . " " .	#kw
		  "Actual_power_Pel: "				. hex2int(substr($message,102,4))/1     . " " .	#kw
		  "collector_temp: " 				. hex2int(substr($message, 4,4))/10  . " " .	#kw
		  "inside_temp: " 				. hex2int(substr($message, 32,4))/10 ;	#Innentemperatur 
  }
  when ("09")    {                     #operating history
    $message =    "compressor_heating: "	. hex(substr($message, 4,4))    . " " .
                  "compressor_cooling: "	. hex(substr($message, 8,4))    . " " .
                  "compressor_dhw: "		. hex(substr($message, 12,4))    . " " .
                  "booster_dhw: "		. hex(substr($message, 16,4))    . " " .
                  "booster_heating: "		. hex(substr($message, 20,4))   ;			
  }
  when ("D1")    {                     #last10errors tested only for 1 error   { THZ_Parse("6BD1010115008D07EB030000000000000000000")  }
    $message =    "number_of_faults: "		. hex(substr($message, 4,2))    . " " .
                  #empty
		  "fault0CODE: "		. hex(substr($message, 8,2))    . " " .
                  "fault0TIME: "		. sprintf(join(':', split("\\.", hex(substr($message, 14,2) . substr($message, 12,2))/100)))   . " " .
                  "fault0DATE: "		. (hex(substr($message, 18,2) . substr($message, 16,2))/100) . " " .
		  
		  "fault1CODE: "		. hex(substr($message, 20,2))    . " " .
                  "fault1TIME: "		. sprintf(join(':', split("\\.", hex(substr($message, 26,2) . substr($message, 24,2))/100)))   . " " .
                  "fault1DATE: "		. (hex(substr($message, 30,2) . substr($message, 28,2))/100) . " " .
		 
		  "fault2CODE: "		. hex(substr($message, 32,2))    . " " .
                  "fault2TIME: "		. sprintf(join(':', split("\\.", hex(substr($message, 38,2) . substr($message, 36,2))/100)))   . " " .
                  "fault2DATE: "		. (hex(substr($message, 42,2) . substr($message, 40,2))/100) . " " .
		
		  "fault3CODE: "		. hex(substr($message, 44,2))    . " " .
                  "fault3TIME: "		. sprintf(join(':', split("\\.", hex(substr($message, 50,2) . substr($message, 48,2))/100)))   . " " .
                  "fault3DATE: "		. (hex(substr($message, 54,2) . substr($message, 52,2))/100)  ;			
  }    
  }
  return (undef, $message);
}


#######################################
#THZ_Parse1($) could be used in order to test an external config file; I do not know if I want it
#
#######################################

sub THZ_Parse1($) {
my %parsinghash = (
        "D1"       => {"number_of_faults:" => [4,"hex",1],                                 
		        "fault0CODE:"      => [8,"hex",1],
			"fault0DATE:"      => [12,"hex",1]  
                    },
	"D2"       => {"number_of_faults:" => [8,"hex",1],                              
			"fault0CODE:"      => [8,"hex",1]              
                    }
);

  my ($Msg) = @_;
  my $parsingcmd = $parsinghash{substr($Msg,2,2)};   
  my $ParsedMsg = $Msg;
  if(defined($parsingcmd)) {
    $ParsedMsg = "";
    foreach  my $parsingkey  (keys %$parsingcmd) {
      my $positionInMsg = $parsingcmd->{$parsingkey}[0];
      my $Type = $parsingcmd->{$parsingkey}[1];
      my $divisor = $parsingcmd->{$parsingkey}[2];
      my $value = substr($Msg, $positionInMsg ,4);
      given ($Type) {
        when ("hex")    { $value= hex($value);}
        when ("hex2int")    { $value= hex($value);}
        }
    $ParsedMsg = $ParsedMsg ." ". $parsingkey ." ". $value/$divisor ; 
    }
  }
  return (undef, $ParsedMsg);
}





########################################################################################
# only for debug
#
########################################################################################
sub THZ_debugread($){
  my ($hash) = @_;
  my ($err, $msg) =("", " ");
  my @numbers=('01', '09', '16', 'D1', 'D2', 'E8', 'E9', 'F2', 'F3', 'F4', 'F5', 'F6', 'FB', 'FC', 'FD', 'FE');
 #my @numbers=('0A05A2','0A0116'); 
  #my @numbers = (1..255);
  #my @numbers = (1..65535);
  my $indice= "FF";
  unlink("data.txt"); #delete  debuglog
  foreach $indice(@numbers) {	
    #my $cmd = sprintf("%02X", $indice);
    #my $cmd = "0A" . sprintf("%04X",  $indice);
    my $cmd = $indice;
    #STX start of text
    THZ_Write($hash,  "02");
    ($err, $msg) = THZ_ReadAnswer($hash);  
    # send request
    my $cmdHex2 = THZ_encodecommand($cmd,"get"); 
    THZ_Write($hash,  $cmdHex2);
    ($err, $msg) = THZ_ReadAnswer($hash);
    # ack datatranfer and read from the heatpump        
    THZ_Write($hash,  "10");
    ($err, $msg) = THZ_ReadAnswer($hash);
    THZ_Write($hash,  "10");
    
    #my $activatetrigger =1;
	#	  readingsSingleUpdate($hash, $cmd, $msg, $activatetrigger);
	#	  open (MYFILE, '>>data.txt');
	#	  print MYFILE ($cmdHex2 . "-" . $msg . "\n");
	#	  close (MYFILE); 
    
    if (defined($err))  {return ($msg ."\n" . $err);}
    else {   #clean up and remove footer and header
	($err, $msg) = THZ_decode($msg);
	if (defined($err)) {$msg=$cmdHex2 ."-". $msg ."-". $err;} 
		  my $activatetrigger =1;
		 # readingsSingleUpdate($hash, $cmd, $msg, $activatetrigger);
		  open (MYFILE, '>>data.txt');
		  print MYFILE ($cmd . "-" . $msg . "\n");
		  close (MYFILE); 
    }    
    select(undef, undef, undef, 0.2); #equivalent to sleep 200ms
  }
}






#####################################



sub THZ_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  RemoveInternalTimer($hash);
  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log GetLogLevel($name,$lev), "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }
  DevIo_CloseDev($hash); 
  return undef;
}














1;


=pod
=begin html

<a name="THZ"></a>
<h3>THZ</h3>
<ul>
  THZ module: comunicate through serial interface RS232/USB (eg /dev/ttyxx) or through ser2net (e.g 10.0.x.x:5555) with a Tecalor/Stiebel Eltron heatpump. <br>
   Tested on a THZ303/Sol (with serial speed 57600/115200@USB) and a THZ403 (with serial speed 115200) with the same Firmware 4.39. <br>
   Tested on a LWZ404 (with serial speed 115200) with Firmware 5.39. <br>
   Tested on fritzbox, nas-qnap, raspi and macos.<br>
   This module is not working if you have an older firmware; Nevertheless, "parsing" could be easily updated, because now the registers are well described.
  https://answers.launchpad.net/heatpumpmonitor/+question/100347  <br>
   Implemented: read of status parameters and read/write of configuration parameters.
  <br><br>

  <a name="THZdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; THZ &lt;device&gt;</code> <br>
    <br>
    <code>device</code> can take the same parameters (@baudrate, @directio,
    TCP/IP, none) like the <a href="#CULdefine">CUL</a>,  e.g  57600 baud or 115200.<br>
    Example:
    direct connection   
    <ul><code>
      define Mytecalor 			THZ   /dev/ttyUSB0@115200<br>
      </code></ul>
      or network connection (like via ser2net)<br>
      <ul><code>
      define Myremotetecalor  	THZ  192.168.0.244:2323 
    </code></ul>
    <br>
      <ul><code>
      define Mythz THZ /dev/ttyUSB0@115200 <br>
      attr Mythz interval_allFB 300      # internal polling interval 5min  <br>
      attr Mythz interval_history 28800  # internal polling interval 8h    <br>
      attr Mythz interval_last10errors 86400 # internal polling interval 24h    <br>
      define FileLog_Mythz FileLog ./log/Mythz-%Y.log Mythz <br>
      </code></ul>
     <br> 
   If the attributes interval_allFB and interval_history are not defined (or 0), their internal polling is disabled.  
   Clearly you can also define the polling interval outside the module with the "at" command.
    <br>
      <ul><code>
      define Mythz THZ /dev/ttyUSB0@115200 <br>
      define atMythzFB at +*00:05:00 {fhem "get Mythz allFB","1";;return()}    <br>
      define atMythz09 at +*08:00:00 {fhem "get Mythz history","1";;return()}   <br>
      define FileLog_Mythz FileLog ./log/Mythz-%Y.log Mythz <br>
      </code></ul>
      
  </ul>
  <br>
</ul>
 
=end html

=begin html_DE

<a name="THZ"></a>
<h3>THZ</h3>
<ul>
  THZ Modul: Kommuniziert mittels einem seriellen Interface RS232/USB (z.B. /dev/ttyxx), oder mittels ser2net (z.B. 10.0.x.x:5555) mit einer Tecalor / Stiebel  
  Eltron W&auml;rmepumpe. <br>
  Getestet mit einer Tecalor THZ303/Sol (Serielle Geschwindigkeit 57600/115200@USB) und einer THZ403 (Serielle Geschwindigkeit 115200) mit identischer 
  Firmware 4.39. <br>
  Getestet mit einer Stiebel LWZ404 (Serielle Geschwindigkeit 115200@USB) mit Firmware 5.39. <br>
  Getestet auf FritzBox, nas-qnap, Raspberry Pi and MacOS.<br>
  Dieses Modul funktioniert nicht mit &aumlterer Firmware; Gleichwohl, das "parsing" k&ouml;nnte leicht angepasst werden da die Register gut 
  beschrieben wurden.
  https://answers.launchpad.net/heatpumpmonitor/+question/100347  <br>
  Implementiert: Lesen der Statusinformation sowie Lesen und Schreiben einzelner Einstellungen.
  <br><br>

  <a name="THZdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; THZ &lt;device&gt;</code> <br>
    <br>
    <code>device</code> kann einige Parameter beinhalten (z.B. @baudrate, @direction,
    TCP/IP, none) wie das <a href="#CULdefine">CUL</a>, z.B. 57600 baud oder 115200.<br>
    Beispiel:<br>
    Direkte Verbindung
    <ul><code>
      define Mytecalor THZ /dev/ttyUSB0@115200<br>
      </code></ul>
      oder vir Netzwerk (via ser2net)<br>
      <ul><code>
      define Myremotetecalor THZ 192.168.0.244:2323 
    </code></ul>
    <br>
      <ul><code>
      define Mythz THZ /dev/ttyUSB0@115200 <br>
      attr Mythz interval_allFB 300      # Internes Polling Intervall 5min  <br>
      attr Mythz interval_history 28800  # Internes Polling Intervall 8h    <br>
      attr Mythz interval_last10errors 86400 # Internes Polling Intervall 24h    <br>
      define FileLog_Mythz FileLog ./log/Mythz-%Y.log Mythz <br>
      </code></ul>
     <br> 
   Wenn die Attribute interval_allFB und interval_history nicht definiert sind (oder 0), ist das interne Polling deaktiviert.
   Nat&uuml;rlich kann das Polling auch mit dem "at" Befehl ausserhalb des Moduls definiert werden.
    <br>
      <ul><code>
      define Mythz THZ /dev/ttyUSB0@115200 <br>
      define atMythzFB at +*00:05:00 {fhem "get Mythz allFB","1";;return()}    <br>
      define atMythz09 at +*08:00:00 {fhem "get Mythz history","1";;return()}   <br>
      define FileLog_Mythz FileLog ./log/Mythz-%Y.log Mythz <br>
      </code></ul>
      
  </ul>
  <br>
</ul>
 
=end html_DE


=cut


