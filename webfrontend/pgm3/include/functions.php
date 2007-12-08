<?php

##Functions for pgm3


function LogRotate($array,$file,$logrotatelines)
{
	$counter=count($array);
	$filename=$file;
	
	if (!$handle = fopen($filename, "w")) {
         print "Logrotate: cannot open $filename -- correct rights?? Read the chapter in the config.php!";
         exit;
   	}
        for ($x = $counter-$logrotatelines; $x < $counter; $x++)
        {fwrite($handle, $array[$x]);};

	fclose($handle);
}


function bft($windspeed)        # wind speed in Beaufort
{
        if($windspeed>= 118.5) { $bft= 12; }
        elseif($windspeed>= 103.7) { $bft= 11; }
        elseif($windspeed>=  88.9) { $bft= 10; }
        elseif($windspeed>=  75.9) { $bft=  9; }
        elseif($windspeed>=  63.0) { $bft=  8; }
        elseif($windspeed>=  51.9) { $bft=  7; }
        elseif($windspeed>=  40.7) { $bft=  6; }
        elseif($windspeed>=  29.6) { $bft=  5; }
        elseif($windspeed>=  20.4) { $bft=  4; }
        elseif($windspeed>=  13.0) { $bft=  3; }
        elseif($windspeed>=   7.4) { $bft=  2; }
        elseif($windspeed>=   1.9) { $bft=  1; }
	else $bft= 0;
        return($bft);
}

# saturation vapour pressure, approximation for
# temperature range 0°C .. +100,9°C
# see http://www.umnicom.de/Elektronik/Projekte/Wetterstation/Sensoren/SattDruck/SattDruck.htm
function svp($temperature)	# saturation vapour pressure in hPa
{
	$c1= 6.10780; 	# hPa
	$c2= 17.09085; 
	$c3= 234.175; 	# °C
	
	return($c1*exp(($c2*$temperature)/($c3+$temperature)));
}

# see http://www.umnicom.de/Elektronik/Projekte/Wetterstation/Sensoren/Taupunkte/Taupunkte.htm
function dewpoint($temp,$hum)	# dew point and temperature in °C, humidity in % 
{
	$svp= svp($temp);
	$log= log10($svp*$hum/100.0);
	return( (234.67*$log-184.2)/(8.233-$log));
}

function randdefine()
{
	$rand1 = rand(500,20000);
        $rand2 = rand(500,20000);
        $rq = md5($rand1.$rand2);
        $randdefine=substr($rq,0,5);
	return ($randdefine);
}


?>
