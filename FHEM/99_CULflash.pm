##############################################
# $Id: $
# modified by M. Fischer
package main;
use strict;
use warnings;
use HttpUtils;

sub CommandCULflash($$);
sub CULflash_SplitNewFiletimes($);

my $server = "http://fhem.de:80";
my $sdir   = "/fhemupdate2";
my $ftime  = "filetimes.txt";
my $dfu    = "dfu-programmer";

#####################################
sub
CULflash_Initialize($$)
{
  my %chash = ( Fn=>"CommandCULflash",
                Hlp=>"<cul> <type>,flash the CUL from the nightly SVN" );
  $cmds{CULflash} = \%chash;

}

#####################################
sub
CommandCULflash($$)
{
  my ($cl, $param) = @_;
  my $modpath = (-d "updatefhem.dir" ? "updatefhem.dir":$attr{global}{modpath});
  my $moddir = "$modpath/FHEM";

  my %ctypes = (
    CUL_V2     => "at90usb162",
    CUL_V2_HM  => "at90usb162",
    CUL_V3     => "atmega32u4",
    CUL_V4     => "atmega32u2",
  );
  my @a = split("[ \t]+", $param);
  return "Usage: CULflash <Fhem-CUL-Device> <CUL-type>, ".
                "where <CUL-type> is one of ". join(" ", sort keys %ctypes)
      if(!(int(@a) == 2 &&
          ($a[0] eq "none" || ($defs{$a[0]} && $defs{$a[0]}{TYPE} eq "CUL")) &&
          $ctypes{$a[1]}));

  my $cul  = $a[0];
  my $target = $a[1];

  ################################
  # First get the index file to prove the file size
  my $filetimes = GetFileFromURL("$server$sdir/$ftime");
  return "Can't get $ftime from $server" if(!$filetimes);

  # split filetime and filesize
  my ($ret, $filetime, $filesize) = CULflash_SplitNewFiletimes($filetimes);
  return $ret if($ret);

  ################################
  # Now get the firmware file:
  my $content = GetFileFromURL("$server$sdir/FHEM/$target.hex");
  return "File size for $target.hex does not correspond to filetimes.txt entry"
          if(length($content) ne $filesize->{"FHEM/$target.hex"});
  my $localfile = "$moddir/$target.hex";
  open(FH,">$localfile") || return "Can't write $localfile";
  print FH $content;
  close(FH);

  my $cmd = "($dfu MCU erase && $dfu MCU flash TARGET && $dfu MCU start) 2>&1";
  my $mcu = $ctypes{$target};
  $cmd =~ s/MCU/$mcu/g;
  $cmd =~ s/TARGET/$localfile/g;

  if($cul ne "none") {
    CUL_SimpleWrite($defs{$cul}, "B01");
    sleep(4);     # B01 needs 2 seconds for the reset
  }
  Log 1, "CULflash $cmd";
  my $result = `$cmd`;
  Log 1, "CULflash $result";
  return $result;
}

sub
CULflash_SplitNewFiletimes($)
{
  my $filetimes = shift;
  my $ret;
  my (%filetime, %filesize) = ();
  foreach my $l (split("[\r\n]", $filetimes)) {
    chomp($l);
    $ret = "Corrupted filetimes.txt file"
        if($l !~ m/^20\d\d-\d\d-\d\d_\d\d:\d\d:\d\d /);
    last if($ret);
    my ($ts, $fs, $file) = split(" ", $l, 3);
    $filetime{$file} = $ts;
    $filesize{$file} = $fs;
  }
  return ($ret, \%filetime, \%filesize);
}

# vim: ts=2:et
1;
