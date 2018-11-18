##############################################
# $Id$
package main;

my %templates;
my $initialized;
my %cachedUsage;

sub
AttrTemplate_Initialize()
{
  my $me = "AttrTemplate_Initialize";
  my $dir = $attr{global}{modpath}."/FHEM/lib/AttrTemplate";
  if(!opendir(dh, $dir)) {
    Log 1, "$me: cant open $dir: $!";
    return;
  }

  my @files = grep /\.template$/, sort readdir dh;
  closedir(dh);

  %templates = ();
  %cachedUsage = ();
  for my $file (@files) {
    if(!open(fh,"$dir/$file")) {
      Log 1, "$me: cant open $dir/$file: $!";
      next;
    }
    my ($name, %h);
    while(my $line = <fh>) {
      chomp($line);
      next if($line =~ m/^$/ || $line =~ m/^#/);

      if($line =~ m/^name:(.*)/) {
        $name = $1;
        my (@p,@c);
        $templates{$name}{pars} = \@p;
        $templates{$name}{cmds} = \@c;

      } elsif($line =~ m/^filter:(.*)=(.*)/) {
        $templates{$name}{filterName} = $1;
        $templates{$name}{filterVal} = $2;

      } elsif($line =~ m/^par:(.*)/) {
        push(@{$templates{$name}{pars}}, $1);

      } else {
        push(@{$templates{$name}{cmds}}, $line);

      }
    }
    close(fh);
  }
  my $nr = (int keys %templates);
  $initialized = 1;
  Log 2, "AttrTemplates: got $nr entries" if($nr);
}

sub
AttrTemplate_Set($$@)
{
  my ($hash, $list, $name, $cmd, @a) = @_;

  AttrTemplate_Initialize() if(!$initialized);

  if($cmd ne "attrTemplate") {
    if(!$cachedUsage{$name}) {
      my @list;
      for my $k (sort keys %templates) {
        my $h = $templates{$k};
        if(!$h->{filterName} || $hash->{$h->{filterName}} eq $h->{filterVal}) {
          push @list, $k;
        }
      }
      $cachedUsage{$name} = (@list ? "attrTemplate:".join(",",@list) : "");
    }
    $list .= " " if($list ne "");
    return "Unknown argument $cmd, choose one of $list$cachedUsage{$name}";
  }

  return "Missing template_entry_name parameter for attrTemplate" if(@a < 1);
  my $entry = shift(@a);
  my $h = $templates{$entry};
  return "Unknown template_entry_name $entry" if(!$h);

  my (%repl, @mComm, @mList, $missing);
  for my $k (@{$h->{pars}}) {
    my ($parname, $comment, $perl_code) = split(";",$k,3);

    if(@a) {
      $repl{$parname} = $a[0];
      push(@mList, $parname);
      push(@mComm, "$parname: with the $comment");
      shift(@a);
      next;
    }

    if($perl_code) {
      $perl_code =~ s/DEVICE/$name/g;
      my $ret = eval $perl_code;
      return "Error checking template regexp: $@" if($@);
      if($ret) {
        $repl{$parname} = $ret;
        next;
      }
    }

    push(@mList, $parname);
    push(@mComm, "$parname: with the $comment");
    $missing = 1;
  }

  if($missing) {
    if($hash->{CL} && $hash->{CL}{TYPE} eq "FHEMWEB") {
      return
      "<html>".
         "<input size='60' type='text' spellcheck='false' ".
                "value='set $name attrTemplate $entry @mList'>".
         "<br><br>Replace<br>".join("<br>",@mComm).
        '<script>
          setTimeout(function(){
            // TODO: fix multiple dialog calls
            $("#FW_okDialog").parent().find("button").css("display","block");
            $("#FW_okDialog").parent().find(".ui-dialog-buttonpane button")
            .unbind("click").click(function(){
              var val = encodeURIComponent($("#FW_okDialog input").val());
              FW_cmd(FW_root+"?cmd="+val+"&XHR=1",
                     function(){ location.reload() } );
              $("#FW_okDialog").remove();
            })}, 100);
         </script>
       </html>';

    } else {
      return "Usage: set $name attrTemplate $entry @mList\nReplace\n".
               join("\n", @mComm);

    }
  }

  my $cmdlist = join("\n",@{$h->{cmds}});
  $repl{DEVICE} = $name;
  map { $cmdlist =~ s/$_/$repl{$_}/g; } keys %repl;
  my $cmd = "";
  my @ret;
  map {
    if($_ =~ m/^(.*)\\$/) {
      $cmd .= "$1\n";
    } else {
      my $r = AnalyzeCommand($hash->{CL}, $cmd.$_);
      push(@ret, $r) if($r);
      $cmd = "";
    }
  } split("\n", $cmdlist);
  return @ret ? join("\n", @ret) : undef;
}

1;
