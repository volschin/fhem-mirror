#
#
# 09_BS.pm
# written by Dr. Boris Neubert 2009-06-20
# e-mail: omega at online dot de
#
##############################################
package main;

use strict;
use warnings;

my $PI= 3.141592653589793238;

my %defptr;

#############################
sub
BS_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^81..(04|0c)..0101a001a5cf......";
  $hash->{DefFn}     = "BS_Define";
  $hash->{UndefFn}   = "BS_Undef";
  $hash->{ParseFn}   = "BS_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 showtime:0,1 dummy:1,0 model:BSs loglevel:0,1,2,3,4,5,6";

}


#############################
sub
BS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u= "wrong syntax: define <name> BS <sensor> [factor]";
  return $u if((int(@a)< 3) || (int(@a)>4));

  my $name	= $a[0];
  my $sensor	= $a[2];
  if($sensor !~ /[1..9]/) {
  	return "erroneous sensor specification $sensor, use one of 1..9";
  }
  $sensor= "0$sensor";

  my $factor	= 1.0;
  $factor= $a[3] if(int(@a)==4);
  $hash->{SENSOR}= "$sensor";
  $hash->{FACTOR}= $factor;

  my $dev= "a5cf $sensor";
  $hash->{DEF}= $dev;

  $defptr{$dev} = $hash;
  AssignIoPort($hash);
}

#############################
sub
BS_Undef($$)
{
  my ($hash, $name) = @_;
  delete($defptr{$hash->{DEF}});
  return undef;
}

#############################
sub
BS_Parse($$)
{
  my ($hash, $msg) = @_;	# hash points to the FHZ, not to the BS


  # Msg format:
  # 01 23 45 67 8901 2345 6789 01 23 45 67
  # 81 0c 04 .. 0101 a001 a5cf xx 00 zz zz

  my $sensor= substr($msg, 20, 2);
  my $dev= "a5cf $sensor";

  my $def= $defptr{$dev};
  if(!defined($def)) {
    Log 3, sprintf("BS Unknown device %s, please define it", $sensor);
    return "UNDEFINED BS";
  }

  my $name= $def->{NAME};

  return "" if($def->{IODev} && $def->{IODev}{NAME} ne $hash->{NAME});

  my $t= TimeNow();

  my $flags= hex(substr($msg, 24, 1)) & 0xdc;
  my $value= hex(substr($msg, 25, 3)) & 0x3ff;

  my $factor= $def->{FACTOR};
  my $brightness= $value/10.24*$factor;

  my $state= sprintf("brightness: %.2f flags: %d", $brightness, $flags);

  $def->{CHANGED}[0] = $state;
  $def->{STATE} = $state;
  $def->{READINGS}{state}{TIME} = $t;
  $def->{READINGS}{state}{VAL} = $state;
  Log GetLogLevel($name, 4), "BS $name: $state";

  $def->{READINGS}{brightness}{TIME} = $t;
  $def->{READINGS}{brightness}{VAL} = $brightness;
  $def->{READINGS}{flags}{TIME} = $t;
  $def->{READINGS}{flags}{VAL} = $flags;

  return $name;

}

#############################

1;
