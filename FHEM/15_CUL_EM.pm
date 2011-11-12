##############################################
# $Id$
package main;

use strict;
use warnings;

# Adjust TOTAL to you meter:
# {$defs{emwz}{READINGS}{basis}{VAL}=<meter>/<corr2>-<total_cnt> }

#####################################
sub
CUL_EM_Initialize($)
{
  my ($hash) = @_;

  # Message is like
  # K41350270

  $hash->{Match}     = "^E0.................\$";
  $hash->{DefFn}     = "CUL_EM_Define";
  $hash->{UndefFn}   = "CUL_EM_Undef";
  $hash->{ParseFn}   = "CUL_EM_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 showtime:0,1 " .
                        "model:EMEM,EMWZ,EMGZ loglevel ignore:0,1";
}

#####################################
sub
CUL_EM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_EM <code> ".
                                "[corr1 corr2 CostPerUnit BasicFeePerMonth]"
            if(int(@a) < 3 || int(@a) > 7);
  return "Define $a[0]: wrong CODE format: valid is 1-12"
                if($a[2] !~ m/^\d+$/ || $a[2] < 1 || $a[2] > 12);

  $hash->{CODE} = $a[2];

  if($a[2] >= 1 && $a[2] <= 4) {                # EMWZ: nRotation in 5 minutes
    my $c = (int(@a) > 3 ? $a[3] : 150);
    $hash->{corr1} = (12/$c);                   # peak/current
    $c = (int(@a) > 4 ? $a[4] : 1800);
    $hash->{corr2} = (12/$c);                   # total

  } elsif($a[2] >= 5 && $a[2] <= 8) {           # EMEM
    # corr1 is the correction factor for power
    $hash->{corr1} = (int(@a) > 3 ? $a[3] : 0.01);
    # corr2 is the correction factor for energy
    $hash->{corr2} = (int(@a) > 4 ? $a[4] : 0.001);

  } elsif($a[2] >= 9 && $a[2] <= 12) {          # EMGZ: 0.01
    $hash->{corr1} = (int(@a) > 3 ? $a[3] : 0.01);
    $hash->{corr2} = (int(@a) > 4 ? $a[4] : 0.01);

  } else {
    $hash->{corr1} = 1;
    $hash->{corr2} = 1;
  }
  $hash->{CostPerUnit} = (int(@a) > 5 ? $a[5] : 0);
  $hash->{BasicFeePerMonth} = (int(@a) > 6 ? $a[6] : 0);

  $modules{CUL_EM}{defptr}{$a[2]} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub
CUL_EM_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{CUL_EM}{defptr}{$hash->{CODE}});
  return undef;
}

#####################################
sub
CUL_EM_Parse($$)
{
  my ($hash,$msg) = @_;

  # 0123456789012345678
  # E01012471B80100B80B -> Type 01, Code 01, Cnt 10
  my @a = split("", $msg);
  my $tpe = ($a[1].$a[2])+0;
  my $cde = hex($a[3].$a[4]);

  # seqno    =  number of received datagram in sequence, runs from 2 to 255
  # total_cnt=  total (cumulated) value in ticks as read from the device
  # basis_cnt=  correction to total (cumulated) value in ticks to account for
  #             counter wraparounds
  # total    =  total (cumulated) value in device units
  # current  =  current value (average over latest 5 minutes) in device units
  # peak     =  maximum value in device units

  my $seqno = hex($a[5].$a[6]);
  my $total_cnt = hex($a[ 9].$a[10].$a[ 7].$a[ 8]);
  my $current_cnt = hex($a[13].$a[14].$a[11].$a[12]);
  my $peak_cnt = hex($a[17].$a[18].$a[15].$a[16]);

  # these are the raw readings from the device
  my $val = sprintf("CNT: %d CUM: %d  5MIN: %d  TOP: %d",
                         $seqno, $total_cnt, $current_cnt, $peak_cnt);

  if($modules{CUL_EM}{defptr}{$cde}) {
    my $def = $modules{CUL_EM}{defptr}{$cde};
    $hash = $def;
    my $n = $hash->{NAME};
    return "" if(IsIgnored($n));

    my $tn = TimeNow();                 # current time
    my $c= 0;                           # count changes
    my %readings;

    Log GetLogLevel($n,5), "CUL_EM $n: $val";
    $readings{RAW} = $val;

    #
    # calculate readings
    #
    # initialize total_cnt_last
    my $total_cnt_last = 0;
    if(defined($hash->{READINGS}{total_cnt})) {
      $total_cnt_last= $hash->{READINGS}{total_cnt}{VAL};
    }


    # initialize basis_cnt_last
    my $basis_cnt = 0;
    if(defined($hash->{READINGS}{basis})) {
      $basis_cnt = $hash->{READINGS}{basis}{VAL};
    }

    # correct counter wraparound
    if($total_cnt< $total_cnt_last) {
      $basis_cnt += 65536;
      $readings{basis} = $basis_cnt;
    }

    #
    # translate into device units
    #
    my $corr1 = $hash->{corr1}; # EMEM power correction factor
    my $corr2 = $hash->{corr2}; # EMEM energy correction factor

    my $total    = ($basis_cnt+$total_cnt)*$corr2;
    my $current  = $current_cnt*$corr1;
    my $peak     = $peak_cnt*$corr1;

    if($tpe ne 2) {
      $peak      = 3000/($peak_cnt > 1 ? $peak_cnt : 1)*$corr1;
      $peak      = ($current > 0 ? $peak : 0);
    }


    $val = sprintf("CNT: %d CUM: %0.3f  5MIN: %0.3f  TOP: %0.3f",
                         $seqno, $total, $current, $peak);
    $hash->{STATE} = $val;
    $hash->{CHANGED}[$c++] = "$val";

    $readings{total_cnt}   = $total_cnt;
    $readings{current_cnt} = $current_cnt;
    $readings{peak_cnt}    = $peak_cnt;
    $readings{seqno}       = $seqno;
    $readings{total}       = $total;
    $readings{current}     = $current;
    $readings{peak}        = $peak;


    ###################################
    # Start CUMULATE day and month
    Log GetLogLevel($n,4), "CUL_EM $n: $val";
    my $tsecs_prev;

    #----- get previous tsecs
    if(defined($hash->{READINGS}{tsecs})) {
      $tsecs_prev= $hash->{READINGS}{tsecs}{VAL};
    } else {
      $tsecs_prev= 0; # 1970-01-01
    }

    #----- save actual tsecs
    my $tsecs= time();  # number of non-leap seconds since January 1, 1970, UTC
    $readings{tsecs}       = $tsecs;

    #----- get cost parameter
    my $cost = $hash->{CostPerUnit};
    my $basicfee = $hash->{BasicFeePerMonth};

    #----- check whether day or month was changed
    if(!defined($hash->{READINGS}{cum_day})) {
      #----- init cum_day if it is not set
      $val = sprintf("CUM_DAY: %0.3f CUM: %0.3f COST: %0.2f", 0,$total,0);
      $readings{cum_day}   = $val;

    } else {

      if( (localtime($tsecs_prev))[3] != (localtime($tsecs))[3] ) {
        #----- day has changed (#3)
        my @cmv = split(" ", $hash->{READINGS}{cum_day}{VAL});
        $val = sprintf("CUM_DAY: %0.3f CUM: %0.3f COST: %0.2f",
                        $total-$cmv[3], $total, ($total-$cmv[3])*$cost);
        $readings{cum_day} = $val;
        Log GetLogLevel($n,3), "CUL_EM $n: $val";


        if( (localtime($tsecs_prev))[4] != (localtime($tsecs))[4] ) {

          #----- month has changed (#4)
          if(!defined($hash->{READINGS}{cum_month})) {
            # init cum_month if not set
            $val = sprintf("CUM_MONTH: %0.3f CUM: %0.3f COST: %0.2f",
                       0, $total, 0);
            $readings{cum_month} = $val;

          } else {
            @cmv = split(" ", $hash->{READINGS}{cum_month}{VAL});
            $val = sprintf("CUM_MONTH: %0.3f CUM: %0.3f COST: %0.2f",
                       $total-$cmv[3], $total,($total-$cmv[3])*$cost+$basicfee);
            $readings{cum_month} = $val;
            Log GetLogLevel($n,3), "CUL_EM $n: $val";

          }
        }
      }
    }
    # End CUMULATE day and month
    ###################################


    foreach my $k (keys %readings) {
      $hash->{READINGS}{$k}{TIME}= $tn;
      $hash->{READINGS}{$k}{VAL} = $readings{$k};
      $hash->{CHANGED}[$c++] = "$k: $readings{$k}";
    }
    return $hash->{NAME};

  } else {

    Log 1, "CUL_EM detected, Code $cde $val";
    return "UNDEFINED CUL_EM_$cde CUL_EM $cde";

  }

}

1;

