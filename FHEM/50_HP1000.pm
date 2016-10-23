# $Id$
##############################################################################
#
#     50_HP1000.pm
#     An FHEM Perl module to receive data from HP1000 weather stations.
#
#     Copyright by Julian Pawlowski
#     e-mail: julian.pawlowski at gmail.com
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
use vars qw(%data);
use HttpUtils;
use UConv;
use Time::Local;
use List::Util qw(sum);
use FHEM::98_dewpoint;
use Data::Dumper;

#########################
sub HP1000_addExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = "/$link";
    Log3 $name, 2, "Registering HP1000 $name for URL $url...";
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;
}

#########################
sub HP1000_removeExtension($) {
    my ($link) = @_;

    my $url  = "/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    Log3 $name, 2, "Unregistering HP1000 $name for URL $url...";
    delete $data{FWEXT}{$url};
}

###################################
sub HP1000_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "HP1000_Initialize: Entering";

    $hash->{DefFn}         = "HP1000_Define";
    $hash->{UndefFn}       = "HP1000_Undefine";
    $hash->{DbLog_splitFn} = "HP1000_DbLog_split";
    $hash->{AttrList} =
      "wu_push:1,0 wu_id wu_password wu_realtime:1,0 wu_apikey extSrvPush_Url "
      . $readingFnAttributes;
}

###################################
sub HP1000_Define($$) {

    my ( $hash, $def ) = @_;

    my @a = split( "[ \t]+", $def, 5 );

    return "Usage: define <name> HP1000 [<ID> <PASSWORD>]"
      if ( int(@a) < 2 );
    my $name = $a[0];
    $hash->{ID}       = $a[2] if ( defined( $a[2] ) );
    $hash->{PASSWORD} = $a[3] if ( defined( $a[3] ) );

    return
        "Device already defined: "
      . $modules{HP1000}{defptr}{NAME}
      . " (there can only be one instance as per restriction of the weather station itself)"
      if ( defined( $modules{HP1000}{defptr} ) && !defined( $hash->{OLDDEF} ) );

    # check FHEMWEB instance
    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {
        my $FWports;
        foreach ( devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') ) {
            $hash->{FW} = $_
              if ( AttrVal( $_, "webname", "fhem" ) eq "weatherstation" );
            push( @{$FWports}, $defs{$_}->{PORT} )
              if ( defined( $defs{$_}->{PORT} ) );
        }

        if ( !defined( $hash->{FW} ) ) {
            $hash->{FW} = "WEBweatherstation";
            my $port = 8084;
            until ( !grep ( /^$port$/, @{$FWports} ) ) {
                $port++;
            }

            if ( !defined( $defs{ $hash->{FW} } ) ) {

                Log3 $name, 3,
                    "HP1000 $name: Creating new FHEMWEB instance "
                  . $hash->{FW}
                  . " with webname 'weatherstation'";

                fhem "define " . $hash->{FW} . " FHEMWEB $port global";
                fhem "attr " . $hash->{FW} . " webname weatherstation";
            }
        }

        $hash->{FW_PORT} = $defs{ $hash->{FW} }{PORT};
    }

    if ( HP1000_addExtension( $name, "HP1000_CGI", "updateweatherstation" ) ) {
        $hash->{fhem}{infix} = "updateweatherstation";
    }
    else {
        return "Error registering FHEMWEB infix";
    }

    # create global unique device definition
    $modules{HP1000}{defptr} = $hash;

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 120, "HP1000_SetAliveState", $hash, 0 );

    return undef;
}

###################################
sub HP1000_Undefine($$) {

    my ( $hash, $name ) = @_;

    HP1000_removeExtension( $hash->{fhem}{infix} );

    # release global unique device definition
    delete $modules{HP1000}{defptr};

    RemoveInternalTimer($hash);

    return undef;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

#####################################
sub HP1000_SetAliveState($;$) {
    my ( $hash, $alive ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "HP1000 $name: called function HP1000_SetAliveState()";
    RemoveInternalTimer($hash);

    my $activity = "dead";
    $activity = "alive" if ($alive);

    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged( $hash, "Activity", $activity );
    readingsEndUpdate( $hash, 1 );

    InternalTimer( gettimeofday() + 120, "HP1000_SetAliveState", $hash, 0 );

    return;
}

###################################
sub HP1000_CGI() {

    my ($request) = @_;

    my $hash;
    my $name = "";
    my $link;
    my $URI;
    my $result = "";
    my $webArgs;
    my $servertype;

    # incorrect FHEMWEB instance used
    if ( AttrVal( $FW_wname, "webname", "fhem" ) ne "weatherstation" ) {
        return ( "text/plain; charset=utf-8",
            "incorrect FHEMWEB instance to receive data" );
    }

    # data received
    elsif ( $request =~ /^\/updateweatherstation\.(\w{3})\?(.+=.+)/ ) {
        $servertype = lc($1);
        $URI        = $2;

        # get device name
        $name = $data{FWEXT}{"/updateweatherstation"}{deviceName}
          if ( defined( $data{FWEXT}{"/updateweatherstation"} ) );

        # return error if no such device
        return ( "text/plain; charset=utf-8",
            "No HP1000 device for webhook /updateweatherstation" )
          unless ($name);

        # extract values from URI
        foreach my $pv ( split( "&", $URI ) ) {
            next if ( $pv eq "" );
            $pv =~ s/\+/ /g;
            $pv =~ s/%([\dA-F][\dA-F])/chr(hex($1))/ige;
            my ( $p, $v ) = split( "=", $pv, 2 );

            $webArgs->{$p} = $v;
        }

        if (   !defined( $webArgs->{softwaretype} )
            || !defined( $webArgs->{dateutc} )
            || !defined( $webArgs->{ID} )
            || !defined( $webArgs->{PASSWORD} )
            || !defined( $webArgs->{action} ) )
        {
            Log3 $name, 5,
              "HP1000: received insufficient data:\n" . Dumper($webArgs);

            return ( "text/plain; charset=utf-8", "Insufficient data" );
        }
    }

    # no data received
    else {
        return ( "text/plain; charset=utf-8", "Missing data" );
    }

    $hash = $defs{$name};

    HP1000_SetAliveState( $hash, 1 );

    $hash->{IP}          = $defs{$FW_cname}{PEER};
    $hash->{SERVER_TYPE} = $servertype;
    $hash->{SWVERSION}   = $webArgs->{softwaretype};
    $hash->{INTERVAL}    = (
        $hash->{SYSTEMTIME_UTC}
        ? time_str2num( $webArgs->{dateutc} ) -
          time_str2num( $hash->{SYSTEMTIME_UTC} )
        : 0
    );
    $hash->{SYSTEMTIME_UTC} = $webArgs->{dateutc};
    $hash->{FW}             = "";
    $hash->{FW_PORT}        = "";

    foreach ( devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') ) {
        if ( AttrVal( $_, "webname", "fhem" ) eq "weatherstation" ) {
            $hash->{FW}      = $_;
            $hash->{FW_PORT} = $defs{$_}{PORT};
            last;
        }
    }

    if (
           defined( $hash->{ID} )
        && defined( $hash->{PASSWORD} )
        && (   $hash->{ID} ne $webArgs->{ID}
            || $hash->{PASSWORD} ne $webArgs->{PASSWORD} )
      )
    {
        Log3 $name, 4, "HP1000: received data containing wrong credentials:\n"
          . Dumper($webArgs);
        return ( "text/plain; charset=utf-8", "Wrong credentials" );
    }

    Log3 $name, 5, "HP1000: received data:\n" . Dumper($webArgs);

    # rename wind speed values as those are in m/sec and
    # we want km/h to be our metric default
    if ( defined( $webArgs->{windspeed} ) ) {
        $webArgs->{windspeedmps} = $webArgs->{windspeed};
        delete $webArgs->{windspeed};
    }
    if ( defined( $webArgs->{windgust} ) ) {
        $webArgs->{windgustmps} = $webArgs->{windgust};
        delete $webArgs->{windgust};
    }

    # calculate readings for Metric standard from Angloamerican standard
    #

    # humidity (special case here!)
    $webArgs->{inhumi} = $webArgs->{indoorhumidity}
      if ( defined( $webArgs->{indoorhumidity} )
        && !defined( $webArgs->{inhumi} ) );

    $webArgs->{indoorhumidity} = $webArgs->{inhumi}
      if ( defined( $webArgs->{inhumi} )
        && !defined( $webArgs->{indoorhumidity} ) );

    $webArgs->{outhumi} = $webArgs->{humidity}
      if ( defined( $webArgs->{humidity} )
        && !defined( $webArgs->{outhumi} ) );

    $webArgs->{humidity} = $webArgs->{outhumi}
      if ( defined( $webArgs->{outhumi} )
        && !defined( $webArgs->{humidity} ) );

    # dewpoint in Celsius (convert from dewptf)
    if (   defined( $webArgs->{dewptf} )
        && $webArgs->{dewptf} ne ""
        && !defined( $webArgs->{dewpoint} ) )
    {
        $webArgs->{dewpoint} =
          UConv::f2c( $webArgs->{dewptf} );
    }

    # relbaro in hPa (convert from baromin)
    if (   defined( $webArgs->{baromin} )
        && $webArgs->{baromin} ne ""
        && !defined( $webArgs->{relbaro} ) )
    {
        $webArgs->{relbaro} = UConv::inhg2hpa( $webArgs->{baromin} );
    }

    # absbaro in hPa (convert from absbaromin)
    if (   defined( $webArgs->{absbaromin} )
        && $webArgs->{absbaromin} ne ""
        && !defined( $webArgs->{absbaro} ) )
    {
        $webArgs->{absbaro} =
          UConv::inhg2hpa( $webArgs->{absbaromin} );
    }

    # rainrate in mm/h (convert from rainin)
    if (   defined( $webArgs->{rainin} )
        && $webArgs->{rainin} ne ""
        && !defined( $webArgs->{rainrate} ) )
    {
        $webArgs->{rainrate} = UConv::in2mm( $webArgs->{rainin} );
    }

    # dailyrain in mm (convert from dailyrainin)
    if (   defined( $webArgs->{dailyrainin} )
        && $webArgs->{dailyrainin} ne ""
        && !defined( $webArgs->{dailyrain} ) )
    {
        $webArgs->{dailyrain} =
          UConv::in2mm( $webArgs->{dailyrainin} );
    }

    # weeklyrain in mm (convert from weeklyrainin)
    if (   defined( $webArgs->{weeklyrainin} )
        && $webArgs->{weeklyrainin} ne ""
        && !defined( $webArgs->{weeklyrain} ) )
    {
        $webArgs->{weeklyrain} =
          UConv::in2mm( $webArgs->{weeklyrainin} );
    }

    # monthlyrain in mm (convert from monthlyrainin)
    if (   defined( $webArgs->{monthlyrainin} )
        && $webArgs->{monthlyrainin} ne ""
        && !defined( $webArgs->{monthlyrain} ) )
    {
        $webArgs->{monthlyrain} =
          UConv::in2mm( $webArgs->{monthlyrainin} );
    }

    # yearlyrain in mm (convert from yearlyrainin)
    if (   defined( $webArgs->{yearlyrainin} )
        && $webArgs->{yearlyrainin} ne ""
        && !defined( $webArgs->{yearlyrain} ) )
    {
        $webArgs->{yearlyrain} =
          UConv::in2mm( $webArgs->{yearlyrainin} );
    }

    # outtemp in Celsius (convert from tempf)
    if (   defined( $webArgs->{tempf} )
        && $webArgs->{tempf} ne ""
        && !defined( $webArgs->{outtemp} ) )
    {
        $webArgs->{outtemp} =
          UConv::f2c( $webArgs->{tempf} );
    }

    # intemp in Celsius (convert from indoortempf)
    if (   defined( $webArgs->{indoortempf} )
        && $webArgs->{indoortempf} ne ""
        && !defined( $webArgs->{intemp} ) )
    {
        $webArgs->{intemp} =
          UConv::f2c( $webArgs->{indoortempf} );
    }

    # windchill in Celsius (convert from windchillf)
    if (   defined( $webArgs->{windchillf} )
        && $webArgs->{windchillf} ne ""
        && !defined( $webArgs->{windchill} ) )
    {
        $webArgs->{windchill} =
          UConv::f2c( $webArgs->{windchillf} );
    }

    # windgust in km/h (convert from windgustmph)
    if (   defined( $webArgs->{windgustmph} )
        && $webArgs->{windgustmph} ne ""
        && !defined( $webArgs->{windgust} ) )
    {
        $webArgs->{windgust} =
          UConv::mph2kph( $webArgs->{windgustmph} );
    }

    # windspeed in km/h (convert from windspdmph)
    if (   defined( $webArgs->{windspdmph} )
        && $webArgs->{windspdmph} ne ""
        && !defined( $webArgs->{windspeed} ) )
    {
        $webArgs->{windspeed} =
          UConv::mph2kph( $webArgs->{windspdmph} );
    }

    # calculate readings for Angloamerican standard from Metric standard
    #

    # humidity (special case here!)
    $webArgs->{indoorhumidity} = $webArgs->{inhumi}
      if ( defined( $webArgs->{inhumi} )
        && !defined( $webArgs->{indoorhumidity} ) );

    # dewptf in Fahrenheit (convert from dewpoint)
    if (   defined( $webArgs->{dewpoint} )
        && $webArgs->{dewpoint} ne ""
        && !defined( $webArgs->{dewptf} ) )
    {
        $webArgs->{dewptf} =
          UConv::c2f( $webArgs->{dewpoint} );
    }

    # baromin in inch (convert from relbaro)
    if (   defined( $webArgs->{relbaro} )
        && $webArgs->{relbaro} ne ""
        && !defined( $webArgs->{baromin} ) )
    {
        $webArgs->{baromin} = UConv::hpa2inhg( $webArgs->{relbaro} );
    }

    # absbaromin in inch (convert from absbaro)
    if (   defined( $webArgs->{absbaro} )
        && $webArgs->{absbaro} ne ""
        && !defined( $webArgs->{absbaromin} ) )
    {
        $webArgs->{absbaromin} =
          UConv::hpa2inhg( $webArgs->{absbaro} );
    }

    # rainin in in/h (convert from rainrate)
    if (   defined( $webArgs->{rainrate} )
        && $webArgs->{rainrate} ne ""
        && !defined( $webArgs->{rainin} ) )
    {
        $webArgs->{rainin} = UConv::mm2in( $webArgs->{rainrate} );
    }

    # dailyrainin in inch (convert from dailyrain)
    if (   defined( $webArgs->{dailyrain} )
        && $webArgs->{dailyrain} ne ""
        && !defined( $webArgs->{dailyrainin} ) )
    {
        $webArgs->{dailyrainin} =
          UConv::mm2in( $webArgs->{dailyrain} );
    }

    # weeklyrainin in inch (convert from weeklyrain)
    if (   defined( $webArgs->{weeklyrain} )
        && $webArgs->{weeklyrain} ne ""
        && !defined( $webArgs->{weeklyrainin} ) )
    {
        $webArgs->{weeklyrainin} =
          UConv::mm2in( $webArgs->{weeklyrain} );
    }

    # monthlyrainin in inch (convert from monthlyrain)
    if (   defined( $webArgs->{monthlyrain} )
        && $webArgs->{monthlyrain} ne ""
        && !defined( $webArgs->{monthlyrainin} ) )
    {
        $webArgs->{monthlyrainin} =
          UConv::mm2in( $webArgs->{monthlyrain} );
    }

    # yearlyrainin in inch (convert from yearlyrain)
    if (   defined( $webArgs->{yearlyrain} )
        && $webArgs->{yearlyrain} ne ""
        && !defined( $webArgs->{yearlyrainin} ) )
    {
        $webArgs->{yearlyrainin} =
          UConv::mm2in( $webArgs->{yearlyrain} );
    }

    #  tempf in Fahrenheit (convert from outtemp)
    if (   defined( $webArgs->{outtemp} )
        && $webArgs->{outtemp} ne ""
        && !defined( $webArgs->{tempf} ) )
    {
        $webArgs->{tempf} =
          UConv::c2f( $webArgs->{outtemp} );
    }

    # indoortempf in Fahrenheit (convert from intemp)
    if (   defined( $webArgs->{intemp} )
        && $webArgs->{intemp} ne ""
        && !defined( $webArgs->{indoortempf} ) )
    {
        $webArgs->{indoortempf} =
          UConv::c2f( $webArgs->{intemp} );
    }

    # windchillf in Fahrenheit (convert from windchill)
    if (   defined( $webArgs->{windchill} )
        && $webArgs->{windchill} ne ""
        && !defined( $webArgs->{windchillf} ) )
    {
        $webArgs->{windchillf} =
          UConv::c2f( $webArgs->{windchill} );
    }

    # windgustmps in m/s (convert from windgust)
    if (   defined( $webArgs->{windgust} )
        && $webArgs->{windgust} ne ""
        && !defined( $webArgs->{windgustmps} ) )
    {
        $webArgs->{windgustmps} =
          UConv::kph2mps( $webArgs->{windgust} );
    }

    # windgust in km/h (convert from windgustmps,
    # not exactly from angloamerican...)
    if (   defined( $webArgs->{windgustmps} )
        && $webArgs->{windgustmps} ne ""
        && !defined( $webArgs->{windgust} ) )
    {
        $webArgs->{windgust} =
          UConv::mps2kph( $webArgs->{windgustmps} );
    }

    # windgustmph in mph (convert from windgust)
    if (   defined( $webArgs->{windgust} )
        && $webArgs->{windgust} ne ""
        && !defined( $webArgs->{windgustmph} ) )
    {
        $webArgs->{windgustmph} =
          UConv::kph2mph( $webArgs->{windgust} );
    }

    # windspeedmps in m/s (convert from windspeed,
    # not exactly from angloamerican...)
    if (   defined( $webArgs->{windspeed} )
        && $webArgs->{windspeed} ne ""
        && !defined( $webArgs->{windspeedmps} ) )
    {
        $webArgs->{windspeedmps} =
          UConv::kph2mps( $webArgs->{windspeed} );
    }

    # windspeed in km/h (convert from windspeedmps)
    if (   defined( $webArgs->{windspeedmps} )
        && $webArgs->{windspeedmps} ne ""
        && !defined( $webArgs->{windspeed} ) )
    {
        $webArgs->{windspeed} =
          UConv::mps2kph( $webArgs->{windspeedmps} );
    }

    # windspdmph in mph (convert from windspeed)
    if (   defined( $webArgs->{windspeed} )
        && $webArgs->{windspeed} ne ""
        && !defined( $webArgs->{windspdmph} ) )
    {
        $webArgs->{windspdmph} =
          UConv::kph2mph( $webArgs->{windspeed} );
    }

    # write general readings
    #
    readingsBeginUpdate($hash);

    while ( ( my $p, my $v ) = each %$webArgs ) {

        # delete empty values
        if ( $v eq "" ) {
            delete $webArgs->{$p};
            next;
        }

        # ignore those values
        next
          if ( $p eq "dateutc"
            || $p eq "action"
            || $p eq "softwaretype"
            || $p eq "realtime"
            || $p eq "rtfreq"
            || $p eq "humidity"
            || $p eq "indoorhumidity"
            || $p eq "ID"
            || $p eq "PASSWORD" );

        $p = "_" . $p;

        # name translation for general readings
        $p = "humidity"       if ( $p eq "_outhumi" );
        $p = "humidityIndoor" if ( $p eq "_inhumi" );
        $p = "luminosity"     if ( $p eq "_light" );
        $p = "uv"             if ( $p eq "_UV" );
        $p = "windDir"        if ( $p eq "_winddir" );

        # name translation for Metric standard
        $p = "dewpoint"          if ( $p eq "_dewpoint" );
        $p = "pressure"          if ( $p eq "_relbaro" );
        $p = "pressureAbs"       if ( $p eq "_absbaro" );
        $p = "rain"              if ( $p eq "_rainrate" );
        $p = "rainDay"           if ( $p eq "_dailyrain" );
        $p = "rainWeek"          if ( $p eq "_weeklyrain" );
        $p = "rainMonth"         if ( $p eq "_monthlyrain" );
        $p = "rainYear"          if ( $p eq "_yearlyrain" );
        $p = "temperature"       if ( $p eq "_outtemp" );
        $p = "temperatureIndoor" if ( $p eq "_intemp" );
        $p = "windChill"         if ( $p eq "_windchill" );
        $p = "windGust"          if ( $p eq "_windgust" );
        $p = "windGustMps"       if ( $p eq "_windgustmps" );
        $p = "windSpeed"         if ( $p eq "_windspeed" );
        $p = "windSpeedMps"      if ( $p eq "_windspeedmps" );

        # name translation for Angloamerican standard
        $p = "dewpointF"          if ( $p eq "_dewptf" );
        $p = "pressureIn"         if ( $p eq "_baromin" );
        $p = "pressureAbsIn"      if ( $p eq "_absbaromin" );
        $p = "rainIn"             if ( $p eq "_rainin" );
        $p = "rainDayIn"          if ( $p eq "_dailyrainin" );
        $p = "rainWeekIn"         if ( $p eq "_weeklyrainin" );
        $p = "rainMonthIn"        if ( $p eq "_monthlyrainin" );
        $p = "rainYearIn"         if ( $p eq "_yearlyrainin" );
        $p = "temperatureF"       if ( $p eq "_tempf" );
        $p = "temperatureIndoorF" if ( $p eq "_indoortempf" );
        $p = "windChillF"         if ( $p eq "_windchillf" );
        $p = "windGustMph"        if ( $p eq "_windgustmph" );
        $p = "windSpeedMph"       if ( $p eq "_windspdmph" );

        readingsBulkUpdate( $hash, $p, $v );
    }

    # calculate additional readings
    #

    # israining
    my $israining = 0;
    $israining = 1
      if ( defined( $webArgs->{rainrate} ) && $webArgs->{rainrate} > 0 );
    readingsBulkUpdateIfChanged( $hash, "israining", $israining );

    # daylight
    my $daylight = 0;
    $daylight = 1
      if ( defined( $webArgs->{light} ) && $webArgs->{light} > 50 );
    readingsBulkUpdateIfChanged( $hash, "daylight", $daylight );

    # weatherCondition
    if ( defined( $webArgs->{light} ) ) {
        my $condition = "clear";

        if ($israining) {
            $condition = "rain";
        }
        elsif ( $webArgs->{light} > 40000 ) {
            $condition = "sunny";
        }
        elsif ($daylight) {
            $condition = "cloudy";
        }

        readingsBulkUpdateIfChanged( $hash, "weatherCondition", $condition );
    }

    # humidityCondition
    if ( defined( $webArgs->{outhumi} ) ) {
        my $condition = "dry";

        if ( $webArgs->{outhumi} >= 80 && $israining ) {
            $condition = "rain";
        }
        elsif ( $webArgs->{outhumi} >= 80 ) {
            $condition = "wet";
        }
        elsif ( $webArgs->{outhumi} >= 70 ) {
            $condition = "high";
        }
        elsif ( $webArgs->{outhumi} >= 50 ) {
            $condition = "optimal";
        }
        elsif ( $webArgs->{outhumi} >= 40 ) {
            $condition = "low";
        }

        readingsBulkUpdateIfChanged( $hash, "humidityCondition", $condition );
    }

    # humidityIndoorCondition
    if ( defined( $webArgs->{inhumi} ) ) {
        my $condition = "dry";

        if ( $webArgs->{inhumi} >= 80 ) {
            $condition = "wet";
        }
        elsif ( $webArgs->{inhumi} >= 70 ) {
            $condition = "high";
        }
        elsif ( $webArgs->{inhumi} >= 50 ) {
            $condition = "optimal";
        }
        elsif ( $webArgs->{inhumi} >= 40 ) {
            $condition = "low";
        }

        readingsBulkUpdateIfChanged( $hash, "humidityIndoorCondition",
            $condition );
    }

    # UVI (convert from uW/cm2)
    if ( defined( $webArgs->{UV} ) ) {
        $webArgs->{UVI} = UConv::uwpscm2uvi( $webArgs->{UV} );
        readingsBulkUpdate( $hash, "uvIndex", $webArgs->{UVI} );
    }

    # uvCondition
    if ( defined( $webArgs->{UVI} ) ) {
        my $condition = "low";

        if ( $webArgs->{UVI} > 11 ) {
            $condition = "extreme";
        }
        elsif ( $webArgs->{UVI} > 8 ) {
            $condition = "veryhigh";
        }
        elsif ( $webArgs->{UVI} > 6 ) {
            $condition = "high";
        }
        elsif ( $webArgs->{UVI} > 3 ) {
            $condition = "moderate";
        }

        readingsBulkUpdateIfChanged( $hash, "uvCondition", $condition );
    }

    # solarradiation in W/m2 (convert from lux)
    if ( defined( $webArgs->{light} ) ) {
        $webArgs->{solarradiation} =
          UConv::lux2wpsm( $webArgs->{light} );
        readingsBulkUpdate( $hash, "solarradiation",
            $webArgs->{solarradiation} );
    }

    # pressureMm in mmHg (convert from hpa)
    if ( defined( $webArgs->{relbaro} ) ) {
        $webArgs->{barommm} = UConv::hpa2mmhg( $webArgs->{relbaro} );
        readingsBulkUpdate( $hash, "pressureMm", $webArgs->{barommm} );
    }

    # pressureAbsMm in mmHg (convert from hpa)
    if ( defined( $webArgs->{absbaro} ) ) {
        $webArgs->{absbarommm} =
          UConv::hpa2mmhg( $webArgs->{absbaro} );
        readingsBulkUpdate( $hash, "pressureAbsMm", $webArgs->{absbarommm} );
    }

    # dewpointIndoor in Celsius
    if ( defined( $webArgs->{intemp} ) && defined( $webArgs->{inhumi} ) ) {
        my $h = (
            $webArgs->{inhumi} > 110
            ? 110
            : ( $webArgs->{inhumi} <= 0 ? 0.01 : $webArgs->{inhumi} )
        );
        $webArgs->{indewpoint} =
          round( dewpoint_dewpoint( $webArgs->{intemp}, $h ), 1 );
        readingsBulkUpdate( $hash, "dewpointIndoor", $webArgs->{indewpoint} );
    }

    # dewpointIndoor in Fahrenheit
    if (   defined( $webArgs->{indoortempf} )
        && defined( $webArgs->{indoorhumidity} ) )
    {
        my $h = (
            $webArgs->{indoorhumidity} > 110 ? 110
            : (
                  $webArgs->{indoorhumidity} <= 0 ? 0.01
                : $webArgs->{indoorhumidity}
            )
        );
        $webArgs->{indoordewpointf} =
          round( dewpoint_dewpoint( $webArgs->{indoortempf}, $h ), 1 );
        readingsBulkUpdate( $hash, "dewpointIndoorF",
            $webArgs->{indoordewpointf} );
    }

    # humidityAbs / humidityAbsF
    if ( defined( $webArgs->{outtemp} ) && defined( $webArgs->{outhumi} ) ) {
        my $h = (
            $webArgs->{outhumi} > 110
            ? 110
            : ( $webArgs->{outhumi} <= 0 ? 0.01 : $webArgs->{outhumi} )
        );
        $webArgs->{outhumiabs} =
          round( dewpoint_absFeuchte( $webArgs->{outtemp}, $h ), 1 );
        readingsBulkUpdate( $hash, "humidityAbs", $webArgs->{outhumiabs} );

        $webArgs->{outhumiabsf} =
          round( dewpoint_absFeuchte( $webArgs->{outtempf}, $h ), 1 );
        readingsBulkUpdate( $hash, "humidityAbsF", $webArgs->{outhumiabsf} );
    }

    # humidityIndoorAbs
    if ( defined( $webArgs->{intemp} ) && defined( $webArgs->{inhumi} ) ) {
        my $h = (
            $webArgs->{inhumi} > 110
            ? 110
            : ( $webArgs->{inhumi} <= 0 ? 0.01 : $webArgs->{inhumi} )
        );
        $webArgs->{inhumiabs} =
          round( dewpoint_absFeuchte( $webArgs->{intemp}, $h ), 1 );
        readingsBulkUpdate( $hash, "humidityIndoorAbs", $webArgs->{inhumiabs} );
    }

    # humidityIndoorAbsF
    if (   defined( $webArgs->{indoortempf} )
        && defined( $webArgs->{indoorhumidity} ) )
    {
        my $h = (
            $webArgs->{indoorhumidity} > 110 ? 110
            : (
                  $webArgs->{indoorhumidity} <= 0 ? 0.01
                : $webArgs->{indoorhumidity}
            )
        );
        $webArgs->{indoorhumidityabsf} =
          round( dewpoint_absFeuchte( $webArgs->{indoortempf}, $h ), 1 );
        readingsBulkUpdate( $hash, "humidityIndoorAbsF",
            $webArgs->{indoorhumidityabsf} );
    }

    # windCompasspoint
    if ( defined( $webArgs->{winddir} ) ) {
        $webArgs->{windcompasspoint} =
          UConv::degrees2compasspoint( $webArgs->{winddir} );
        readingsBulkUpdate( $hash, "windCompasspoint",
            $webArgs->{windcompasspoint} );
    }

    # windSpeedBft in Beaufort (convert from km/h)
    if ( defined( $webArgs->{windspeed} ) ) {
        $webArgs->{windspeedbft} =
          UConv::kph2bft( $webArgs->{windspeed} );
        readingsBulkUpdate( $hash, "windSpeedBft", $webArgs->{windspeedbft} );
    }

    # windSpeedKn in kn (convert from km/h)
    if ( defined( $webArgs->{windspeed} ) ) {
        my $v = UConv::kph2kn( $webArgs->{windspeed} );
        $webArgs->{windspeedkn} = ( $v > 0.5 ? round( $v, 1 ) : "0.0" );
        readingsBulkUpdate( $hash, "windSpeedKn", $webArgs->{windspeedkn} );
    }

    # windSpeedFts in ft/s (convert from mph)
    if ( defined( $webArgs->{windspeedmph} ) ) {
        my $v = UConv::mph2fts( $webArgs->{windspeedmph} );
        $webArgs->{windspeedfts} = ( $v > 0.5 ? round( $v, 1 ) : "0.0" );
        readingsBulkUpdate( $hash, "windSpeedFts", $webArgs->{windspeedfts} );
    }

    # windGustBft in Beaufort (convert from km/h)
    if ( defined( $webArgs->{windgust} ) ) {
        $webArgs->{windgustbft} =
          UConv::kph2bft( $webArgs->{windgust} );
        readingsBulkUpdate( $hash, "windGustBft", $webArgs->{windgustbft} );
    }

    # windGustKn in m/s (convert from km/h)
    if ( defined( $webArgs->{windgust} ) ) {
        my $v = UConv::kph2kn( $webArgs->{windgust} );
        $webArgs->{windgustkn} = ( $v > 0.5 ? round( $v, 1 ) : "0.0" );
        readingsBulkUpdate( $hash, "windGustKn", $webArgs->{windgustkn} );
    }

    # windGustFts ft/s (convert from mph)
    if ( defined( $webArgs->{windgustmph} ) ) {
        my $v = UConv::mph2fts( $webArgs->{windgustmph} );
        $webArgs->{windgustfts} = ( $v > 0.5 ? round( $v, 1 ) : "0.0" );
        readingsBulkUpdate( $hash, "windGustFts", $webArgs->{windgustfts} );
    }

    # averages/windDir_avg2m
    if ( defined( $webArgs->{winddir} ) ) {
        my $v = sprintf( '%0.0f',
            HP1000_GetAvg( $hash, "winddir", 2 * 60, $webArgs->{winddir} ) );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "windDir_avg2m", $v );
            $webArgs->{winddir_avg2m} = $v;
        }
    }

    # averages/windCompasspoint_avg2m
    if ( defined( $webArgs->{winddir_avg2m} ) ) {
        $webArgs->{windcompasspoint_avg2m} =
          UConv::degrees2compasspoint( $webArgs->{winddir_avg2m} );
        readingsBulkUpdate( $hash, "windCompasspoint_avg2m",
            $webArgs->{windcompasspoint_avg2m} );
    }

    # averages/windSpeed_avg2m in km/h
    if ( defined( $webArgs->{windspeed} ) ) {
        my $v =
          HP1000_GetAvg( $hash, "windspeed", 2 * 60, $webArgs->{windspeed} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "windSpeed_avg2m", $v );
            $webArgs->{windspeed_avg2m} = $v;
        }
    }

    # averages/windSpeedMph_avg2m in mph
    if ( defined( $webArgs->{windspdmph} ) ) {
        my $v =
          HP1000_GetAvg( $hash, "windspdmph", 2 * 60, $webArgs->{windspdmph} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "windSpeedMph_avg2m", $v );
            $webArgs->{windspdmph_avg2m} = $v;
        }
    }

    # averages/windSpeedBft_avg2m in Beaufort (convert from km/h)
    if ( defined( $webArgs->{windspeed_avg2m} ) ) {
        $webArgs->{windspeedbft_avg2m} =
          UConv::kph2bft( $webArgs->{windspeed_avg2m} );
        readingsBulkUpdate( $hash, "windSpeedBft_avg2m",
            $webArgs->{windspeedbft_avg2m} );
    }

    # averages/windSpeedKn_avg2m in Kn (convert from km/h)
    if ( defined( $webArgs->{windspeed_avg2m} ) ) {
        $webArgs->{windspeedkn_avg2m} =
          UConv::kph2kn( $webArgs->{windspeed_avg2m} );
        readingsBulkUpdate( $hash, "windSpeedKn_avg2m",
            $webArgs->{windspeedkn_avg2m} );
    }

    # averages/windSpeedMps_avg2m in m/s
    if ( defined( $webArgs->{windspeed_avg2m} ) ) {
        my $v = UConv::kph2mps( $webArgs->{windspeed_avg2m} );
        $webArgs->{windspeedmps_avg2m} =
          ( $v > 0.5 ? round( $v, 1 ) : "0.0" );
        readingsBulkUpdate( $hash, "windSpeedMps_avg2m",
            $webArgs->{windspeedmps_avg2m} );
    }

    # averages/windGust_sum10m
    if ( defined( $webArgs->{windgust} ) ) {
        my $v =
          HP1000_GetSum( $hash, "windgust", 10 * 60, $webArgs->{windgust} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "windGust_sum10m", $v );
            $webArgs->{windgust_10m} = $v;
        }
    }

    # averages/windGustMph_sum10m
    if ( defined( $webArgs->{windgustmph} ) ) {
        my $v =
          HP1000_GetSum( $hash, "windgustmph", 10 * 60,
            $webArgs->{windgustmph} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "windGustMph_sum10m", $v );
            $webArgs->{windgustmph_10m} = $v;
        }
    }

    # from WU API - can we somehow calculate these as well?
    # weather - [text] -- metar style (+RA)
    # clouds - [text] -- SKC, FEW, SCT, BKN, OVC
    # soiltempf - [F soil temperature]
    # soilmoisture - [%]
    # leafwetness  - [%]
    # visibility - [nm visibility]
    # condition_forecast (based on pressure trend)
    # dayNight
    # soilTemperature
    # brightness in % ??

    $result = "T: " . $webArgs->{outtemp}
      if ( defined( $webArgs->{outtemp} ) );
    $result .= " H: " . $webArgs->{outhumi}
      if ( defined( $webArgs->{outhumi} ) );
    $result .= " Ti: " . $webArgs->{intemp}
      if ( defined( $webArgs->{intemp} ) );
    $result .= " Hi: " . $webArgs->{inhumi}
      if ( defined( $webArgs->{inhumi} ) );
    $result .= " W: " . $webArgs->{windspeed}
      if ( defined( $webArgs->{windspeed} ) );
    $result .= " W: " . $webArgs->{windspdmph}
      if ( defined( $webArgs->{windspdmph} ) );
    $result .= " WC: " . $webArgs->{windchill}
      if ( defined( $webArgs->{windchill} ) );
    $result .= " WG: " . $webArgs->{windgust}
      if ( defined( $webArgs->{windgust} ) );
    $result .= " WG: " . $webArgs->{windgustmph}
      if ( defined( $webArgs->{windgustmph} ) );
    $result .= " R: " . $webArgs->{rainrate}
      if ( defined( $webArgs->{rainrate} ) );
    $result .= " RD: " . $webArgs->{dailyrain}
      if ( defined( $webArgs->{dailyrain} ) );
    $result .= " RW: " . $webArgs->{weeklyrain}
      if ( defined( $webArgs->{weeklyrain} ) );
    $result .= " RM: " . $webArgs->{monthlyrain}
      if ( defined( $webArgs->{monthlyrain} ) );
    $result .= " RY: " . $webArgs->{yearlyrain}
      if ( defined( $webArgs->{yearlyrain} ) );
    $result .= " WD: " . $webArgs->{winddir}
      if ( defined( $webArgs->{winddir} ) );
    $result .= " D: " . $webArgs->{dewpoint}
      if ( defined( $webArgs->{dewpoint} ) );
    $result .= " P: " . $webArgs->{relbaro}
      if ( defined( $webArgs->{relbaro} ) );
    $result .= " UV: " . $webArgs->{UV}
      if ( defined( $webArgs->{UV} ) );
    $result .= " UVI: " . $webArgs->{UVI}
      if ( defined( $webArgs->{UVI} ) );
    $result .= " L: " . $webArgs->{light}
      if ( defined( $webArgs->{light} ) );
    $result .= " SR: " . $webArgs->{solarradiation}
      if ( defined( $webArgs->{solarradiation} ) );

    readingsBulkUpdate( $hash, "state", $result );
    readingsEndUpdate( $hash, 1 );

    HP1000_PushWU( $hash, $webArgs )
      if AttrVal( $name, "wu_push", 0 ) eq "1";

    HP1000_PushSrv( $hash, $webArgs )
      if AttrVal( $name, "extSrvPush_Url", undef );

    return ( "text/plain; charset=utf-8", "success" );
}

###################################
sub HP1000_GetAvg($$$$) {
    my ( $hash, $t, $s, $v, $avg ) = @_;
    return HP1000_GetSum( $hash, $t, $s, $v, 1 );
}

sub HP1000_GetSum($$$$;$) {
    my ( $hash, $t, $s, $v, $avg ) = @_;
    my $name = $hash->{NAME};

    return $v if ( $avg && $hash->{INTERVAL} < 1 );
    return "0" if ( $hash->{INTERVAL} < 1 );

    my $max = sprintf( "%.0f", $s / $hash->{INTERVAL} );
    $max = "1" if ( $max < 1 );
    my $return;

    my $v2 = unshift @{ $hash->{helper}{history}{$t} }, $v;
    my $v3 = splice @{ $hash->{helper}{history}{$t} }, $max;

    Log3 $name, 5, "HP1000 $name: Updated history for $t:"
      . Dumper( $hash->{helper}{history}{$t} );

    if ($avg) {
        $return = sprintf( "%.1f",
            sum( @{ $hash->{helper}{history}{$t} } ) /
              @{ $hash->{helper}{history}{$t} } );

        Log3 $name, 5, "HP1000 $name: Average for $t: $return";
    }
    else {
        $return = sprintf( "%.1f", sum( @{ $hash->{helper}{history}{$t} } ) );
        Log3 $name, 5, "HP1000 $name: Sum for $t: $return";
    }

    return $return;
}

###################################
sub HP1000_PushSrv($$) {
    my ( $hash, $webArgs ) = @_;
    my $name            = $hash->{NAME};
    my $timeout         = AttrVal( $name, "timeout", 7 );
    my $http_noshutdown = AttrVal( $name, "http-noshutdown", "1" );
    my $srv_url         = AttrVal( $name, "extSrvPush_Url", "" );
    my $cmd             = "";

    Log3 $name, 5, "HP1000 $name: called function HP1000_PushSrv()";

    if ( $srv_url !~
/(https?):\/\/([\w\.]+):?(\d+)?([a-zA-Z0-9\~\!\@\#\$\%\^\&\*\(\)_\-\=\+\\\/\?\.\:\;\'\,]*)?/
      )
    {
        return;
    }
    elsif ( $4 !~ /\?/ ) {
        $cmd = "?";
    }
    else {
        $cmd = "&";
    }

    $webArgs->{PASSWORD} = "";

    while ( my ( $key, $value ) = each %{$webArgs} ) {
        if ( $key eq "softwaretype" || $key eq "dateutc" ) {
            $value = urlEncode($value);
        }
        $cmd .= "$key=" . $value . "&";
    }

    Log3 $name, 4,
      "HP1000 $name: pushing data to external Server: $srv_url$cmd";

    HttpUtils_NonblockingGet(
        {
            url        => $srv_url . $cmd,
            timeout    => $timeout,
            noshutdown => $http_noshutdown,
            data       => undef,
            hash       => $hash,
            callback   => \&HP1000_ReturnSrv,
        }
    );

    return;
}

###################################
sub HP1000_PushWU($$) {

    #
    # See: http://wiki.wunderground.com/index.php/PWS_-_Upload_Protocol
    #

    my ( $hash, $webArgs ) = @_;
    my $name            = $hash->{NAME};
    my $timeout         = AttrVal( $name, "timeout", 7 );
    my $http_noshutdown = AttrVal( $name, "http-noshutdown", "1" );
    my $wu_user         = AttrVal( $name, "wu_id", "" );
    my $wu_pass         = AttrVal( $name, "wu_password", "" );

    Log3 $name, 5, "HP1000 $name: called function HP1000_PushWU()";

    if ( $wu_user eq "" && $wu_pass eq "" ) {
        Log3 $name, 4,
"HP1000 $name: missing attributes for Weather Underground transfer: wu_user and wu_password";

        my $return = "error: missing attributes wu_user and wu_password";

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "wu_state", $return );
        readingsEndUpdate( $hash, 1 );
        return;
    }

    if ( AttrVal( $name, "wu_realtime", "1" ) eq "0" ) {
        Log3 $name, 5, "HP1000 $name: Explicitly turning off realtime";
        delete $webArgs->{realtime};
        delete $webArgs->{rtfreq};
    }
    elsif ( AttrVal( $name, "wu_realtime", "0" ) eq "1" ) {
        Log3 $name, 5, "HP1000 $name: Explicitly turning on realtime";
        $webArgs->{realtime} = 1;
    }

    $webArgs->{rtfreq} = 5
      if ( defined( $webArgs->{realtime} )
        && !defined( $webArgs->{rtfreq} ) );

    my $wu_url = (
        defined( $webArgs->{realtime} )
          && $webArgs->{realtime} eq "1"
        ? "https://rtupdate.wunderground.com/weatherstation/updateweatherstation.php?"
        : "https://weatherstation.wunderground.com/weatherstation/updateweatherstation.php?"
    );

    $webArgs->{ID}       = $wu_user;
    $webArgs->{PASSWORD} = $wu_pass;

    my $cmd;

    while ( my ( $key, $value ) = each %{$webArgs} ) {
        if ( $key eq "softwaretype" || $key eq "dateutc" ) {
            $value = urlEncode($value);
        }

        elsif ( $key eq "UVI" ) {
            $key   = "UV";
            $value = $value;
        }

        elsif ( $key eq "UV" ) {
            next;
        }

        $cmd .= "$key=" . $value . "&";
    }

    Log3 $name, 4, "HP1000 $name: pushing data to WU: " . $cmd;

    HttpUtils_NonblockingGet(
        {
            url        => $wu_url . $cmd,
            timeout    => $timeout,
            noshutdown => $http_noshutdown,
            data       => undef,
            hash       => $hash,
            callback   => \&HP1000_ReturnWU,
        }
    );

    return;
}

###################################
sub HP1000_ReturnSrv($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    # device not reachable
    if ($err) {
        my $return = "error: connection timeout";
        Log3 $name, 4, "HP1000 $name: EXTSRV HTTP " . $return;

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "extsrv_state", $return );
        readingsEndUpdate( $hash, 1 );
    }

    # data received
    elsif ($data) {
        my $logprio = 5;
        my $return  = "ok";

        if ( $param->{code} ne "200" ) {
            $logprio = 4;
            $return  = "error " . $param->{code} . ": $data";
        }
        Log3 $name, $logprio,
          "HP1000 $name: EXTSRV HTTP return: " . $param->{code} . " - $data";

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "extsrv_state", $return );
        readingsEndUpdate( $hash, 1 );
    }

    return;
}

###################################
sub HP1000_ReturnWU($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    # device not reachable
    if ($err) {
        my $return = "error: connection timeout";
        Log3 $name, 4, "HP1000 $name: WU HTTP " . $return;

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "wu_state", $return );
        readingsEndUpdate( $hash, 1 );
    }

    # data received
    elsif ($data) {
        my $logprio = 5;
        my $return  = "ok";

        if ( $data !~ m/^success.*/ ) {
            $logprio = 4;
            $return  = "error";
            $return .= " " . $param->{code} if ( $param->{code} ne "200" );
            $return .= ": $data";
        }
        Log3 $name, $logprio,
          "HP1000 $name: WU HTTP return: " . $param->{code} . " - $data";

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "wu_state", $return );
        readingsEndUpdate( $hash, 1 );
    }

    return;
}

###################################
sub HP1000_DbLog_split($$) {
    my ( $event, $device ) = @_;
    my ( $reading, $value, $unit ) = "";
    my $hash = $defs{$device};

    if ( $event =~
/^(windCompasspoint.*|.*_sum10m|.*_avg2m|uvCondition):\s([\w\.,]+)\s*(.*)/
      )
    {
        return undef;
    }
    elsif ( $event =~
/^(dewpoint|dewpointIndoor|temperature|temperatureIndoor|windChill):\s([\w\.,]+)\s*(.*)/
      )
    {
        $reading = $1;
        $value   = $2;
        $unit    = "°C";
    }
    elsif ( $event =~
/^(dewpointF|dewpointIndoorF|temperatureF|temperatureIndoorF|windChillF):\s([\w\.,]+)\s*(.*)/
      )
    {
        $reading = $1;
        $value   = $2;
        $unit    = "°F";
    }
    elsif ( $event =~ /^(humidity.*):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "%";
    }
    elsif ( $event =~ /^(luminosity):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "lux";
    }
    elsif ( $event =~ /^(solarradiation):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "W/m2";
    }
    elsif ( $event =~ /^(pressure|pressureAbs):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "hPa";
    }
    elsif ( $event =~ /^(pressureIn|pressureAbsIn):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "inHg";
    }
    elsif ( $event =~ /^(pressureMm|pressureAbsMm):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "mmHg";
    }
    elsif ( $event =~ /^(rain):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "mm/h";
    }
    elsif ( $event =~ /^(rainin):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "in/h";
    }
    elsif (
        $event =~ /^(rainDay|rainWeek|rainMonth|rainYear):\s([\w\.,]+)\s*(.*)/ )
    {
        $reading = $1;
        $value   = $2;
        $unit    = "mm";
    }
    elsif ( $event =~
        /^(rainDayIn|rainWeekIn|rainMonthIn|rainYearIn):\s([\w\.,]+)\s*(.*)/ )
    {
        $reading = $1;
        $value   = $2;
        $unit    = "in";
    }
    elsif ( $event =~ /^(uv):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "uW/cm2";
    }
    elsif ( $event =~ /^(uvIndex):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "UVI";
    }
    elsif ( $event =~ /^(windDir.*):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "°";
    }
    elsif ( $event =~ /^(windGust|windSpeed):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "km/h";
    }
    elsif ( $event =~ /^(windGustBft|windSpeedBft):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "Bft";
    }
    elsif ( $event =~ /^(windGustMps.*|windSpeedMps.*):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "m/s";
    }
    elsif ( $event =~ /^(windGustFts.*|windSpeedFts.*):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "ft/s";
    }
    elsif ( $event =~ /^(windGustKn.*|windSpeedKn.*):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "kn";
    }
    elsif ( $event =~ /^(Activity):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $value   = "1" if ( $2 eq "alive" );
        $value   = "0" if ( $2 eq "dead" );
        $unit    = "";
    }
    elsif ( $event =~ /^(weatherCondition):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = "";
        $value   = "0" if ( $2 eq "clear" );
        $value   = "1" if ( $2 eq "sunny" );
        $value   = "2" if ( $2 eq "cloudy" );
        $value   = "3" if ( $2 eq "rain" );
        return undef if ( $value eq "" );
        $unit = "";
    }
    elsif ( $event =~ /^(humidityCondition):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = "";
        $value   = "0" if ( $2 eq "dry" );
        $value   = "1" if ( $2 eq "low" );
        $value   = "2" if ( $2 eq "optimal" );
        $value   = "3" if ( $2 eq "wet" );
        $value   = "4" if ( $2 eq "rain" );
        return undef if ( $value eq "" );
        $unit = "";
    }
    elsif ( $event =~ /^(humidityIndoorCondition):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = "";
        $value   = "0" if ( $2 eq "dry" );
        $value   = "1" if ( $2 eq "low" );
        $value   = "2" if ( $2 eq "optimal" );
        $value   = "3" if ( $2 eq "wet" );
        return undef if ( $value eq "" );
        $unit = "";
    }
    elsif ( $event =~ /^(wu_state):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = "1" if ( $2 eq "ok" );
        $value   = "0" if ( $2 ne "ok" );
        $unit    = "";
    }
    elsif ( $event =~ /(.+):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = $3;
    }

    Log3 $device, 5,
"HP1000 $device: Splitting event $event > reading=$reading value=$value unit=$unit";

    return ( $reading, $value, $unit );
}

1;

=pod
=item device
=item summary support for Wifi-based weather stations HP1000 and WH2600
=item summary_DE Unterst&uuml;tzung f&uuml;r die WLAN-basierte HP1000 oder WH2600 Wetterstationen
=begin html

    <p>
      <a name="HP1000" id="HP1000"></a>
    </p>
    <h3>
      HP1000
    </h3>
    <ul>

    <div>
      <a name="HP1000define" id="HP10000define"></a> <b>Define</b>
      <div>
      <ul>
        <code>define &lt;WeatherStation&gt; HP1000 [&lt;ID&gt; &lt;PASSWORD&gt;]</code><br>
        <br>
          Provides webhook receiver for Wifi-based weather station HP1000 and WH2600 of Fine Offset Electronics (e.g. also known as Ambient Weather WS-1001-WIFI).<br>
          There needs to be a dedicated FHEMWEB instance with attribute webname set to "weatherstation".<br>
          No other name will work as it's hardcoded in the HP1000/WH2600 device itself!<br>
          If necessary, this module will create a matching FHEMWEB instance named WEBweatherstation during initial definition.<br>
          <br>
          As the URI has a fixed coding as well there can only be one single HP1000/WH2600 station per FHEM installation.<br>
        <br>
        Example:<br>
        <div>
          <code># unprotected instance where ID and PASSWORD will be ignored<br>
          define WeatherStation HP1000<br>
          <br>
          # protected instance: Weather Station needs to be configured<br>
          # to send this ID and PASSWORD for data to be accepted<br>
          define WeatherStation HP1000 MyHouse SecretPassword</code>
        </div><br>
          IMPORTANT: In your HP1000/WH2600 hardware device, make sure you use a DNS name as most revisions cannot handle IP addresses correctly.<br>
      </ul>
      </div><br>
    </div>
    <br>

    <a name="HP1000Attr" id="HP10000Attr"></a> <b>Attributes</b>
    <div>
    <ul>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
      <br>

      <a name="wu_id"></a><li><b>wu_id</b></li>
        Weather Underground (Wunderground) station ID

      <a name="wu_password"></a><li><b>wu_password</b></li>
        Weather Underground (Wunderground) password

      <a name="wu_push"></a><li><b>wu_push</b></li>
        Enable or disable to push data forward to Weather Underground (defaults to 0=no)

      <a name="wu_realtime"></a><li><b>wu_realtime</b></li>
        Send the data to the WU realtime server instead of using the standard server (defaults to 1=yes)
    </ul>
    </div>

    </ul>
=end html

=begin html_DE

    <p>
      <a name="HP1000" id="HP1000"></a>
    </p>
    <h3>
      HP1000
    </h3>
    <ul>

    <div>
      <a name="HP1000define" id="HP10000define"></a> <b>Define</b>
      <div>
      <ul>
        <code>define &lt;WeatherStation&gt; HP1000 [&lt;ID&gt; &lt;PASSWORD&gt;]</code><br>
        <br>
          Stellt einen Webhook f&uuml;r die WLAN-basierte HP1000 oder WH2600 Wetterstation von Fine Offset Electronics bereit (z.B. auch bekannt als Ambient Weather WS-1001-WIFI).<br>
          Es muss noch eine dedizierte FHEMWEB Instanz angelegt werden, wo das Attribut webname auf "weatherstation" gesetzt wurde.<br>
          Kein anderer Name funktioniert, da dieser hard im HP1000/WH2600 Ger&auml;t hinterlegt ist!<br>
          Sofern notwendig, erstellt dieses Modul eine passende FHEMWEB Instanz namens WEBweatherstation w&auml;hrend der initialen Definition.<br>
          <br>
          Da die URI ebenfalls fest kodiert ist, kann mit einer einzelnen FHEM Installation maximal eine HP1000/WH2600 Station gleichzeitig verwendet werden.<br>
        <br>
        Beispiel:<br>
        <div>
          <code># ungesch&uuml;tzte Instanz bei der ID und PASSWORD ignoriert werden<br>
          define WeatherStation HP1000<br>
          <br>
          # gesch&uuml;tzte Instanz: Die Wetterstation muss so konfiguriert sein, dass sie<br>
          # diese ID und PASSWORD sendet, damit Daten akzeptiert werden<br>
          define WeatherStation HP1000 MyHouse SecretPassword</code>
        </div><br>
          WICHTIG: Im HP1000/WH2600 Ger&auml;t selbst muss sichergestellt sein, dass ein DNS Name statt einer IP Adresse verwendet wird, da einige Revisionen damit nicht umgehen k&ouml;nnen.<br>
      </ul>
      </div><br>
    </div>

    <a name="HP1000Attr" id="HP10000Attr"></a> <b>Attributes</b>
    <div>
    <ul>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
      <br>

      <a name="wu_id"></a><li><b>wu_id</b></li>
        Weather Underground (Wunderground) Stations ID

      <a name="wu_password"></a><li><b>wu_password</b></li>
        Weather Underground (Wunderground) Passwort

      <a name="wu_push"></a><li><b>wu_push</b></li>
        Pushen der Daten zu Weather Underground aktivieren oder deaktivieren (Standard ist 0=aus)

      <a name="wu_realtime"></a><li><b>wu_realtime</b></li>
        Sendet die Daten an den WU Echtzeitserver statt an den Standard Server (Standard ist 1=an)
    </ul>
    </div>

    </ul>
=end html_DE

=cut
