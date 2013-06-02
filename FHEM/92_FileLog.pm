##############################################
# $Id$
package main;

use strict;
use warnings;
use IO::File;
#use Devel::Size qw(size total_size);
use vars qw($FW_ss);      # is smallscreen
use vars qw($FW_ME);      # webname (default is fhem), needed by 97_GROUP

sub seekTo($$$$);

#####################################
sub
FileLog_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "FileLog_Define";
  $hash->{SetFn}    = "FileLog_Set";
  $hash->{GetFn}    = "FileLog_Get";
  $hash->{UndefFn}  = "FileLog_Undef";
  $hash->{DeleteFn} = "FileLog_Delete";
  $hash->{NotifyFn} = "FileLog_Log";
  $hash->{AttrFn}   = "FileLog_Attr";
  # logtype is used by the frontend
  $hash->{AttrList} = "disable:0,1 logtype nrarchive archivedir archivecmd";

  $hash->{FW_summaryFn} = "FileLog_fhemwebFn";
  $hash->{FW_detailFn}  = "FileLog_fhemwebFn";
}


#####################################
sub
FileLog_Define($@)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $fh;

  return "wrong syntax: define <name> FileLog filename regexp" if(int(@a) != 4);

  eval { "Hallo" =~ m/^$a[3]$/ };
  return "Bad regexp: $@" if($@);

  my @t = localtime;
  my $f = ResolveDateWildcards($a[2], @t);
  $fh = new IO::File ">>$f";
  return "Can't open $f: $!" if(!defined($fh));

  $hash->{FH} = $fh;
  $hash->{REGEXP} = $a[3];
  $hash->{logfile} = $a[2];
  $hash->{currentlogfile} = $f;
  $hash->{STATE} = "active";

  return undef;
}

#####################################
sub
FileLog_Undef($$)
{
  my ($hash, $name) = @_;
  close($hash->{FH});
  return undef;
}

sub
FileLog_Delete($$)
{
  my ($hash, $name) = @_;
  return if(!$hash->{currentlogfile});
  unlink($hash->{currentlogfile});
  return undef;
}


sub
FileLog_Switch($)
{
  my ($log) = @_;

  my $fh = $log->{FH};
  my @t = localtime;
  my $cn = ResolveDateWildcards($log->{logfile},  @t);

  if($cn ne $log->{currentlogfile}) { # New logfile
    $fh->close();
    HandleArchiving($log);
    $fh = new IO::File ">>$cn";
    if(!defined($fh)) {
      Log(0, "Can't open $cn");
      return;
    }
    $log->{currentlogfile} = $cn;
    $log->{FH} = $fh;
  }

}

#####################################
sub
FileLog_Log($$)
{
  # Log is my entry, Dev is the entry of the changed device
  my ($log, $dev) = @_;

  my $ln = $log->{NAME};
  return if($attr{$ln} && $attr{$ln}{disable});
  return if(!$dev || !defined($dev->{CHANGED}));

  my $n = $dev->{NAME};
  my $re = $log->{REGEXP};
  my $max = int(@{$dev->{CHANGED}});
  my $tn = $dev->{NTFY_TRIGGERTIME};
  my $ct = $dev->{CHANGETIME};
  my $wrotesome;
  my $fh = $log->{FH};

  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));
    my $t = (($ct && $ct->[$i]) ? $ct->[$i] : $tn);
    if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/ || "$t:$n:$s" =~ m/^$re$/) {
      $t =~ s/ /_/; # Makes it easier to parse with gnuplot

      FileLog_Switch($log);

      print $fh "$t $n $s\n";
      $wrotesome = 1;
    }
  }
  if($wrotesome) {
    $fh->flush;
# Too much IO
#    $fh->sync if !($^O eq 'MSWin32'); #not implemented in Windows
  }
  return "";
}

###################################
sub
FileLog_Attr(@)
{
  my @a = @_;
  my $do = 0;

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $defs{$a[1]}{STATE} = ($do == 1 ? "disabled" : "active");

  return undef;
}

###################################

sub
FileLog_Set($@)
{
  my ($hash, @a) = @_;
  my $me = $hash->{NAME};

  return "no set argument specified" if(int(@a) < 2);
  my %sets = (reopen=>0, absorb=>1, addRegexpPart=>2, removeRegexpPart=>1);
  
  my $cmd = $a[1];
  if(!defined($sets{$cmd})) {
    my $r = "Unknown argument $cmd, choose one of ".join(" ",sort keys %sets);
    my $fllist = join(",", grep { $me ne $_ } devspec2array("TYPE=FileLog"));
    $r =~ s/absorb/absorb:$fllist/;
    return $r;
  }
  return "$cmd needs $sets{$cmd} parameter(s)" if(@a-$sets{$cmd} != 2);

  if($cmd eq "reopen") {
    my $fh = $hash->{FH};
    my $cn = $hash->{currentlogfile};
    $fh->close();
    $fh = new IO::File(">>$cn");
    return "Can't open $cn" if(!defined($fh));
    $hash->{FH} = $fh;

  } elsif($cmd eq "addRegexpPart") {
    my %h;
    my $re = "$a[2]:$a[3]";
    map { $h{$_} = 1 } split(/\|/, $hash->{REGEXP});
    $h{$re} = 1;
    $re = join("|", sort keys %h);
    eval { "Hallo" =~ m/^$re$/ };
    return "Bad regexp: $@" if($@);
    $hash->{REGEXP} = $re;
    $hash->{DEF} = $hash->{logfile} ." $re";
    
  } elsif($cmd eq "removeRegexpPart") {
    my %h;
    map { $h{$_} = 1 } split(/\|/, $hash->{REGEXP});
    return "Cannot remove regexp part: not found" if(!$h{$a[2]});
    return "Cannot remove last regexp part" if(int(keys(%h)) == 1);
    delete $h{$a[2]};
    my $re = join("|", sort keys %h);
    eval { "Hallo" =~ m/^$re$/ };
    return "Bad regexp: $@" if($@);
    $hash->{REGEXP} = $re;
    $hash->{DEF} = $hash->{logfile} ." $re";

  } elsif($cmd eq "absorb") {
    my $victim = $a[2];
    return "need another FileLog as argument."
      if(!$victim ||
         !$defs{$victim} ||
         $defs{$victim}{TYPE} ne "FileLog" ||
         $victim eq $me);
    my $vh = $defs{$victim};
    my $mylogfile = $hash->{currentlogfile};
    return "Cant open the associated files"
        if(!open(FH1, $mylogfile) ||
           !open(FH2, $vh->{currentlogfile}) ||
           !open(FH3, ">$mylogfile.new"));

    my $fh = $hash->{FH};
    $fh->close();

    my $b1 = <FH1>; my $b2 = <FH2>;
    while(defined($b1) && defined($b2)) {
      if($b1 lt $b2) {
        print FH3 $b1; $b1 = <FH1>;
      } else {
        print FH3 $b2; $b2 = <FH2>;
      }
    }

    while($b1 = <FH1>) { print FH3 $b1; }
    while($b2 = <FH2>) { print FH3 $b2; }
    close(FH1); close(FH2); close(FH3);
    rename("$mylogfile.new", $mylogfile);
    $fh = new IO::File(">>$mylogfile");
    $hash->{FH} = $fh;

    $hash->{REGEXP} .= "|".$vh->{REGEXP};
    $hash->{DEF} = $hash->{logfile} . " ". $hash->{REGEXP};
    CommandDelete(undef, $victim);

  }
  return undef;
}

#########################
sub
FileLog_fhemwebFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  return "<div id=\"$d\" align=\"center\" class=\"col2\">$defs{$d}{STATE}</div>"
        if($FW_ss && $pageHash);

  my $row = 0;
  my $ret = sprintf("<table class=\"%swide\">", $pageHash ? "" : "block ");
  foreach my $f (FW_fileList($defs{$d}{logfile})) {
    my $class = (!$pageHash ? (($row++&1)?"odd":"even") : "");
    $ret .= "<tr class=\"$class\">";
    $ret .= "<td><div class=\"dname\">$f</div></td>";
    my $idx = 0;
    foreach my $ln (split(",", AttrVal($d, "logtype", "text"))) {
      if($FW_ss && $idx++) {
        $ret .= "</tr><tr class=\"".(($row++&1)?"odd":"even")."\"><td>";
      }
      my ($lt, $name) = split(":", $ln);
      $name = $lt if(!$name);
      $ret .= FW_pH("cmd=logwrapper $d $lt $f",
                    "<div class=\"dval\">$name</div>", 1, "dval", 1);
    }
    $ret .= "</tr>";
  }
  $ret .= "</table>";
  return $ret if($pageHash);

  # DETAIL only from here on
  my $hash = $defs{$d};

  $ret .= "<br>Regexp parts";
  $ret .= "<br><table class=\"block wide\">";
  my @ra = split(/\|/, $hash->{REGEXP});
  if(@ra > 1) {
    foreach my $r (@ra) {
      $ret .= "<tr class=\"".(($row++&1)?"odd":"even")."\">";
      my $cmd = "cmd.X=set $d removeRegexpPart&val.X=$r";
      $ret .= "<td>$r</td>";
      $ret .= FW_pH("$cmd&detail=$d", "removeRegexpPart", 1,undef,1);
      $ret .= "</tr>";
    }
  }

  my @et = devspec2array("TYPE=eventTypes");
  if(!@et) {
    $ret .= FW_pH("$FW_ME/docs/commandref.html#eventTypes",
                  "To add a regexp an eventTypes definition is needed",
                  1, undef, 1);
  } else {
    my %dh;
    foreach my $l (split("\n", AnalyzeCommand(undef, "get $et[0] list"))) {
      my @a = split(/[ \r\n]/, $l);
      $a[1] = "" if(!defined($a[1]));
      $a[1] =~ s/\.\*//g;
      $a[1] =~ s/,.*//g;
      $dh{$a[0]}{".*"} = 1;
      $dh{$a[0]}{$a[1].".*"} = 1;
    }
    my $list = ""; my @al;
    foreach my $dev (sort keys %dh) {
      $list .= " $dev:" . join(",", sort keys %{$dh{$dev}});
      push @al, $dev;
    }
    $ret .= "<tr class=\"".(($row++&1)?"odd":"even")."\">";
    $ret .= "<td colspan=\"2\"><form autocomplete=\"off\">";
    $ret .= FW_hidden("detail", $d);
    $ret .= FW_hidden("dev.$d", "$d addRegexpPart");
    $ret .= FW_submit("cmd.$d", "set", "set");
    $ret .= "<div class=\"set downText\">&nbsp;$d addRegexpPart&nbsp;</div>";
    $ret .= FW_select("","arg.$d",\@al, undef, "set",
        "FW_selChange(this.options[selectedIndex].text,'$list','val.$d')");
    $ret .= FW_textfield("val.$d", 30, "set");
    $ret .= "<script type=\"text/javascript\">" .
              "FW_selChange('$al[0]','$list','val.$d')</script>";
    $ret .= "</form></td></tr>";
  }
  $ret .= "</table>";

  my $newIdx=1;
  while($defs{"wl_${d}_$newIdx"}) {
    $newIdx++;
  }
  my $name = "wl_${d}_$newIdx";
  $ret .= FW_pH("cmd=define $name weblink fileplot $d:template:CURRENT;".
                     "set $name copyGplotFile&detail=$name",
                "<div class=\"dval\">Create new SVG plot</div>", 0, "dval", 1);

  return $ret;
}


###################################
# We use this function to be able to scroll/zoom in the plots created from the
# logfile.  When outfile is specified, it is used with gnuplot post-processing,
# when outfile is "-" it is used to create SVG graphics
#
# Up till now following functions are impemented:
# - int (to cut off % from a number, as for the actuator)
# - delta-h / delta-d to get rain/h and rain/d values from continuous data.
#
# It will set the %data values
#  min<x>, max<x>, avg<x>, cnt<x>, currdate<x>, currval<x>, sum<x>
# for each requested column, beginning with <x> = 1

sub
FileLog_Get($@)
{
  my ($hash, @a) = @_;
  
  return "Usage: get $a[0] <infile> <outfile> <from> <to> <column_spec>...\n".
         "  where column_spec is <col>:<regexp>:<default>:<fn>\n" .
         "  see the FileLogGrep entries in he .gplot files\n" .
         "  <infile> is without direcory, - means the current file\n" .
         "  <outfile> is a prefix, - means stdout\n"
        if(int(@a) < 5);
  shift @a;
  my $inf  = shift @a;
  my $outf = shift @a;
  my $from = shift @a;
  my $to   = shift @a; # Now @a contains the list of column_specs
  my $internal;
  if($outf eq "INT") {
    $outf = "-";
    $internal = 1;
  }

  FileLog_Switch($hash);
  if($inf eq "-") {
    $inf = $hash->{currentlogfile};

  } else {
    # Look for the file in the log directory...
    my $linf = "$1/$inf" if($hash->{currentlogfile} =~ m,^(.*)/[^/]*$,);
    return undef if(!$linf);
    if(!-f $linf) {
      # ... or in the archivelog
      $linf = AttrVal($hash->{NAME},"archivedir",".") ."/". $inf;
      return "Error: cannot access $linf" if(!-f $linf);
    }
    $inf = $linf;
  }
  my $ifh = new IO::File $inf;
  seekTo($inf, $ifh, $hash, $from);

  #############
  # Digest the input.
  # last1: first delta value after d/h change
  # last2: last delta value recorded (for the very last entry)
  # last3: last delta timestamp (d or h)
  my (@d, @fname);
  my (@min, @max, @sum, @cnt, @lastv, @lastd);

  for(my $i = 0; $i < int(@a); $i++) {
    my @fld = split(":", $a[$i], 4);

    my %h;
    if($outf ne "-") {
      $fname[$i] = "$outf.$i";
      $h{fh} = new IO::File "> $fname[$i]";
    }
    $h{re} = $fld[1];                                   # Filter: regexp
    $h{df} = defined($fld[2]) ? $fld[2] : "";           # default value
    $h{fn} = $fld[3];                                   # function
    $h{didx} = 10 if($fld[3] && $fld[3] eq "delta-d");  # delta idx, substr len
    $h{didx} = 13 if($fld[3] && $fld[3] eq "delta-h");

    if($fld[0] =~ m/"(.*)"/o) {
      $h{col} = $1;
      $h{type} = 0;
    } else {
      $h{col} = $fld[0]-1;
      $h{type} = 1;
    }
    if($h{fn}) {
      $h{type} = 4;
      $h{type} = 2 if($h{didx});
      $h{type} = 3 if($h{fn} eq "int");
    }
    $h{ret} = "";
    $d[$i] = \%h;
    $min[$i] =  999999;
    $max[$i] = -999999;
    $sum[$i] = 0;
    $cnt[$i] = 0;
    $lastv[$i] = 0;
    $lastd[$i] = "undef";
  }

  my %lastdate;
  my $d;                    # Used by eval functions

  my ($rescan, $rescanNum, $rescanIdx, @rescanArr);
  $rescan = 0;

RESCAN:
  for(;;) {
    my $l;

    if($rescan) {
      last if($rescanIdx<1 || !$rescanNum);
      $l = $rescanArr[$rescanIdx--];
    } else {
      $l = <$ifh>;
      last if(!$l);
    }

    next if($l lt $from && !$rescan);
    last if($l gt $to);
    my @fld = split("[ \r\n]+", $l);     # 40% CPU

    for my $i (0..int(@a)-1) {           # Process each req. field
      my $h = $d[$i];
      next if($rescan && $h->{ret});
      my @missingvals;
      next if($h->{re} && $l !~ m/$h->{re}/);      # 20% CPU

      my $col = $h->{col};
      my $t = $h->{type};

      my $val = undef;
      my $dte = $fld[0];

      if($t == 0) {                         # Fixed text
        $val = $col;

      } elsif($t == 1) {                    # The column
        $val = $fld[$col] if(defined($fld[$col]));

      } elsif($t == 2) {                    # delta-h  or delta-d

        my $hd = $h->{didx};                # TimeStamp-Length
        my $ld = substr($fld[0],0,$hd);     # TimeStamp-Part (hour or date)
        if(!defined($h->{last1}) || $h->{last3} ne $ld) {
          if(defined($h->{last1})) {
            my @lda = split("[_:]", $lastdate{$hd});
            my $ts = "12:00:00";            # middle timestamp
            $ts = "$lda[1]:30:00" if($hd == 13);
            my $v = $fld[$col]-$h->{last1};
            $v = 0 if($v < 0);              # Skip negative delta
            $dte = "$lda[0]_$ts";
            $val = sprintf("%g", $v);
            if($hd == 13) {                 # Generate missing 0 values / hour
              my @cda = split("[_:]", $ld);
              for(my $mi = $lda[1]+1; $mi < $cda[1]; $mi++) {
                push @missingvals, sprintf("%s_%02d:30:00 0\n", $lda[0], $mi);
              }
            }
          }
          $h->{last1} = $fld[$col];
          $h->{last3} = $ld;
        }
        $h->{last2} = $fld[$col];
        $lastdate{$hd} = $fld[0];

      } elsif($t == 3) {                    # int function
        $val = $1 if($fld[$col] =~ m/^(\d+).*/o);

      } else {                              # evaluate
        $val = eval($h->{fn});

      }

      next if(!defined($val) || $val !~ m/^[-\.\d]+$/o);
      $min[$i] = $val if($val < $min[$i]);
      $max[$i] = $val if($val > $max[$i]);
      $sum[$i] += $val;
      $cnt[$i]++;
      $lastv[$i] = $val;
      $lastd[$i] = $dte;
      map { $cnt[$i]++; $min[$i] = 0 if(0 < $min[$i]); } @missingvals;

      if($outf eq "-") {
        $h->{ret} .= "$dte $val\n";
        map { $h->{ret} .= $_ } @missingvals;

      } else {
        my $fh = $h->{fh};      # cannot use $h->{fh} in print directly
        print $fh "$dte $val\n";
        map { print $fh $_ } @missingvals;
      }
      $h->{count}++;
      $rescanNum--;
      last if(!$rescanNum);

    }
  }

  # If no value found for some of the required columns, then look for the last
  # matching entry outside of the range. Known as the "window left open
  # yesterday" problem
  if(!$rescan) {
    $rescanNum = 0;
    map { $rescanNum++ if(!$d[$_]->{count} && $d[$_]->{df} eq "") } (0..$#a);
    if($rescanNum) {
      $rescan=1;
      my $buf;
      my $end = $hash->{pos}{"$inf:$from"};
      my $start = $end - 1024;
      $start = 0 if($start < 0);
      $ifh->seek($start, 0);
      sysread($ifh, $buf, $end-$start);
      @rescanArr = split("\n", $buf);
      $rescanIdx = $#rescanArr;
      goto RESCAN;
    }
  }

  $ifh->close();

  my $ret = "";
  for(my $i = 0; $i < int(@a); $i++) {
    my $h = $d[$i];
    my $hd = $h->{didx};
    if($hd && $lastdate{$hd}) {
      my $val = defined($h->{last1}) ? $h->{last2}-$h->{last1} : 0;
      $min[$i] = $val if($min[$i] ==  999999);
      $max[$i] = $val if($max[$i] == -999999);
      $lastv[$i] = $val if(!$lastv[$i]);
      $sum[$i] = ($sum[$i] ? $sum[$i] + $val : $val);
      $cnt[$i]++;

      my @lda = split("[_:]", $lastdate{$hd});
      my $ts = "12:00:00";                   # middle timestamp
      $ts = "$lda[1]:30:00" if($hd == 13);
      my $line = sprintf("%s_%s %0.1f\n", $lda[0],$ts, $h->{last2}-$h->{last1});

      if($outf eq "-") {
        $h->{ret} .= $line;
      } else {
        my $fh = $h->{fh};
        print $fh $line;
        $h->{count}++;
      }
    }

    if($outf eq "-") {
      $h->{ret} .= "$from $h->{df}\n" if(!$h->{ret} && $h->{df} ne "");
      $ret .= $h->{ret} if($h->{ret});
      $ret .= "#$a[$i]\n";
    } else {
      my $fh = $h->{fh};
      if(!$h->{count} && $h->{df} ne "") {
        print $fh "$from $h->{df}\n";
      }
      $fh->close();
    }

    my $j = $i+1;
    $data{"min$j"} = $min[$i] == 999999 ? "undef" : $min[$i];
    $data{"max$j"} = $max[$i] == -999999 ? "undef" : $max[$i];
    $data{"avg$j"} = $cnt[$i] ? sprintf("%0.1f", $sum[$i]/$cnt[$i]) : "undef";
    $data{"sum$j"} = $sum[$i];
    $data{"cnt$j"} = $cnt[$i] ? $cnt[$i] : "undef";
    $data{"currval$j"} = $lastv[$i];
    $data{"currdate$j"} = $lastd[$i];

  }
  if($internal) {
    $internal_data = \$ret;
    return undef;
  }

  return ($outf eq "-") ? $ret : join(" ", @fname);
}

###############
# this is not elegant
sub
seekBackOneLine($$)
{
  my ($fh, $pos) = @_;
  my $buf;
  $pos -= 2; # skip current CR/NL
  $fh->seek($pos, 0);
  while($pos > 0 && $fh->read($buf, 1)) {
    if($buf eq "\n" || $buf eq "\r") {
      $fh->seek(++$pos, 0);
      return $pos;
    }
    $fh->seek(--$pos, 0);
  }
  return 0;
}

###################################
sub
seekTo($$$$)
{
  my ($fname, $fh, $hash, $ts) = @_;

  # If its cached
  if($hash->{pos} && $hash->{pos}{"$fname:$ts"}) {
    $fh->seek($hash->{pos}{"$fname:$ts"}, 0);
    return;
  }

  $fh->seek(0, 2); # Go to the end
  my $upper = $fh->tell;

  my ($lower, $next, $last) = (0, $upper/2, 0);
  my $div = 2;
  while() {                                             # Binary search
    $fh->seek($next, 0);
    my $data = <$fh>;
    if(!$data) {
      $last = $next;
      last;
    }
    if($data !~ m/^\d\d\d\d-\d\d-\d\d_\d\d:\d\d:\d\d /o) {
      $next = $fh->tell;
      $data = <$fh>;
      if(!$data) {
        $last = seekBackOneLine($fh, $next);
        last;
      }

      # If the second line is longer then the first,
      # binary search will never get it: 
      if($next eq $last && $data ge $ts && $div < 8192) {
        $last = 0;
        $div *= 2;
      }
    }
    if($next eq $last) {
      $fh->seek($next, 0);
      last;
    }

    $last = $next;
    if(!$data || $data lt $ts) {
      ($lower, $next) = ($next, int(($next+$upper)/$div));
    } else {
      ($upper, $next) = ($next, int(($lower+$next)/$div));
    }
  }
  $hash->{pos}{"$fname:$ts"} = $last;

}

1;

=pod
=begin html

<a name="FileLog"></a>
<h3>FileLog</h3>
<ul>
  <br>

  <a name="FileLogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FileLog &lt;filename&gt; &lt;regexp&gt;</code>
    <br><br>

    Log events to <code>&lt;filename&gt;</code>. The log format is
    <ul><code><br>
      YYYY:MM:DD_HH:MM:SS &lt;device&gt; &lt;event&gt;<br>
    <br></code></ul>
    The regexp will be checked against the device name
    devicename:event or timestamp:devicename:event combination.
    The regexp must match the complete string, not just a part of it.
    <br>
    <code>&lt;filename&gt;</code> may contain %-wildcards of the
    POSIX strftime function of the underlying OS (see your strftime manual).
    Common used wildcards are:
    <ul>
    <li><code>%d</code> day of month (01..31)</li>
    <li><code>%m</code> month (01..12)</li>
    <li><code>%Y</code> year (1970...)</li>
    <li><code>%w</code> day of week (0..6);  0 represents Sunday</li>
    <li><code>%j</code> day of year (001..366)</li>
    <li><code>%U</code> week number of year with Sunday as first day of week (00..53)</li>
    <li><code>%W</code> week number of year with Monday as first day of week (00..53)</li>
    </ul>
    FHEM also replaces <code>%L</code> by the value of the global logdir attribute.<br>
    Before using <code>%V</code> for ISO 8601 week numbers check if it is
    correctly supported by your system (%V may not be replaced, replaced by an
    empty string or by an incorrect ISO-8601 week number, especially
    at the beginning of the year)
    If you use <code>%V</code> you will also have to use %G
    instead of %Y for the year!<br>
    Examples:
    <ul>
      <code>define lamplog FileLog %L/lamp.log lamp</code><br>
      <code>define wzlog FileLog /var/tmp/wz-%Y-%U.log
              wz:(measured-temp|actuator).*</code><br>
      With ISO 8601 week numbers, if supported:<br>
      <code>define wzlog FileLog /var/tmp/wz-%G-%V.log
              wz:(measured-temp|actuator).*</code><br>
    </ul>
    <br>
  </ul>

  <a name="FileLogset"></a>
  <b>Set </b>
  <ul>
    <li>reopen
      <ul>
        Reopen a FileLog after making some manual changes to the
        logfile.
      </ul>
      </li>
    <li>addRegexpPart &lt;device&gt; &lt;regexp&gt;
      <ul>
        add a regexp part, which is constructed as device:regexp.  The parts
        are separated by |.  Note: as the regexp parts are resorted, manually
        constructed regexps may become invalid.
      </ul>
      </li>
    <li>removeRegexpPart &lt;re&gt;
      <ul>
        remove a regexp part.  Note: as the regexp parts are resorted, manually
        constructed regexps may become invalid.<br>
        The inconsistency in addRegexpPart/removeRegexPart arguments originates
        from the reusage of javascript functions.
      </ul>
      </li>
    <li>absorb secondFileLog 
      <ul>
        merge the current and secondFileLog into one file, add the regexp of the
        secondFileLog to the current one, and delete secondFileLog.<br>
        This command is needed to create combined plots (weblinks).<br>
        <b>Notes:</b>
        <ul>
          <li>secondFileLog will be deleted (i.e. the FHEM definition and
              the file itself).</li>
          <li>only the current files will be merged.</li>
          <li>weblinks using secondFilelog will become broken, they have to be
              adopted to the new logfile or deleted.</li>
        </ul>
      </ul>
      </li>
      <br>
    </ul>
    <br>


  <a name="FileLogget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;column_spec&gt; </code>
    <br><br>
    Read data from the logfile, used by frontends to plot data without direct
    access to the file.<br>

    <ul>
      <li>&lt;infile&gt;<br>
        Name of the logfile to grep. "-" is the current logfile, or you can
        specify an older file (or a file from the archive).</li>
      <li>&lt;outfile&gt;<br>
        If it is "-", you get the data back on the current connection, else it
        is the prefix for the output file. If more than one file is specified,
        the data is separated by a comment line for "-", else it is written in
        separate files, numerated from 0.
        </li>
      <li>&lt;from&gt; &lt;to&gt;<br>
        Used to grep the data. The elements should correspond to the
        timeformat or be an initial substring of it.</li>
      <li>&lt;column_spec&gt;<br>
        For each column_spec return a set of data in a separate file or
        separated by a comment line on the current connection.<br>
        Syntax: &lt;col&gt;:&lt;regexp&gt;:&lt;default&gt;:&lt;fn&gt;<br>
        <ul>
          <li>&lt;col&gt;
            The column number to return, starting at 1 with the date.
            If the column is enclosed in double quotes, then it is a fix text,
            not a column nuber.</li>
          <li>&lt;regexp&gt;
            If present, return only lines containing the regexp. Case sensitive.
            </li>
          <li>&lt;default&gt;<br>
            If no values were found and the default value is set, then return
            one line containing the from value and this default. We need this
            feature as gnuplot aborts if a dataset has no value at all.
            </li>
          <li>&lt;fn&gt;
            One of the following:
            <ul>
              <li>int<br>
                Extract the  integer at the beginning og the string. Used e.g.
                for constructs like 10%</li>
              <li>delta-h or delta-d<br>
                Return the delta of the values for a given hour or a given day.
                Used if the column contains a counter, as is the case for the
                KS300 rain column.</li>
              <li>everything else<br>
                The string is evaluated as a perl expression. @fld is the
                current line splitted by spaces. Note: The string/perl
                expression cannot contain spaces, as the part after the space
                will be considered as the next column_spec.</li>
            </ul></li>
        </ul></li>
      </ul>
    <br><br>
    Example:
      <ul><code><br>
        get outlog out-2008.log - 2008-01-01 2008-01-08 4:IR:int: 9:IR::
      </code></ul>
    <br>
  </ul>

  <a name="FileLogattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="archivedir"></a>
    <a name="archivecmd"></a>
    <a name="nrarchive"></a>
    <li>archivecmd / archivedir / nrarchive<br>
        When a new FileLog file is opened, the FileLog archiver wil be called.
        This happens only, if the name of the logfile has changed (due to
        time-specific wildcards, see the <a href="#FileLog">FileLog</a>
        section), and there is a new entry to be written into the file.
        <br>

        If the attribute archivecmd is specified, then it will be started as a
        shell command (no enclosing " is needed), and each % in the command
        will be replaced with the name of the old logfile.<br>

        If this attribute is not set, but nrarchive and/or archivecmd are set,
        then nrarchive old logfiles are kept along the current one while older
        ones are moved to archivedir (or deleted if archivedir is not set).
        </li><br>

    <li><a href="#disable">disable</a></li>

    <a name="logtype"></a>
    <li>logtype<br>
        Used by the pgm2 webfrontend to offer gnuplot/SVG images made from the
        logs.  The string is made up of tokens separated by comma (,), each
        token specifies a different gnuplot program. The token may contain a
        colon (:), the part before the colon defines the name of the program,
        the part after is the string displayed in the web frontend. Currently
        following types of gnuplot programs are implemented:<br>
        <ul>
           <li>fs20<br>
               Plots on as 1 and off as 0. The corresponding filelog definition
               for the device fs20dev is:<br>
               define fslog FileLog log/fs20dev-%Y-%U.log fs20dev
          </li>
           <li>fht<br>
               Plots the measured-temp/desired-temp/actuator lines. The
               corresponding filelog definitions (for the FHT device named
               fht1) looks like:<br>
               <code>define fhtlog1 FileLog log/fht1-%Y-%U.log fht1:.*(temp|actuator).*</code>

          </li>
           <li>temp4rain10<br>
               Plots the temperature and rain (per hour and per day) of a
               ks300. The corresponding filelog definitions (for the KS300
               device named ks300) looks like:<br>
               define ks300log FileLog log/fht1-%Y-%U.log ks300:.*H:.*
          </li>
           <li>hum6wind8<br>
               Plots the humidity and wind values of a
               ks300. The corresponding filelog definition is the same as
               above, both programs evaluate the same log.
          </li>
           <li>text<br>
               Shows the logfile as it is (plain text). Not gnuplot definition
               is needed.
          </li>
        </ul>
        Example:<br>
           attr ks300log1 logtype temp4rain10:Temp/Rain,hum6wind8:Hum/Wind,text:Raw-data
    </li><br>



  </ul>
  <br>
</ul>

=end html
=cut
