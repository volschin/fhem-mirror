#########################################################################
# $Id$
# fhem Modul which provides traffic details with Google Distance API
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
#     versioning: MAJOR.MINOR.PATCH, increment the:
#     MAJOR version when you make incompatible API changes
#      - includes changing CLI options, changing log-messages
#     MINOR version when you add functionality in a backwards-compatible manner
#      - includes adding new features and log-messages (as long as they don't break anything existing)
#     PATCH version when you make backwards-compatible bug fixes.
#
##############################################################################
#   Changelog:
#
#   2016-07-26 initial release
#   2016-07-28 added eta, readings in minutes
#   2016-08-01 changed JSON decoding/encofing, added stateReading attribute, added outputReadings attribute
#   2016-08-02 added attribute includeReturn, round minutes & smart zero'ing, avoid negative values, added update burst 
#   2016-08-05 fixed 3 perl warnings
#   2016-08-09 added auto-update if status returns UNKOWN_ERROR, added outputReading average
#   2016-09-25 bugfix Blocking, improved errormessage
#   2016-10-07 version 1.0, adding to SVN
#   2016-10-15 adding attribute updateSchedule to provide flexible updates, changed internal interval to INTERVAL
#   2016-12-13 adding travelMode, fixing stateReading with value 0
#   2016-12-15 adding reverseWaypoints attribute, adding weblink with auto create route via gmaps on verbose 5
#   2017-04-21 reduced log entries if verbose is not set, fixed JSON error, Map available through FHEM-Web-toggle, and direct link
#              Map https, with APIKey, Traffic & customizable, new attributes  GoogleMapsStyle,GoogleMapsSize,GoogleMapsLocation,GoogleMapsStroke,GoogleMapsDisableUI
#
##############################################################################


package main;

use strict;                          
use warnings;                        
use Data::Dumper;
use Time::HiRes qw(gettimeofday);    
use LWP::Simple qw($ua get);
use Blocking;
use POSIX;
use JSON;
die "MIME::Base64 missing!" unless(eval{require MIME::Base64});
die "JSON missing!" unless(eval{require JSON});


sub TRAFFIC_Initialize($);
sub TRAFFIC_Define($$);
sub TRAFFIC_Undef($$);
sub TRAFFIC_Set($@);
sub TRAFFIC_Attr(@);
sub TRAFFIC_GetUpdate($);

my %TRcmds = (
    'update' => 'noArg',
);
my $TRVersion = '1.3';

sub TRAFFIC_Initialize($){

    my ($hash) = @_;

    $hash->{DefFn}      = "TRAFFIC_Define";
    $hash->{UndefFn}    = "TRAFFIC_Undef";
    $hash->{SetFn}      = "TRAFFIC_Set";

    $hash->{AttrFn}     = "TRAFFIC_Attr";
    $hash->{AttrList}   = 
      "disable:0,1 start_address end_address raw_data:0,1 language waypoints returnWaypoints stateReading outputReadings travelMode:driving,walking,bicycling,transit includeReturn:0,1 updateSchedule GoogleMapsStyle:default,silver,dark,night GoogleMapsSize GoogleMapsLocation GoogleMapsStroke GoogleMapsTrafficLayer:0,1 GoogleMapsDisableUI:0,1 " .
      $readingFnAttributes;  

    $data{FWEXT}{"/TRAFFIC"}{FUNC} = "TRAFFIC";
    $data{FWEXT}{"/TRAFFIC"}{FORKABLE} = 1; 

    $hash->{FW_detailFn} = "TRAFFIC_fhemwebFn";
}

sub TRAFFIC_Define($$){

    my ($hash, $allDefs) = @_;
    
    my @deflines = split('\n',$allDefs);
    my @apiDefs = split('[ \t]+', shift @deflines);
    
    if(int(@apiDefs) < 3) {
        return "too few parameters: 'define <name> TRAFFIC <APIKEY>'";
    }

    $hash->{NAME}    = $apiDefs[0];
    $hash->{APIKEY}  = $apiDefs[2];
    $hash->{VERSION} = $TRVersion;
    delete($hash->{BURSTCOUNT}) if $hash->{BURSTCOUNT};
    delete($hash->{BURSTINTERVAL}) if $hash->{BURSTINTERVAL};

    my $name = $hash->{NAME};

    #clear all readings
    foreach my $clearReading ( keys %{$hash->{READINGS}}){
        Log3 $hash, 5, "TRAFFIC: ($name) READING: $clearReading deleted";
        delete($hash->{READINGS}{$clearReading}); 
    }
    
    #clear all helpers
    foreach my $helperName ( keys %{$hash->{helper}}){
        delete($hash->{helper}{$helperName});
    }
    
    # clear weblink
    FW_fC("delete ".$name."_weblink");
    
    # basic update INTERVAL
    if(scalar(@apiDefs) > 3 && $apiDefs[3] =~ m/^\d+$/){
        $hash->{INTERVAL} = $apiDefs[3];
    }else{
        $hash->{INTERVAL} = 3600;
    }
    Log3 $hash, 4, "TRAFFIC: ($name) defined ".$hash->{NAME}.' with interval set to '.$hash->{INTERVAL};
    
    # put in default verbose level
    $attr{$name}{"verbose"} = 1 if !$attr{$name}{"verbose"};
    $attr{$name}{"outputReadings"} = "text" if !$attr{$name}{"outputReadings"};
    
    readingsSingleUpdate( $hash, "state", "Initialized", 1 );
    
    my $firstTrigger = gettimeofday() + 2;
    $hash->{TRIGGERTIME}     = $firstTrigger;
    $hash->{TRIGGERTIME_FMT} = FmtDateTime($firstTrigger);

    RemoveInternalTimer($hash);
    InternalTimer($firstTrigger, "TRAFFIC_StartUpdate", $hash, 0);
    Log3 $hash, 5, "TRAFFIC: ($name) InternalTimer set to call GetUpdate in 2 seconds for the first time";
    return undef;
}


sub TRAFFIC_Undef($$){      

    my ( $hash, $arg ) = @_;       
    RemoveInternalTimer ($hash);
    return undef;                  
}    

sub TRAFFIC_fhemwebFn($$$$) {
    my ($FW_wname, $device, $room, $pageHash) = @_; # pageHash is set for summaryFn.
    my $name = $device;
    my $hash = $defs{$name};

    my $mapState = ReadingsVal($device,".map", "off") eq "on" ? "off" : "on";
    my $web = "<span><a href=\"$FW_ME?detail=$device&amp;cmd.$device=setreading $device .map $mapState$FW_CSRF\">toggle Map</a>&nbsp;&nbsp;</span><br>";
    
    if (ReadingsVal($device,".map","off") eq "on") {
        $web .= TRAFFIC_GetMap($device);
        $web .= TRAFFIC_weblink($device);
    }
    return $web;
}

sub TRAFFIC_GetMap($@){
    my $device = shift();
    my $name = $device;
    my $hash = $defs{$name};
    
    my $debugPoly       = $hash->{helper}{'Poly'};
    my $returnDebugPoly = $hash->{helper}{'return_Poly'};
    my $GoogleMapsLocation = AttrVal($name, "GoogleMapsLocation", $hash->{helper}{'GoogleMapsLocation'});

    if(!$debugPoly || !$GoogleMapsLocation){
        return "<div>please update your map first</div>";
    }
    
    my%GoogleMapsStyles=(
        'default'   => "[]",
        'silver'    => '[{"elementType":"geometry","stylers":[{"color":"#f5f5f5"}]},{"elementType":"labels.icon","stylers":[{"visibility":"off"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#f5f5f5"}]},{"featureType":"administrative.land_parcel","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},{"featureType":"poi","elementType":"geometry","stylers":[{"color":"#eeeeee"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#e5e5e5"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},{"featureType":"road.arterial","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#dadada"}]},{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},{"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#e5e5e5"}]},{"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#eeeeee"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#c9c9c9"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]}]',
        'dark'      => '[{"elementType":"geometry","stylers":[{"color":"#212121"}]},{"elementType":"labels.icon","stylers":[{"visibility":"off"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#212121"}]},{"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#757575"}]},{"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},{"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},{"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#181818"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"poi.park","elementType":"labels.text.stroke","stylers":[{"color":"#1b1b1b"}]},{"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2c2c2c"}]},{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},{"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#373737"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3c3c3c"}]},{"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#4e4e4e"}]},{"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#000000"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d3d3d"}]}]',
        'night'     => '[{"elementType":"geometry","stylers":[{"color":"#242f3e"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},{"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#263c3f"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#6b9a76"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#38414e"}]},{"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#212a37"}]},{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5b3"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#746855"}]},{"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1f2835"}]},{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f3d19c"}]},{"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]},{"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]},{"featureType":"water","elementType":"labels.text.stroke","stylers":[{"color":"#17263c"}]}]',
    );
    my $selectedGoogleMapsStyle = $GoogleMapsStyles{ AttrVal($name, "GoogleMapsStyle", 'default' )};
    
    my ( $GoogleMapsWidth )   = AttrVal($name, "GoogleMapsSize", '800,600') =~ m/(\d+),\d+/;
    my ( $GoogleMapsHeight )  = AttrVal($name, "GoogleMapsSize", '800,600') =~ m/\d+,(\d+)/;
    my ( $GoogleMapsStroke1 ) = AttrVal($name, "GoogleMapsStroke", '#4cde44,#FF0000') =~ m/(#[a-zA-z0-9]+),#[a-zA-z0-9]+/;
    my ( $GoogleMapsStroke2 ) = AttrVal($name, "GoogleMapsStroke", '#4cde44,#FF0000') =~ m/#[a-zA-z0-9]+,(#[a-zA-z0-9]+)/;
    
    my $GoogleMapsDisableUI;
    $GoogleMapsDisableUI = "disableDefaultUI: true," if AttrVal($name, "GoogleMapsDisableUI", 0) eq 1;
    
    Log3 $hash, 4, "TRAFFIC: ($name) drawing map in style ".AttrVal($name, "GoogleMapsStyle", 'default' )." in $GoogleMapsWidth x $GoogleMapsHeight px";

    my $map;
    $map .= '<div><script type="text/javascript" src="https://maps.google.com/maps/api/js?key='.$hash->{APIKEY}.'&libraries=geometry&amp"></script>
        <input size="200" type="hidden" id="path" value="'.decode_base64($debugPoly).'">';
    $map .= '<input size="200" type="hidden" id="pathR" value="'.decode_base64($returnDebugPoly).'">' if decode_base64($returnDebugPoly);
    $map .= '
        <div id="map"></div>
        <style>
            #map {width:'.$GoogleMapsWidth.'px;height:'.$GoogleMapsHeight.'px;}
        </style>
        <script type="text/javascript">
        function initialize() {
            var myLatlng = new google.maps.LatLng('.$GoogleMapsLocation.');
            var myOptions = {
                zoom: 10,
                center: myLatlng,
                '.$GoogleMapsDisableUI.'
                mapTypeId: google.maps.MapTypeId.ROADMAP,
                styles: '.$selectedGoogleMapsStyle.'
            }
            var map = new google.maps.Map(document.getElementById("map"), myOptions);
            var decodedPath = google.maps.geometry.encoding.decodePath(document.getElementById("path").value); 
            var decodedLevels = decodeLevels("");
            var setRegion = new google.maps.Polyline({
                path: decodedPath,
                levels: decodedLevels,
                strokeColor: "'.$GoogleMapsStroke1.'",
                strokeOpacity: 1.0,
                strokeWeight: 6,
                map: map
            });';

    $map .= 'var decodedPathR = google.maps.geometry.encoding.decodePath(document.getElementById("pathR").value); 
            var decodedLevelsR = decodeLevels("");
            var setRegionR = new google.maps.Polyline({
                path: decodedPathR,
                levels: decodedLevels,
                strokeColor: "'.$GoogleMapsStroke2.'",
                strokeOpacity: 1.0,
                strokeWeight: 2,
                map: map
            });' if decode_base64($returnDebugPoly );

    $map .= 'var trafficLayer = new google.maps.TrafficLayer();
             trafficLayer.setMap(map);' if AttrVal($name, "GoogleMapsTrafficLayer", 0) eq 1;

    $map .='   
        }
        function decodeLevels(encodedLevelsString) {
            var decodedLevels = [];
            for (var i = 0; i < encodedLevelsString.length; ++i) {
                var level = encodedLevelsString.charCodeAt(i) - 63;
                decodedLevels.push(level);
            }
            return decodedLevels;
        }
        initialize();
        </script></div>';
        
    return $map;
}

  
#
# Attr command 
#########################################################################
sub TRAFFIC_Attr(@){

	my ($cmd,$name,$attrName,$attrValue) = @_;
    # $cmd can be "del" or "set" 
    # $name is device name
    my $hash = $defs{$name};

    if ($cmd eq "set") {        
        addToDevAttrList($name, $attrName);
        Log3 $hash, 4, "TRAFFIC: ($name)  attrName $attrName set to attrValue $attrValue";
    }
    if($attrName eq "disable" && $attrValue eq "1"){
        readingsSingleUpdate( $hash, "state", "disabled", 1 );
    }
    
    if($attrName eq "outputReadings" || $attrName eq "includeReturn" || $attrName eq "verbose"){
        #clear all readings
        foreach my $clearReading ( keys %{$hash->{READINGS}}){
            Log3 $hash, 5, "TRAFFIC: ($name) READING: $clearReading deleted";
            delete($hash->{READINGS}{$clearReading}); 
        }
        # start update
        InternalTimer(gettimeofday() + 1, "TRAFFIC_StartUpdate", $hash, 0); 
    }
    return undef;
}

sub TRAFFIC_Set($@){

	my ($hash, @param) = @_;
	return "\"set <TRAFFIC>\" needs at least one argument: \n".join(" ",keys %TRcmds) if (int(@param) < 2);

    my $name = shift @param;
	my $set = shift @param;
    
    $hash->{VERSION} = $TRVersion if $hash->{VERSION} ne $TRVersion;
    
    if(AttrVal($name, "disable", 0 ) == 1){
        readingsSingleUpdate( $hash, "state", "disabled", 1 );
        Log3 $hash, 3, "TRAFFIC: ($name) is disabled, $set not set!";
        return undef;
    }else{
        Log3 $hash, 5, "TRAFFIC: ($name) set $name $set";
    }
    
    my $validCmds = join("|",keys %TRcmds);
	if($set !~ m/$validCmds/ ) {
        return join(' ', keys %TRcmds);
	
    }elsif($set =~ m/update/){
        Log3 $hash, 5, "TRAFFIC: ($name) update command recieved";
        
        # if update burst ist specified
        if( (my $burstCount = shift @param) && (my $burstInterval = shift @param)){
            Log3 $hash, 5, "TRAFFIC: ($name) update burst is set to $burstCount $burstInterval";
            $hash->{BURSTCOUNT} = $burstCount;
            $hash->{BURSTINTERVAL} = $burstInterval;
        }else{
            Log3 $hash, 5, "TRAFFIC: ($name) no update burst set";
        }
        
        # update internal timer and update NOW
        my $updateTrigger = gettimeofday() + 1;
        $hash->{TRIGGERTIME}     = $updateTrigger;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($updateTrigger);
        RemoveInternalTimer($hash);

        # start update
        InternalTimer($updateTrigger, "TRAFFIC_StartUpdate", $hash, 0);            

        return undef;
    }

}


sub TRAFFIC_StartUpdate($){

    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    my ($sec,$min,$hour,$dayn,$month,$year,$wday,$yday,$isdst) = localtime(time);
    $wday=7 if $wday == 0; #sunday 0 -> sunday 7, monday 0 -> monday 1 ...


    if(AttrVal($name, "disable", 0 ) == 1){
        RemoveInternalTimer ($hash);
        Log3 $hash, 3, "TRAFFIC: ($name) is disabled";
        return undef;
    }
    if ( $hash->{INTERVAL}) {
        RemoveInternalTimer ($hash);
        delete($hash->{UPDATESCHEDULE});

        my $nextTrigger = gettimeofday() + $hash->{INTERVAL};
        
        if(defined(AttrVal($name, "updateSchedule", undef ))){
            Log3 $hash, 5, "TRAFFIC: ($name) flexible update Schedule defined";
            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
            my @updateScheduleDef = split('\|', AttrVal($name, "updateSchedule", undef ));
            foreach my $upSched (@updateScheduleDef){
                my ($upFrom, $upTo, $upDay, $upInterval ) = $upSched =~ m/(\d+)-(\d+)\s(\d{1,})\s?(\d{1,})?/;
                if (!$upInterval){
                    $upInterval = $upDay;
                    $upDay='';
                }
                Log3 $hash, 5, "TRAFFIC: ($name) parsed schedule to upFrom $upFrom, upTo $upTo, upDay $upDay, upInterval $upInterval";

                if(!$upFrom || !$upTo || !$upInterval){
                    Log3 $hash, 1, "TRAFIC: ($name) updateSchedule $upSched not defined correctly";
                }else{
                    if($hour >= $upFrom && $hour < $upTo){
                        if(!$upDay || $upDay == $wday ){
                            $nextTrigger = gettimeofday() + $upInterval;
                            Log3 $hash, 4, "TRAFFIC: ($name) schedule from $upFrom to $upTo (on day $upDay) every $upInterval seconds, matches (current hour $hour), nextTrigger set to $nextTrigger";
                            $hash->{UPDATESCHEDULE} = $upSched;
                            last;
                        }else{
                            Log3 $hash, 4, "TRAFFIC: ($name) $upSched does match the time but not the day ($wday)";
                        }
                    }else{
                        Log3 $hash, 5, "TRAFFIC: ($name) schedule $upSched does not match ($hour)";
                    }
                }
            }
        }
        
        if(defined($hash->{BURSTCOUNT}) && $hash->{BURSTCOUNT} > 0){
            $nextTrigger = gettimeofday() + $hash->{BURSTINTERVAL};
            Log3 $hash, 3, "TRAFFIC: ($name) next update defined by burst";
            $hash->{BURSTCOUNT}--;
        }elsif(defined($hash->{BURSTCOUNT}) && $hash->{BURSTCOUNT} == 0){
            delete($hash->{BURSTCOUNT});
            delete($hash->{BURSTINTERVAL});
            Log3 $hash, 4, "TRAFFIC: ($name) burst update is done";
        }
        
        $hash->{TRIGGERTIME}     = $nextTrigger;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextTrigger);
        InternalTimer($nextTrigger, "TRAFFIC_StartUpdate", $hash, 0);            
        Log3 $hash, 4, "TRAFFIC: ($name) internal interval timer set to call StartUpdate again at " . $hash->{TRIGGERTIME_FMT};
    }

    
    
    if(defined(AttrVal($name, "start_address", undef )) && defined(AttrVal($name, "end_address", undef ))){
        
        BlockingCall("TRAFFIC_DoUpdate",$hash->{NAME}.';;;normal',"TRAFFIC_FinishUpdate",60,"TRAFFIC_AbortUpdate",$hash);    
        
        if(defined(AttrVal($name, "includeReturn", undef )) && AttrVal($name, "includeReturn", undef ) eq 1){
            BlockingCall("TRAFFIC_DoUpdate",$hash->{NAME}.';;;return',"TRAFFIC_FinishUpdate",60,"TRAFFIC_AbortUpdate",$hash);    
        }
        
    }else{
        readingsSingleUpdate( $hash, "state", "incomplete configuration", 1 );
        Log3 $hash, 1, "TRAFFIC: ($name) is not configured correctly, please add start_address and end_address";
    }
}

sub TRAFFIC_AbortUpdate($){

}


sub TRAFFIC_DoUpdate(){

    my ($string) = @_;
    my ($hName, $direction) = split(";;;", $string); # direction is normal or return
    my $hash = $defs{$hName};

    my $dotrigger = 1; 
    my $name = $hash->{NAME};
    my ($sec,$min,$hour,$dayn,$month,$year,$wday,$yday,$isdst) = localtime(time);

    Log3 $hash, 4, "TRAFFIC: ($name) TRAFFIC_DoUpdate start";

    if ( $hash->{INTERVAL}) {
        RemoveInternalTimer ($hash);
        my $nextTrigger = gettimeofday() + $hash->{INTERVAL};
        $hash->{TRIGGERTIME}     = $nextTrigger;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextTrigger);
        InternalTimer($nextTrigger, "TRAFFIC_DoUpdate", $hash, 0);            
        Log3 $hash, 4, "TRAFFIC: ($name) internal interval timer set to call GetUpdate again in " . int($hash->{INTERVAL}). " seconds";
    }
    
    my $returnJSON;
    
    my $TRlanguage = '';
    if(defined(AttrVal($name,"language",undef))){
        $TRlanguage = '&language='.AttrVal($name,"language","");
    }else{
        Log3 $hash, 5, "TRAFFIC: ($name) no language specified";
    }

    my $TRwaypoints = ''; 
    if(defined(AttrVal($name,"waypoints",undef))){
        $TRwaypoints = '&waypoints=via:' . join('|via:', split('\|', AttrVal($name,"waypoints",undef)));
    }else{
        Log3 $hash, 4, "TRAFFIC: ($name) no waypoints specified";
    }
    if($direction eq "return"){
        if(defined(AttrVal($name,"returnWaypoints",undef))){
            $TRwaypoints = '&waypoints=via:' . join('|via:', split('\|', AttrVal($name,"returnWaypoints",undef)));
            Log3 $hash, 4, "TRAFFIC: ($name) using returnWaypoints";
        }elsif(defined(AttrVal($name,"waypoints",undef))){
            $TRwaypoints = '&waypoints=via:' . join('|via:', reverse split('\|', AttrVal($name,"waypoints",undef)));    
            Log3 $hash, 4, "TRAFFIC: ($name) reversing waypoints";
        }else{
            Log3 $hash, 4, "TRAFFIC: ($name) no waypoints for return specified";
        }
    }
    
    my $origin = AttrVal($name, "start_address", 0 );
    my $destination = AttrVal($name, "end_address", 0 );
    my $travelMode = AttrVal($name, "travelMode", 'driving' );
    
    if($direction eq "return"){
        $origin = AttrVal($name, "end_address", 0 );
        $destination = AttrVal($name, "start_address", 0 );
    }
    
    my $url = 'https://maps.googleapis.com/maps/api/directions/json?origin='.$origin.'&destination='.$destination.'&mode='.$travelMode.$TRlanguage.'&departure_time=now'.$TRwaypoints.'&key='.$hash->{APIKEY};
    Log3 $hash, 4, "TRAFFIC: ($name) using $url";
    
    my $ua = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0 } );
    $ua->default_header("HTTP_REFERER" => "www.google.de");
    my $body = $ua->get($url);
    my $json = decode_json($body->decoded_content);
    
    my $duration_sec            = $json->{'routes'}[0]->{'legs'}[0]->{'duration'}->{'value'} ;
    my $duration_in_traffic_sec = $json->{'routes'}[0]->{'legs'}[0]->{'duration_in_traffic'}->{'value'};

    $returnJSON->{'READINGS'}->{'duration'}               = $json->{'routes'}[0]->{'legs'}[0]->{'duration'}->{'text'}             if AttrVal($name, "outputReadings", "" ) =~ m/text/;
    $returnJSON->{'READINGS'}->{'duration_in_traffic'}    = $json->{'routes'}[0]->{'legs'}[0]->{'duration_in_traffic'}->{'text'}  if AttrVal($name, "outputReadings", "" ) =~ m/text/;
    $returnJSON->{'READINGS'}->{'distance'}               = $json->{'routes'}[0]->{'legs'}[0]->{'distance'}->{'text'}             if AttrVal($name, "outputReadings", "" ) =~ m/text/;
    $returnJSON->{'READINGS'}->{'state'}                  = $json->{'status'};
    $returnJSON->{'READINGS'}->{'status'}                 = $json->{'status'};
    $returnJSON->{'READINGS'}->{'eta'}                    = FmtTime( gettimeofday() + $duration_in_traffic_sec ) if defined($duration_in_traffic_sec); 
    
    $returnJSON->{'HELPER'}->{'Poly'}                     = encode_base64 ($json->{'routes'}[0]->{overview_polyline}->{points});
    $returnJSON->{'HELPER'}->{'GoogleMapsLocation'}       = $json->{'routes'}[0]->{'legs'}[0]->{start_location}->{lat}.','.$json->{'routes'}[0]->{'legs'}[0]->{start_location}->{lng};
    
    if($duration_in_traffic_sec && $duration_sec){
        $returnJSON->{'READINGS'}->{'delay'}              = prettySeconds($duration_in_traffic_sec - $duration_sec)  if AttrVal($name, "outputReadings", "" ) =~ m/text/;
        Log3 $hash, 4, "TRAFFIC: ($name) delay in seconds = $duration_in_traffic_sec - $duration_sec";
        
        if (AttrVal($name, "outputReadings", "" ) =~ m/min/ && defined($duration_in_traffic_sec) && defined($duration_sec)){
            $returnJSON->{'READINGS'}->{'delay_min'} = int($duration_in_traffic_sec - $duration_sec);
        }
        if(defined($returnJSON->{'READINGS'}->{'delay_min'})){
            if( ( $returnJSON->{'READINGS'}->{'delay_min'} && $returnJSON->{'READINGS'}->{'delay_min'} =~ m/^-/ ) || $returnJSON->{'READINGS'}->{'delay_min'} < 60){
                Log3 $hash, 5, "TRAFFIC: ($name) delay_min was negative or less than 1min (".$returnJSON->{'READINGS'}->{'delay_min'}."), set to 0";
                $returnJSON->{'READINGS'}->{'delay_min'} = 0;
            }else{
                $returnJSON->{'READINGS'}->{'delay_min'} = int($returnJSON->{'READINGS'}->{'delay_min'} / 60 + 0.5); #divide 60 and round
            }
        }
    }else{
        Log3 $hash, 1, "TRAFFIC: ($name) did not receive duration_in_traffic, not able to calculate delay";
        
    }
    
    # condition based values
    $returnJSON->{'READINGS'}->{'error_message'} = $json->{'error_message'} if $json->{'error_message'};
    # output readings
    $returnJSON->{'READINGS'}->{'duration_min'}               = int($duration_sec / 60  + 0.5)            if AttrVal($name, "outputReadings", "" ) =~ m/min/ && defined($duration_sec);
    $returnJSON->{'READINGS'}->{'duration_in_traffic_min'}    = int($duration_in_traffic_sec / 60  + 0.5) if AttrVal($name, "outputReadings", "" ) =~ m/min/ && defined($duration_in_traffic_sec);
    $returnJSON->{'READINGS'}->{'duration_sec'}               = $duration_sec                             if AttrVal($name, "outputReadings", "" ) =~ m/sec/; 
    $returnJSON->{'READINGS'}->{'duration_in_traffic_sec'}    = $duration_in_traffic_sec                  if AttrVal($name, "outputReadings", "" ) =~ m/sec/; 
    # raw data (seconds)
    $returnJSON->{'READINGS'}->{'distance'} = $json->{'routes'}[0]->{'legs'}[0]->{'distance'}->{'value'}  if AttrVal($name, "raw_data", 0);
    

    # average readings
    if(AttrVal($name, "outputReadings", "" ) =~ m/average/){
        
        # calc average
        $returnJSON->{'READINGS'}->{'average_duration_min'}               = int($hash->{READINGS}{'average_duration_min'}{VAL} + $returnJSON->{'READINGS'}->{'duration_min'}) / 2                        if $returnJSON->{'READINGS'}->{'duration_min'};
        $returnJSON->{'READINGS'}->{'average_duration_in_traffic_min'}    = int($hash->{READINGS}{'average_duration_in_traffic_min'}{VAL} + $returnJSON->{'READINGS'}->{'duration_in_traffic_min'}) / 2  if $returnJSON->{'READINGS'}->{'duration_in_traffic_min'};
        $returnJSON->{'READINGS'}->{'average_delay_min'}                  = int($hash->{READINGS}{'average_delay_min'}{VAL} + $returnJSON->{'READINGS'}->{'delay_min'}) / 2                              if $returnJSON->{'READINGS'}->{'delay_min'};
        
        # override if this is the first average
        $returnJSON->{'READINGS'}->{'average_duration_min'}               = $returnJSON->{'READINGS'}->{'duration_min'}             if !$hash->{READINGS}{'average_duration_min'}{VAL};
        $returnJSON->{'READINGS'}->{'average_duration_in_traffic_min'}    = $returnJSON->{'READINGS'}->{'duration_in_traffic_min'}  if !$hash->{READINGS}{'average_duration_in_traffic_min'}{VAL};
        $returnJSON->{'READINGS'}->{'average_delay_min'}                  = $returnJSON->{'READINGS'}->{'delay_min'}                if !$hash->{READINGS}{'average_delay_min'}{VAL};
    }
    
    
    Log3 $hash, 5, "TRAFFIC: ($name) returning from TRAFFIC_DoUpdate: ".encode_json($returnJSON);
    Log3 $hash, 4, "TRAFFIC: ($name) TRAFFIC_DoUpdate done";
    return "$name;;;$direction;;;".encode_json($returnJSON);
}

sub TRAFFIC_FinishUpdate($){
    my ($name,$direction,$rawJson) = split(/;;;/,shift);
    my $hash = $defs{$name};
    my %sensors;
    my $dotrigger = 1;

    Log3 $hash, 4, "TRAFFIC: ($name) TRAFFIC_FinishUpdate start";

    my $json = decode_json($rawJson);
    readingsBeginUpdate($hash);
    
    my $readings = $json->{'READINGS'};
    my $helper = $json->{'HELPER'};

    foreach my $helperName (keys %{$helper}){
        if($direction eq 'return'){
            Log3 $hash, 4, "TRAFFIC: ($name) HelperUpdate: return_".$helperName." - ".$helper->{$helperName};
            $hash->{helper}{'return_'.$helperName} = $helper->{$helperName}; #testme        
        }else{
            Log3 $hash, 4, "TRAFFIC: ($name) HelperUpdate: $helperName - ".$helper->{$helperName};
            $hash->{helper}{$helperName} = $helper->{$helperName}; #testme        
        }
    }
    
    foreach my $readingName (keys %{$readings}){
        Log3 $hash, 4, "TRAFFIC: ($name) ReadingsUpdate: $readingName - ".$readings->{$readingName};
        if($direction eq 'return'){
            readingsBulkUpdate($hash,'return_'.$readingName,$readings->{$readingName});
        }else{
            readingsBulkUpdate($hash,$readingName,$readings->{$readingName});
        }
    }
    
    if($json->{'status'} eq 'UNKNOWN_ERROR'){ # UNKNOWN_ERROR indicates a directions request could not be processed due to a server error. The request may succeed if you try again.
        InternalTimer(gettimeofday() + 3, "TRAFFIC_StartUpdate", $hash, 0); 
    }

    if(my $stateReading = AttrVal($name,"stateReading",undef)){
        Log3 $hash, 5, "TRAFFIC: ($name) stateReading defined, override state";
        if(defined($json->{$stateReading})){
            readingsBulkUpdate($hash,'state',$json->{$stateReading});
        }else{
            
            Log3 $hash, 1, "TRAFFIC: ($name) stateReading $stateReading not found";
        }
    }
    readingsEndUpdate($hash, $dotrigger);
    Log3 $hash, 1, "TRAFFIC: ($name) TRAFFIC_FinishUpdate done";
    Log3 $hash, 5, "TRAFFIC: ($name) Helper: ".Dumper($hash->{helper}); 
}

sub TRAFFIC_weblink{
    my $name = shift();
    return "<a href='$FW_ME/TRAFFIC?name=$name'>$FW_ME/TRAFFIC?name=$name</a><br>";
}

sub TRAFFIC(){
    my $name    = $FW_webArgs{name};
    return if(!defined($name));

    $FW_RETTYPE = "text/html; charset=UTF-8";
    $FW_RET="";

    my $web .= TRAFFIC_GetMap($name);

    FW_pO $web;
    return ($FW_RETTYPE, $FW_RET);
}

sub prettySeconds {
    my $time = shift;
    
    if($time =~ m/^-/){
        return "0 min";
    }
    my $days = int($time / 86400);
    $time -= ($days * 86400);
    my $hours = int($time / 3600);
    $time -= ($hours * 3600);
    my $minutes = int($time / 60);
    my $seconds = $time % 60;

    $days = $days < 1 ? '' : $days .' days ';
    $hours = $hours < 1 ? '' : $hours .' hours ';
    $minutes = $minutes < 1 ? '' : $minutes . ' min ';
    $time = $days . $hours . $minutes;
    if(!$time){
        return "0 min";
    }else{
        return $time;
    }
    
}


1;

#======================================================================
#======================================================================
#
# HTML Documentation for help and commandref
#
#======================================================================
#======================================================================
=pod
=item device
=item summary    provide traffic details with Google Distance API
=item summary_DE stellt Verkehrsdaten mittels Google Distance API bereit
=begin html

<a name="TRAFFIC"></a>
<h3>TRAFFIC</h3>
<ul>
  <u><b>TRAFFIC - google maps directions module</b></u>
  <br>
  <br>
  This FHEM module collects and displays data obtained via the google maps directions api<br>
  requirements:<br>
  perl JSON module<br>
  perl LWP::SIMPLE module<br>
  perl MIME::Base64 module<br>
  Google maps API key<br>
  <br>
    <b>Features:</b>
  <br>
  <ul>
    <li>get distance between start and end location</li>
    <li>get travel time for route</li>
    <li>get travel time in traffic for route</li>
    <li>define additional waypoints</li>
    <li>calculate delay between travel-time and travel-time-in-traffic</li>
    <li>choose default language</li>
    <li>disable the device</li>
    <li>5 log levels</li>
    <li>get outputs in seconds / meter (raw_data)</li>
    <li>state of google maps returned in error reading (i.e. The provided API key is invalid)</li>
    <li>customize update interval (default 3600 seconds)</li>
    <li>calculate ETA with localtime and delay</li>
    <li>configure the output readings with attribute outputReadings, text, min sec</li>
    <li>configure the state-reading </li>
    <li>optionally display the same route in return</li>
    <li>one-time-burst, specify the amount and interval between updates</li>
    <li>different Travel Modes (driving, walking, bicycling and transit)</li>
    <li>flexible update schedule</li>
    <li>integrated Map to visualize configured route at verbose 5</li>
  </ul>
  <br>
  <br>
  <a name="TRAFFICdefine"></a>
  <b>Define:</b>
  <ul><br>
    <code>define &lt;name&gt; TRAFFIC &lt;YOUR-API-KEY&gt; [UPDATE-INTERVAL]</code>
    <br><br>
    example:<br>
       <code>define muc2berlin TRAFFIC ABCDEFGHIJKLMNOPQRSTVWYZ 600</code><br>
  </ul>
  <br>
  <br>
  <b>Attributes:</b>
  <ul>
    <li>"start_address" - Street, zipcode City  <b>(mandatory)</b></li>
    <li>"end_address" -  Street, zipcode City <b>(mandatory)</b></li>
    <li>"raw_data" -  0:1</li>
    <li>"language" - de, en etc.</li>
    <li>"waypoints" - Lat, Long coordinates, separated by | </li>
    <li>"returnWaypoints" - Lat, Long coordinates, separated by | </li>
    <li>"disable" - 0:1</li>
    <li>"stateReading" - name the reading which will be used in device state</li>
    <li>"outputReadings" - define what kind of readings you want to get: text, min, sec, average</li>
    <li>"updateSchedule" - define a flexible update schedule, syntax &lt;starthour&gt;-&lt;endhour&gt; [&lt;day&gt;] &lt;seconds&gt; , multiple entries by sparated by |<br> <i>example:</i> 7-9 1 120 - Monday between 7 and 9 every 2minutes <br> <i>example:</i> 17-19 120 - every Day between 17 and 19 every 2minutes <br> <i>example:</i> 6-8 1 60|6-8 2 60|6-8 3 60|6-8 4 60|6-8 5 60 - Monday till Friday, 60 seconds between 6 and 8 am</li>
    <li>"travelMode" - default: driving, options walking, bicycling or transit </li>
    <li>"includeReturn" - 0:1</li>
  </ul>
  <br>
  <br>
  
  <a name="TRAFFICreadings"></a>
  <b>Readings:</b>
  <ul>
     <li>delay </li>
     <li>distance </li>
     <li>duration </li>
     <li>duration_in_traffic </li>
     <li>state </li>
     <li>eta</li>
     <li>delay_min</li>
     <li>duration_min</li>
     <li>duration_in_traffic_min</li>
     <li>error_message</li>
  </ul>
  <br><br>
  <a name="TRAFFICset"></a>
  <b>Set</b>
  <ul>
    <li>update [burst-update-count] [burst-update-interval] - update readings manually</li>
  </ul>
  <br><br>
</ul>


=end html
=cut

