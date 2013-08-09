# $Id$
##############################################################################
#
#	55_GDS.pm
#
#	An FHEM Perl module to retrieve data from "Deutscher Wetterdienst"
#
#	Copyright: betateilchen ®
#	e-mail: fhem.development@betateilchen.de
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#	Changelog:
#
#	2013-08-07	initial release
#
#	2013-08-08	added	logging
#				added	firewall/proxy support
#				fixed	XMLin missing parameter 
#				added	:noArg to setlist-definitions
#				added	AttrFn
#				modi	retrieval of VHDL messages 30-33
#

package main;

use strict;
use warnings;
use feature qw/say switch/;
use Time::HiRes qw(gettimeofday);
use Net::FTP;
use List::MoreUtils 'first_index'; 
use XML::Simple;

sub GDS_Define($$$);
sub GDS_Undef($$);
sub GDS_Set($@);
sub GDS_Get($@);
sub GDS_Attr(@);

sub getListStationsDropdown();
sub buildCAPList();


my $bulaList = "Baden-Württemberg,Bayern,Berlin,Brandenburg,Bremen,".
				"Hamburg,Hessen,Mecklenburg-Vorpommern,Niedersachsen,".
				"Nordrhein-Westfalen,Rheinland-Pfalz,Saarland,Sachsen,".
				"Sachsen-Anhalt,Schleswig-Holstein,Thüringen";

#
# Bundesländer den entsprechenden Dienststellen zuordnen
#
my %bula2dwd = (
	"Baden-Württemberg" => "DWSG",
	"Bayern" => "DWMG",
	"Berlin" => "DWPG",
	"Brandenburg" => "DWPG",
	"Bremen" => "DWHG",
	"Hamburg" => "DWHH",
	"Hessen" => "DWOH",
	"Mecklenburg-Vorpommern" => "DWPH",
	"Niedersachsen" => "DWHG",
	"Nordrhein-Westfalen" => "DWEH",
	"Rheinland-Pfalz" => "DWOI",
	"Saarland" => "DWOI",
	"Sachsen" => "DWLG",
	"Sachsen-Anhalt" => "DWLH",
	"Schleswig-Holstein" => "DWHH",
	"Thüringen" => "DWLI" );

#
# Dienststellen den entsprechenden Serververzeichnissen zuordnen
#
my %dwd2Dir = (
	DWSG => "SU", # Stuttgart
	DWMG => "MS", # München
	DWPG => "PD", # Potsdam
	DWHG => "HA", # Hamburg
	DWHH => "HA", # Hamburg
	DWOH => "OF", # Offenbach
	DWPH => "PD", # Potsdam
	DWHG => "HA", # Hamburg
	DWEH => "EM", # Essen
	DWOI => "OF", # Offenbach
	DWLG => "LZ", # Leipzig
	DWLH => "LZ", # Leipzig
	DWLI => "LZ", # Leipzig
	DWHC => "HA", # Hamburg
	DWHB => "HA", # Hamburg
	DWPD => "PD", # Potsdam
	DWRW => "PD", # Potsdam
	DWEM => "EM", # Essen
	LSAX => "LZ", # Leipzig
	LSNX => "LZ", # Leipzig
	THLX => "LZ", # Leipzig
	DWOF => "OF", # Offenbach
	DWTR => "OF", # Offenbach
	DWSU => "SU", # Stuttgart
	DWMS => "MS" # München
#	???? => "FG" # Freiburg
);

my %dwd2Name = (
	EM => "Essen",
	FG => "Freiburg",
	HA => "Hamburg",
	LZ => "Leipzig",
	MS => "München",
	OF => "Offenbach",
	PD => "Potsdam",
	SU => "Stuttgart"
);

my %iiList = (
	"31" => "Gewitter",
	"33" => "Starkes Gewitter",
	"34" => "Starkes Gewitter",
	"36" => "Starkes Gewitter",
	"38" => "Starkes Gewitter",
	"40" => "Schweres Gewitter",
	"41" => "Schweres Gewitter mit extremen Orkanböen",
	"42" => "Schweres Gewitter",
	"44" => "Schweres Gewitter",
	"45" => "Schweres Gewitter mit extremen Orkanböen",
	"46" => "Schweres Gewitter",
	"48" => "Schweres Gewitter",
	"49" => "Schweres Gewitter mit extremen Orkanböen",
	"51" => "Windböen",
	"52" => "Sturmböen",
	"53" => "Schwere Sturmböen",
	"54" => "Orkanartige Böen",
	"55" => "Orkanböen",
	"56" => "Extreme Orkanböen",
	"59" => "Nebel",
	"61" => "Starkregen",
	"62" => "Heftiger Starkregen",
	"63" => "Dauerregen",
	"64" => "Ergiebiger Dauerregen",
	"65" => "Extrem ergiebiger Dauerregen",
	"66" => "Extrem heftiger Starkregen",
	"70" => "Schneefall",
	"71" => "Schneefall",
	"72" => "Starker Schneefall",
	"73" => "Extrem starker Schneefall",
	"74" => "Schneeverwehung",
	"75" => "Starke Schneeverwehung",
	"76" => "Schneeverwehung",
	"77" => "Starke Schneeverwehung",
	"78" => "Extrem starke Schneeverwehung",
	"81" => "Frost",
	"82" => "Strenger Frost",
	"83" => "Glätte",
	"84" => "Glätte",
	"85" => "Glatteis",
	"86" => "Glätte",
	"87" => "Glätte",
	"88" => "Tauwetter",
	"89" => "Starkes Tauwetter",
	"94" => "Schweres Gewitter",
	"95" => "Schweres Gewitter mit extrem heftigem Starkregen",
	"96" => "Schweres Gewitter mit extrem heftigem Starkregen"
);

my ($alertsXml, %capCityHash, %capCellHash);

my $sList;
if (-e "/tmp/conditions"){
	$sList = getListStationsDropdown();
} else {
	$sList = "please_use_rereadcfg_first";
}

my ($aList, $numCAPCount);
if (-e "/tmp/alerts"){
	($aList, $numCAPCount) = buildCAPList();
} else {
	$aList = "please_use_rereadcfg_first";
	$numCAPCount = 0;
}


####################################################################################################
#
# Main routines
#

sub GDS_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}		=	"GDS_Define";
	$hash->{UndefFn}	=	"GDS_Undef";
	$hash->{GetFn}		=	"GDS_Get";
	$hash->{SetFn}		=	"GDS_Set";
	$hash->{AttrFn}		=	"GDS_Attr";
	$hash->{AttrList}	=	"loglevel:0,1,2,3,4,5 ".
							"gdsFwName gdsFwType:0,1,2,3,4,5,6,7 ".
							"gdsAll:0,1 gdsDebug:0,1 gdsLong:0,1 gdsPolygon:0,1 ".
							$readingFnAttributes;
}

sub GDS_Define($$$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	my $found;

	return "syntax: define <name> GDS <username> <password>" if(int(@a) != 4 ); 
	my $name = $hash->{NAME};
	$hash->{helper}{USER}		= $a[2];
	$hash->{helper}{PASS}		= $a[3];
	$hash->{helper}{URL}		= "ftp-outgoing2.dwd.de";
	$hash->{helper}{INTERVAL}	= 3600;

	(undef, $found) = retrieveFile($hash,"conditions");
	if($found){
		$sList = getListStationsDropdown()
	} else {
		Log 2, "GDS $name: No datafile (conditions) found";
	}
	retrieveFile($hash,"alerts");
	if($found){
		($aList, undef) = buildCAPList();
	} else {
		Log 2, "GDS $name: No datafile (alerts) found";
	}
	Log 3, "GDS $name created";
	$hash->{STATE} = "active";

	return undef;
}

sub GDS_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash);
	return undef;
}

sub GDS_Attr(@){
	my @a = @_;
	my $hash = $defs{$a[1]};
	my (undef, $name, $attrName, $attrValue) = @a;
	given($attrName){
		when("gdsDebug"){
			CommandDeleteReading(undef, "$name _dF.*") if($attrValue != 1);
			break;
			}

		default {$attr{$name}{$attrName} = $attrValue;}
	}
	return "";
}

sub GDS_GetUpdate($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my (@a, $next);

	push @a, undef;
	push @a, undef;
	push @a, ReadingsVal($name, "c_stationName", "");
	retrieveConditions($hash, "c", @a);

	$next = gettimeofday()+$hash->{helper}{INTERVAL};
	readingsSingleUpdate($hash, "c_nextUpdate", localtime($next), 1);
	InternalTimer($next, "GDS_GetUpdate", $hash, 1);

	return 1;
}

sub GDS_Get($@) {
	my ($hash, @a) = @_;
	my $command		= lc($a[1]);
	my $parameter	= $a[2] if(defined($a[2]));
	my $name = $hash->{NAME};

	$hash->{LOCAL} = 1;

	my $usage = "Unknown argument $command, choose one of help:noArg rereadcfg:noArg ".
				"list:stations,data ".
				"alerts:".$aList." ".
				"conditions:".$sList." ".
				"warnings:".$bulaList;


	my ($result, $datensatz, $found);

	given($command) {
		when("help"){
			$result = getHelp();
			break;
			}

		when("list"){
			given($parameter){
				when("data")		{ $result = getListData($hash,@a); break; }
				when("stations")	{ $result = getListStationsText($hash,@a); break; }
				default				{ $usage = "get <name> list <parameter>"; return $usage; }
			}
			break;
			}

		when("alerts"){
			if($parameter =~ y/0-9// == length($parameter)){
				$datensatz = $capCellHash{$parameter};
			} else {
				$datensatz = $capCityHash{$parameter};
			}
			CommandDeleteReading(undef, "$name a_.*");
			if($datensatz){
				decodeCAPData($hash, $datensatz);
			} else {
				$result = "Keine Warnmeldung für die gesuchte Region vorhanden.";
			}
			break;
			}

		when("conditions"){
			retrieveConditions($hash, "g", @a);
			break;
			}

		when("rereadcfg"){
			eval {
				retrieveFile($hash,"conditions");
				$sList = getListStationsDropdown();
			}; 
			eval {
				retrieveFile($hash,"alerts");
				($aList, undef) = buildCAPList();
			}; 
			break;
			}

		when("warnings"){
			my $vhdl;
			$result= "Warnlageberichte für $parameter";
			for ($vhdl=30; $vhdl <=33; $vhdl++){
				(undef, $found) = retrieveFile($hash, $command, $parameter, $vhdl);
				if($found){
					$result .= "\n".sepLine(70);
					$result .= retrieveTextWarn($hash,@a);
				}
			}
			break;
			}

		default { return $usage; };
	}
	return $result;
}

sub GDS_Set($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $usage =	"Unknown argument, choose one of clear:noArg help:noArg rereadcfg:noArg update:noArg ".
				"conditions:".$sList." ";

	my $command		= lc($a[1]);
	my $parameter	= $a[2] if(defined($a[2]));

	my ($result, $next);

	$hash->{LOCAL} = 1;
	$hash->{STATE} = "active";

	given($command) {
		when("clear"){
			CommandDeleteReading(undef, "$name a_.*");
			CommandDeleteReading(undef, "$name c_.*");
			CommandDeleteReading(undef, "$name g_.*");
			}
		when("help"){
			$result = setHelp();
			break;
			}

		when("rereadcfg"){
			eval {
				retrieveFile($hash,"conditions");
				$sList = getListStationsDropdown();
			}; 
			eval {
				retrieveFile($hash,"alerts");
				($aList, undef) = buildCAPList();
			}; 
			break;
			}

		when("update"){
			RemoveInternalTimer($hash);
			GDS_GetUpdate($hash);
			break;
			}

		when("conditions"){
			retrieveConditions($hash, "c", @a);
			$next = gettimeofday()+$hash->{helper}{INTERVAL};
			readingsSingleUpdate($hash, "c_nextUpdate", localtime($next), 1);
			RemoveInternalTimer($hash);
			InternalTimer($next, "GDS_GetUpdate", $hash, 1);
			break;
			}

		default { return $usage; };
	}
	return $result;
}

####################################################################################################
#
# Routines used by "get"
#

sub getHelp(){
	return	"Use one of the following commands:\n".
			sepLine(35)."\n".
			"get <name> alerts <region>\n".
			"get <name> conditions <stationName>\n".
			"get <name> help\n".
			"get <name> list stations|data\n".
			"get <name> rereadcfg\n".
			"get <name> warnings <region>\n";
}

sub getListData($@){
	my ($line, @a);

	open WXDATA, "/tmp/conditions";
	while (chomp($line = <WXDATA>)) {
		push @a, latin1ToUtf8($line);
	}
	close WXDATA;

	return join("\n", @a);
}

sub getListStationsText($@){
	my ($line, @a);

	open WXDATA, "/tmp/conditions";
	while (chomp($line = <WXDATA>)) {
		push @a, substr(latin1ToUtf8($line),0,19);
	}
	close WXDATA;

	splice(@a,0,6);
	splice(@a,first_index { /Höhe/ } @a);
	splice(@a,-1);
	@a = sort(@a);
	unshift(@a, "Use one of the following stations:", sepLine(40));

	return join("\n", @a);
}

####################################################################################################
#
# Routines used by "set"
#

sub setHelp(){
	return	"Use one of the following commands:\n".
			sepLine(35)."\n".
			"set <name> clear\n".
			"set <name> conditions <stationName>\n".
			"set <name> rereadcfg\n".
			"set <name> update\n".
			"set <name> help\n";
}

####################################################################################################
#
# some tools
# called by various routines
#

sub buildCAPList(){
	my $xml			= new XML::Simple;
	$alertsXml		= undef;
	$alertsXml		= $xml->XMLin('/tmp/alerts', KeyAttr => {}, ForceArray => [ 'info', 'eventCode', 'area', 'geocode' ]);
	my $info		= 0;
	my $area		= 0;
	my $record		= 0;
	my $n			= 0;
	my ($capCity, $capCell, $capExit, @a, $list);

	%capCityHash	= ();
	%capCellHash	= ();
	$aList			= undef;
	
	while(1) {
		$area = 0;
		while(1){
			$capCity = $alertsXml->{info}[$info]{area}[$area]{areaDesc};
			$capExit = $alertsXml->{info}[$info]{event};
			if(!$capCity) {last;}
			$capCell = findCAPWarnCellId($info, $area);
			$n = 100*$info+$area;
			$capCity = latin1ToUtf8($capCity);
			push @a, $capCity;
			$capCity =~ s/\s/_/g;
			$capCityHash{$capCity} = $n;
			$capCellHash{"$capCell"} = $n;
Log 1, "I: $info A: $area City: $capCity Cell: $capCell";
			$area++;
			$record++;
			$capCity = undef;
		}
		if(!$capExit){last;}
		$info++;
	}

	@a = sort(@a);
	$list = join(",", @a);
	$list =~ s/\s/_/g;
	return ($list, $record);
}

sub decodeCAPData($$){
	my ($hash, $datensatz) = @_;
	my $name		= $hash->{NAME};
	my $loglevel	= GetLogLevel($name,3);
	my $info		= int($datensatz/100);
	my $area		= $datensatz-$info*100;

	my (%readings, @dummy, $i, $k, $n, $v, $t);

	my $_gdsAll		= AttrVal($name,"gdsAll", 0);
	my $_gdsDebug	= AttrVal($name,"gdsDebug", 0);
	my $_gdsLong	= AttrVal($name,"gdsLong", 0);
	my $_gdsPolygon	= AttrVal($name,"gdsPolygon", 0);

	Log $loglevel, "GDS $name: Decoding CAP record #".$datensatz;

# topLevel informations
	@dummy = split(/\./, $alertsXml->{identifier});

	$readings{a_identifier}		= $alertsXml->{identifier}	if($_gdsAll || $_gdsDebug);
	$readings{a_idPublisher}	= $dummy[5]					if($_gdsAll);
	$readings{a_idSysten}		= $dummy[6]					if($_gdsAll);
	$readings{a_idTimeStamp}	= $dummy[7]					if($_gdsAll);
	$readings{a_idIndex}		= $dummy[8]					if($_gdsAll);
	$readings{a_sent}			= $alertsXml->{sent};
	$readings{a_status}			= $alertsXml->{status};
	$readings{a_msgType}		= $alertsXml->{msgType};

# infoSet informations
	$readings{a_language}		= $alertsXml->{info}[$info]{language}		if($_gdsAll);
	$readings{a_category}		= $alertsXml->{info}[$info]{category};
	$readings{a_event}			= $alertsXml->{info}[$info]{event};
	$readings{a_responseType}	= $alertsXml->{info}[$info]{responseType};
	$readings{a_urgency}		= $alertsXml->{info}[$info]{urgency}		if($_gdsAll);
	$readings{a_severity}		= $alertsXml->{info}[$info]{severity}		if($_gdsAll);
	$readings{a_certainty}		= $alertsXml->{info}[$info]{certainty}		if($_gdsAll);

# eventCode informations
# loop through array
	$i = 0;
	while(1){
		($n, $v) = (undef, undef);
		$n = $alertsXml->{info}[$info]{eventCode}[$i]{valueName};
		if(!$n) {last;}
		$n = "a_eventCode_".$n;
		$v = $alertsXml->{info}[$info]{eventCode}[$i]{value};
		$readings{$n} .= $v." " if($v);
		$i++;
	}

# time/validity informations
	$readings{a_effective}		= $alertsXml->{info}[$info]{effective}					if($_gdsAll);
	$readings{a_onset}			= $alertsXml->{info}[$info]{onset};
	$readings{a_expires}		= $alertsXml->{info}[$info]{expires};
	$readings{a_valid}			= checkCAPValid($readings{a_expires});

# text informations
	$readings{a_headline}		= $alertsXml->{info}[$info]{headline};
	$readings{a_description}	= $alertsXml->{info}[$info]{description}				if($_gdsAll || $_gdsLong);
	$readings{a_instruction}	= $alertsXml->{info}[$info]{instruction} 				if($readings{a_responseType} eq "Prepare" 
																						&& ($_gdsAll || $_gdsLong));

# area informations
	$readings{a_areaDesc} 		=  $alertsXml->{info}[$info]{area}[$area]{areaDesc};
	$readings{a_areaPolygon}	=  $alertsXml->{info}[$info]{area}[$area]{polygon}		if($_gdsAll || $_gdsPolygon);

# area geocode informations
# loop through array
	$i = 0;
	while(1){
		($n, $v) = (undef, undef);
		$n = $alertsXml->{info}[$info]{area}[$area]{geocode}[$i]{valueName};
		if(!$n) {last;}
		$n = "a_geoCode_".$n;
		$v = $alertsXml->{info}[$info]{area}[$area]{geocode}[$i]{value};
		$readings{$n} .= $v." " if($v);
		$i++;
	}

	$readings{a_altitude}		= $alertsXml->{info}[$info]{area}[$area]{altitude}		if($_gdsAll);
	$readings{a_ceiling}		= $alertsXml->{info}[$info]{area}[$area]{ceiling}		if($_gdsAll);

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "_copyright", "Quelle: Deutscher Wetterdienst");
	while(($k, $v) = each %readings) { readingsBulkUpdate($hash, $k, latin1ToUtf8($v)); }
	readingsEndUpdate($hash, 1);

	return;
}

sub checkCAPValid($){
	my ($expires) = @_;
	my $valid = 0;
	$expires =~ s/T/ /;
	$expires =~ s/\+/ \+/;
	$expires = time_str2num($expires);
	$valid = 1 if($expires gt time);
	return $valid;
}

sub findCAPWarnCellId($$){
	my ($info, $area) = @_;
	my $i = 0;
	while($i < 100){
		if($alertsXml->{info}[$info]{area}[$area]{geocode}[$i]{valueName} eq "WARNCELLID"){
			return $alertsXml->{info}[$info]{area}[$area]{geocode}[$i]{value};
			last;
		}
		$i++;
	}
}

sub retrieveTextWarn($@){
	my ($line, @a);

	open WXDATA, "/tmp/warnings";
	while (chomp($line = <WXDATA>)) { push @a, latin1ToUtf8($line); }
	close WXDATA;

	return join("\n", @a);
}

sub retrieveConditions($$@){
	my ($hash, $prefix, @a) = @_;
	my $name		= $hash->{NAME};
	my $loglevel	= GetLogLevel($name,3);
	my $user		= $hash->{helper}{USER};
	my $pass		= $hash->{helper}{PASS};
	(my $myStation	= utf8ToLatin1($a[2])) =~ s/_/ /g; # replace underscore in stationName by space
	my $searchLen	= length($myStation);

	my (%alignment, $dataFile, $decodeDummy, $debug, @files, $found, $ftp, $item, $line, %pos, %wx, $wx, %cread, $k, $v);

	$debug = AttrVal($name, "gdsDebug", 0);

	Log $loglevel, "GDS $name: Retrieving conditions data";
	
	($dataFile, $found) = retrieveFile($hash,"conditions");
	open WXDATA, "/tmp/conditions";
	while (chomp($line = <WXDATA>)) {
		map {s/\r//g;} ($line);
		if ($line =~ /Station/) {		# Header line... find out data positions
			@a = split(/\s+/, $line);
			foreach $item (@a) {
				$pos{$item} = index($line, $item);
			}
		}
		if (index(substr(lc($line),0,$searchLen), substr(lc($myStation),0,$searchLen)) != -1) { last; }
	}
	close WXDATA;

	%alignment = ("Station" => "l", "H\xF6he" => "r", "Luftd." => "r", "TT" => "r", "Tmin" => "r", "Tmax" => "r",
	"RR1" => "r", "RR24" => "r", "SSS" => "r", "DD" => "r", "FF" => "r", "FX" => "r", "Wetter/Wolken" => "l", "B\xF6en" => "l");
	
	foreach $item (@a) {
		$wx{$item} = &readItem($line, $pos{$item}, $alignment{$item}, $item);
	}

	%cread = ();
	$cread{"_copyright"} = "Quelle: Deutscher Wetterdienst";

	if(length($wx{"Station"})){
		$cread{$prefix."_stationName"}	= $wx{"Station"};
		$cread{$prefix."_altitude"}		= $wx{"H\xF6he"};
		$cread{$prefix."_pressure-nn"}	= $wx{"Luftd."};
		$cread{$prefix."_temperature"}	= $wx{"TT"};
		$cread{$prefix."_tempMin"}		= $wx{"Tmin"};
		$cread{$prefix."_tempMax"}		= $wx{"Tmax"};
		$cread{$prefix."_rain1h"}		= $wx{"RR1"};
		$cread{$prefix."_rain24h"}		= $wx{"RR24"};
		$cread{$prefix."_snow"}			= $wx{"SSS"};
		$cread{$prefix."_windDir"}		= $wx{"DD"};
		$cread{$prefix."_windSpeed"}	= $wx{"FF"};
		$cread{$prefix."_windPeak"}		= $wx{"FX"};
		$cread{$prefix."_weather"}		= $wx{"Wetter\/Wolken"};
		$cread{$prefix."_windGust"}		= $wx{"B\xF6en"};
	} else {
		$cread{$prefix."_stationName"}	= "unknown: $myStation";
	}

	CommandDeleteReading(undef, "$name $prefix"."_.*");
	readingsBeginUpdate($hash);
	while(($k, $v) = each %cread) { readingsBulkUpdate($hash, $k, latin1ToUtf8($v)); }
	readingsEndUpdate($hash, 1);

	$hash->{STATE} = "active";
	
	return ;
}

sub retrieveFile($$;$$){
#
# request = type, e.g. alerts, conditions, warnings
# parameter = additional selector, e.g. Bundesland
#
	my ($hash, $request, $parameter, $parameter2) = @_;
	my $name		= $hash->{NAME};
	my $loglevel	= GetLogLevel($name,3);
	my $user		= $hash->{helper}{USER};
	my $pass		= $hash->{helper}{PASS};
	my $proxyName	= AttrVal($name, "gdsProxyName", "");
	my $proxyType	= AttrVal($name, "gdsProxyType", "");
	my $debug		= AttrVal($name, "gdsDebug",0);

	my ($dwd, $dir, $ftp, @files, $dataFile, $targetFile, $found, $readingName);

	given($request){

		when("alerts"){
			$dir = "gds/specials/warnings/xml/PVW/";
			$dwd = "Z_CAP*";
			$targetFile = "/tmp/".$request;
			break;
			}

		when("conditions"){
			$dir = "gds/specials/observations/tables/germany/";
			$dwd = "*";
			$targetFile = "/tmp/".$request;
			break;
			}

		when("warnings"){
			$dwd = $bula2dwd{$parameter};
			$dir = $dwd2Dir{$dwd};
			$dwd = "VHDL".$parameter2."_".$dwd."*";
			$dir = "gds/specials/warnings/".$dir."/";
			$targetFile = "/tmp/".$request;
			break;
			}
	}

	Log $loglevel, "GDS $name: retrieving $dir".$dwd." from DWD server";

	$found = 0;
	eval {
		$ftp = Net::FTP->new(	"ftp-outgoing2.dwd.de", 
								Debug => 0,
								Timeout => 360,
								FirewallType => $proxyType,
								Firewall => $proxyName);
		if(defined($ftp)){
			$ftp->login($user, $pass);
			$ftp->cwd("$dir");
			@files = undef;
			@files = $ftp->ls($dwd);
			if(@files){
				@files = sort(@files);
				$dataFile = $files[-1];
				$ftp->get($files[-1], $targetFile);
				$found = 1;
			} else { 
				$found = 0;
			}
			$ftp->quit;
		}
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "_copyright",		"Quelle: Deutscher Wetterdienst");
		readingsBulkUpdate($hash, "_dF_".$request, $dataFile) if(AttrVal($name, "gdsDebug", 0));
		readingsEndUpdate($hash, 1);
	};
	return ($dataFile, $found);
}

sub getListStationsDropdown(){
	my ($line, $liste, @a);

	open WXDATA, "/tmp/conditions";
	while (chomp($line = <WXDATA>)) {
		push @a, trim(substr(latin1ToUtf8($line),0,19));
	}
	close WXDATA;

	splice(@a,0,6);
	splice(@a,first_index { /Höhe/ } @a);
	splice(@a,-1);
	@a = sort(@a);

	$liste = join(",", @a);
	$liste =~ s/\s+,/,/g; # replace multiple spaces followed by comma with comma
	$liste =~ s/\s/_/g;   # replace spaces in stationName with underscore for list in frontende
	return $liste;
}

sub readItem {
	my ($line, $pos, $align, $item)  = @_;
	my $x;
	
	if ($align eq "l") {
		$x = substr($line, $pos);
		$x =~ s/  .+$//g;	# after two spaces => next field
	}
	if ($align eq "r") {
		$pos += length($item);
		$x = substr($line, 0, $pos);
		$x =~ s/^.+  //g;	# remove all before the item
	}
	return $x;
}

sub sepLine($) {
	my ($len) = @_;
	my ($output, $i);
	for ($i=0; $i<$len; $i++) { $output .= "-"; }
	return $output;
}


1;


####################################################################################################
#
# Further informations
#

# DWD's data format is unpleasant to read, 
# since the data columns change depending on the available data
# (e.g. the SSS column for snow disappears when there is no snow).
# It's also in ISO8859-1, i.e. it contains non-ASCII characters. To
# avoid problems, we need some conversion subs in this program.

# Höhe  : m über NN
# Luftd.: reduzierter Luftdruck auf Meereshöhe in hPa
# TT    : Lufttemperatur in Grad Celsius
# Tmin  : Minimum der Lufttemperatur, 06 UTC Vortag bis 06 UTC heute, Grad Celsius
# Tmax  : Maximum der Lufttemperatur, 06 UTC Vortag bis 06 UTC heute, Grad Celsius
# RR1   : Niederschlagsmenge, einstündig, mm = l/qm
# RR24  : Niederschlagsmenge, 24stündig, 06 UTC Vortag bis 06 UTC heute, mm = l/qm
# SSS   : Gesamtschneehöhe in cm
# DD    : Windrichtung 
# FF    : Windgeschwindigkeit letztes 10-Minutenmittel in km/h
# FX    : höchste Windspitze im Bezugszeitraum in km/h
# ---   : Wert nicht vorhanden


####################################################################################################
#
# Documentation 
#

=pod
=begin html

<a name="GDS"></a>
<h3>GDS</h3>
<ul>
	<a name="GDSdefine"></a>
	<b>Define</b>
	<ul>

		<br/>
		<code>define &lt;name&gt; GDS &lt;username&gt; &lt;password&gt;</code>
		<br/><br/>
		This module provides connection to <a href="http://www.dwd.de/grundversorgung">GDS service</a> generated by <a href="http://www.dwd.de">DWD</a><br/>

	</ul>
	<br/><br/>

	<a name="GDSset"></a>
	<b>Set-Commands</b><br/>
	<ul>

		<br/>
		<code>set &lt;name&gt; clear </code>
		<br/><br/>
		<ul>Delete all a_*, c_* and g_* readings</ul>
		<br/>

		<code>set &lt;name&gt; conditions &lt;stationName&gt;</code>
		<br/><br/>
		<ul>Retrieve current conditions at selected station. Data will be updated periodically.</ul>
		<br/>

		<code>set &lt;name&gt; help</code>
		<br/><br/>
		<ul>Show a help text with available commands</ul>
		<br/>

		<code>set &lt;name&gt; rereadcfg</code>
		<br/><br/>
		<ul>Reread all required data from DWD Server manually: station list and CAP data</ul>
		<br/>

		<code>set &lt;name&gt; update</code>
		<br/><br/>
		<ul>Update conditions readings at selected station and restart update-timer</ul>
		<br/>

		<li>condition readings generated by SET use prefix "c_"</li>
		<li>readings generated by SET will be updated automatically every 60 minutes</li>

	</ul>
	<br/><br/>

	<a name="GDSget"></a>
	<b>Get-Commands</b><br/>
	<ul>

		<br/>
		<code>get &lt;name&gt; alerts &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve alert message for selected region from DWD server</ul>
		<br/>

		<code>get &lt;name&gt; conditions &lt;stationName&gt;</code>
		<br/><br/>
		<ul>Retrieve current conditions at selected station</ul>
		<br/>

		<code>get &lt;name&gt; help</code>
		<br/><br/>
		<ul>Show a help text with available commands</ul>
		<br/>

		<code>get &lt;name&gt; list data</code>
		<br/><br/>
		<ul>List current conditions for all available stations in one single table</ul>
		<br/>

		<code>get &lt;name&gt; list stations</code>
		<br/><br/>
		<ul>List all available stations that provide conditions data</ul>
		<br/>

		<code>get &lt;name&gt; rereadcfg</code>
		<br/><br/>
		<ul>Reread all required data from DWD Server manually: station list and CAP data</ul>
		<br/>

		<code>get &lt;name&gt; warnings &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve current warnings report for selected region</ul>
		<br/>

		<li>alert readings use prefix "a_"</li>
		<li>condition readings generated by GET use prefix "g_"</li>
		<li>readings generated by GET will not be updated automatically</li>

	</ul>
	<br/><br/>

	<a name="GDSattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>

		<li><a href="#loglevel">loglevel</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
		<br/>
		<li><b>gdsAll</b> - defines filter for "all data" from alert message</li>
		<li><b>gdsDebug</b> - defines filter for debug informations</li>
		<li><b>gdsLong</b> - show long text fields "description" and "instruction" from alert message in readings</li>
		<li><b>gdsPolygon</b> - show polygon data from alert message in a reading</li>
		<br/>
		<li><b>gdsFwName</b> - define firewall hostname in format &lt;hostname&gt;:&lt;port&gt;</li>
		<li><b>gdsFwType</b> - define firewall type in a value 0..7 please refer to <a href="http://search.cpan.org/~gbarr/libnet-1.22/Net/Config.pm#NetConfig_VALUES">cpan documentation</a> for further informations regarding firewall settings.</li>

	</ul>
	<br/><br/>

	<b>Generated Readings/Events:</b>
	<br/><br/>
	<ul>

		<li><b>_&lt;readingName&gt;</b> - debug informations</li>
		<li><b>a_&lt;readingName&gt;</b> - weather data from CAP alert messages. Readings will NOT be updated automatically</li>
		<li><b>c_&lt;readingName&gt;</b> - weather data from SET weather conditions. Readings will be updated every 60 minutes</li>
		<li><b>g_&lt;readingName&gt;</b> - weather data from GET weather conditions. Readings will NOT be updated automatically</li>

	</ul>
	<br/><br/>

	<b>Author's notes</b><br/><br/>
	<ul>

		<li>Module uses following additional Perl modules:<br/><br/>
		<ul>Net::FTP, List::MoreUtils, XML::Simple</ul><br/><br/>
		If not installed in your environment, please install with<br/><br/>
		<ul><code>cpan install moduleName</code></ul></li>
		<br/><br/>
		<li>Have fun!</li><br/>

	</ul>

</ul>

=end html
=cut
