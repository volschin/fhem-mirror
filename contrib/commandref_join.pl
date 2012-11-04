#!/usr/bin/perl

use strict;
use warnings;

# $Id$

my $docIn  = "docs/commandref_frame.html";
my $docOut = "docs/commandref.html";
my @modDir = ("FHEM");
use constant TAGS => qw{ul li code};

open(IN, "$docIn")    || die "Cant open $docIn: $!\n";
open(OUT, ">$docOut") || die "Cant open $docOut: $!\n";

my %mods;
foreach my $modDir (@modDir) {
  opendir(DH, $modDir) || die "Cant open $modDir: $!\n";
  while(my $l = readdir DH) {
    next if($l !~ m/^\d\d_.*\.pm$/);
    my $of = $l;
    $l =~ s/.pm$//;
    $l =~ s/^[0-9][0-9]_//;
    $mods{$l} = "$modDir/$of";
  }
}

# First run: check what is a command and what is a helper module
my $status;
my %noindex;
while(my $l = <IN>) {
  last if($l =~ m/<h3>Introduction/);
  $noindex{$1} = 1 if($l =~ m/href="#(.*)"/);
}
seek(IN,0,0);

# Second run: create the file
# Header
while(my $l = <IN>) {
  print OUT $l;
  last if($l =~ m/#global/);
}

# index for devices.
foreach my $mod (sort keys %mods) {
  next if($noindex{$mod});
  print OUT "      <a href='#$mod'>$mod</a> &nbsp;\n";
}

# Copy the middle part
while(my $l = <IN>) {
  last if($l =~ m/name="perl"/);
  print OUT $l;
}

# Copy the doc part from the module
foreach my $mod (sort keys %mods) {
  my $tag;
  my %tagcount= ();
  open(MOD, $mods{$mod}) || die("Cant open $mods{$mod}:$!\n");
  my $skip = 1;
  while(my $l = <MOD>) {
    if($l =~ m/^=begin html/) {
      $skip = 0;
    } elsif($l =~ m/^=end html/) {
      $skip = 1;
    } elsif(!$skip) {
      # here we copy line by line from the module
      print OUT $l;
      foreach $tag (TAGS) {
        $tagcount{$tag}+= ($l =~ /<$tag>/i);
        $tagcount{$tag}-= ($l =~ /<\/$tag>/i);
      }
    }
  }
  close(MOD);
  foreach $tag (TAGS) {
    print("$mods{$mod}: Unbalanced $tag\n") if($tagcount{$tag});
  }
}

# Copy the tail
print OUT '<a name="perl"></a>',"\n";
while(my $l = <IN>) {
  print OUT $l;
}
close(OUT);
