
# $Id$

package main;

use strict;
use warnings;

use vars qw(%FW_webArgs); # all arguments specified in the GET

sub readingsGroup_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "readingsGroup_Define";
  $hash->{NotifyFn} = "readingsGroup_Notify";
  $hash->{UndefFn}  = "readingsGroup_Undefine";
  #$hash->{SetFn}    = "readingsGroup_Set";
  $hash->{GetFn}    = "readingsGroup_Get";
  $hash->{AttrList} = "mapping separator style nameStyle valueStyle timestampStyle noheading:1 notime:1 nostate:1";

  $hash->{FW_detailFn}  = "readingsGroup_detailFn";
  $hash->{FW_summaryFn}  = "readingsGroup_detailFn";

  $hash->{FW_atPageEnd} = 1;
}

sub
readingsGroup_updateDevices($)
{
  my ($hash) = @_;

  my %list;
  my @devices;

  my @params = split(" ", $hash->{DEF});
  while (@params) {
    my $param = shift(@params);

    # for backwards compatibility with weblink readings
    if( $param eq '*noheading' ) {
      $attr{$hash->{NAME}}{noheading} = 1;
      $hash->{DEF} =~ s/(\s*)$param((:\S+)?\s*)/ /g;
      $hash->{DEF} =~ s/^ //;
      $hash->{DEF} =~ s/ $//;
    } elsif( $param eq '*notime' ) {
      $attr{$hash->{NAME}}{notime} = 1;
      $hash->{DEF} =~ s/(\s*)$param((:\S+)?\s*)/ /g;
      $hash->{DEF} =~ s/^ //;
      $hash->{DEF} =~ s/ $//;
    } elsif( $param eq '*nostate' ) {
      $attr{$hash->{NAME}}{nostate} = 1;
      $hash->{DEF} =~ s/(\s*)$param((:\S+)?\s*)/ /g;
      $hash->{DEF} =~ s/^ //;
      $hash->{DEF} =~ s/ $//;
    } elsif( $param =~ m/^{/) {
      $attr{$hash->{NAME}}{mapping} = $param ." ". join( " ", @params );
      $hash->{DEF} =~ s/\s*[{].*$//g;
      last;
    } else {
      my @device = split(":", $param);

      if( defined($defs{$device[0]}) ) {
        $list{$device[0]} = 1;
        push @devices, [@device];
      } else {
        foreach my $d (sort keys %defs) {
          next if( IsIgnored($d) );
          next if( $d !~ m/^$device[0]$/);
          $list{$d} = 1;
          push @devices, [$d,$device[1]];
        }
      }
    }
  }

  $hash->{CONTENT} = \%list;
  $hash->{DEVICES} = \@devices;
}

sub readingsGroup_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> readingsGroup <device>+"  if(@args < 3);

  my $name = shift(@args);
  my $type = shift(@args);

  readingsGroup_updateDevices($hash);

  $hash->{STATE} = 'Initialized';

  return undef;
}

sub readingsGroup_Undefine($$)
{
  my ($hash,$arg) = @_;

  return undef;
}

sub
readingsGroup_2html($)
{
  my($hash) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );

  my $d = $hash->{NAME};

  my $show_heading = !AttrVal( $d, "noheading", "0" );
  my $show_state = !AttrVal( $d, "nostate", "0" );
  my $show_time = !AttrVal( $d, "notime", "0" );

  my $separator = AttrVal( $d, "separator", ":" );
  my $style = AttrVal( $d, "style", "" );
  my $name_style = AttrVal( $d, "nameStyle", "" );
  my $value_style = AttrVal( $d, "valueStyle", "" );
  my $timestamp_style = AttrVal( $d, "timestampStyle", "" );

  my $mapping = AttrVal( $d, "mapping", undef);
  $mapping = eval $mapping if( $mapping );
  $mapping = undef if( ref($mapping) ne 'HASH' );

  my $devices = $hash->{DEVICES};

  my $ret;

  my $row = 1;
  $ret .= "<table>";
  $ret .= "<tr><td><div class=\"devType\"><a href=\"/fhem?detail=$d\">".AttrVal($d, "alias", $d)."</a></div></td></tr>" if( $show_heading );
  $ret .= "<tr><td><table $style class=\"block wide\">";
  foreach my $device (@{$devices}) {
    my $h = $defs{@{$device}[0]};
    my $regex = @{$device}[1];
    my $name = $h->{NAME};
    next if( !$h );

    if( $regex =~ m/\+(.*)/ ) {
      $regex = $1;

      my $now = gettimeofday();
      my $fmtDateTime = FmtDateTime($now);

      foreach my $n (sort keys %{$h}) {
        next if( $n =~ m/^\./);
        next if( defined($regex) &&  $n !~ m/^$regex$/);
        my $val = $h->{$n};

        my $r = ref($val);
        next if($r && ($r ne "HASH" || !defined($hash->{$n}{VAL})));

        my $v = FW_htmlEscape($val);

        $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
        $row++;

        my $name_style = $name_style;
        if(defined($name_style) && $name_style =~ m/^{.*}$/) {
          my $DEVICE = $name;
          my $READING = $n;
          my $VALUE = $v;
          $name_style = eval $name_style;
          $name_style = "" if( !$name_style );
        }
        my $value_style = $value_style;
        if(defined($value_style) && $value_style =~ m/^{.*}$/) {
          my $DEVICE = $name;
          my $READING = $n;
          my $VALUE = $v;
          $value_style = eval $value_style;
          $value_style = "" if( !$value_style );
        }

        my $m = "$name$separator$n";
        $m = $mapping->{$n} if( defined($mapping) && defined($mapping->{$n}) );
        $m = $mapping->{$name.".".$n} if( defined($mapping) && defined($mapping->{$name.".".$n}) );
        $m =~ s/\%DEVICE/$name/g;
        $m =~ s/\%READING/$n/g;
        $ret .= "<td><div $name_style class=\"dname\"><a href=\"/fhem?detail=$name\">$m</a></div></td>";

        $ret .= "<td><div $value_style\">$v</div></td>";
        $ret .= "<td><div></div>$fmtDateTime</td>" if( $show_time );
      }
    } else {
    foreach my $n (sort keys %{$h->{READINGS}}) {
      next if( $n =~ m/^\./);
      next if( $n eq "state" && !$show_state );
      next if( defined($regex) &&  $n !~ m/^$regex$/);
      my $val = $h->{READINGS}->{$n};

      if(ref($val)) {
        my ($v, $t) = ($val->{VAL}, $val->{TIME});
        $v = FW_htmlEscape($v);
        $t = "" if(!$t);

        $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
        $row++;

        my $name_style = $name_style;
        if(defined($name_style) && $name_style =~ m/^{.*}$/) {
          my $DEVICE = $name;
          my $READING = $n;
          my $VALUE = $v;
          $name_style = eval $name_style;
          $name_style = "" if( !$name_style );
        }
        my $value_style = $value_style;
        if(defined($value_style) && $value_style =~ m/^{.*}$/) {
          my $DEVICE = $name;
          my $READING = $n;
          my $VALUE = $v;
          $value_style = eval $value_style;
          $value_style = "" if( !$value_style );
        }

        my $m = "$name$separator$n";
        $m = $mapping->{$n} if( defined($mapping) && defined($mapping->{$n}) );
        $m = $mapping->{$name.".".$n} if( defined($mapping) && defined($mapping->{$name.".".$n}) );
        $m =~ s/\%DEVICE/$name/g;
        $m =~ s/\%READING/$n/g;
        $ret .= "<td><div $name_style class=\"dname\"><a href=\"/fhem?detail=$name\">$m</a></div></td>";

        $ret .= "<td><div $value_style informId=\"$d-$name.$n\">$v</div></td>";
        $ret .= "<td><div $timestamp_style informId=\"$d-$name.$n-ts\">$t</div></td>" if( $show_time );
      }
    }
    }
  }
  $ret .= "</table></td></tr>";
  $ret .= "</table>";
  $ret .= "</br>";

  return $ret;
}
sub
readingsGroup_detailFn()
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  return readingsGroup_2html($d);
}

sub
readingsGroup_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};

  return if($dev->{NAME} eq $name);

  my $devices = $hash->{DEVICES};

  my $max = int(@{$dev->{CHANGED}});
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));

    if( $dev->{NAME} eq "global" && $s =~ m/^RENAMED ([^ ]*) ([^ ]*)$/) {
      my ($old, $new) = ($1, $2);
      if( defined($hash->{CONTENT}{$old}) ) {

        $hash->{DEF} =~ s/(\s*)$old((:\S+)?\s*)/$1$new$2/g;
      }
      readingsGroup_updateDevices($hash);
    } elsif( $dev->{NAME} eq "global" && $s =~ m/^DELETED ([^ ]*)$/) {
      my ($name) = ($1);

      if( defined($hash->{CONTENT}{$name}) ) {

        $hash->{DEF} =~ s/(\s*)$name((:\S+)?\s*)/ /g;
        $hash->{DEF} =~ s/^ //;
        $hash->{DEF} =~ s/ $//;
      }
      readingsGroup_updateDevices($hash);
    } elsif( $dev->{NAME} eq "global" && $s =~ m/^DEFINED ([^ ]*)$/) {
      readingsGroup_updateDevices($hash);
    } else {
      next if(AttrVal($name,"disable", undef));

      next if (!$hash->{CONTENT}->{$dev->{NAME}});

      my @parts = split(/: /,$s);
      my $reading = shift @parts;
      my $value   = join(": ", @parts);

      $reading = "" if( !defined($reading) );
      next if( $reading =~ m/^\./);
      $value = "" if( !defined($value) );
      if( $value eq "" ) {
        next if( AttrVal( $name, "nostate", "0" ) );

        $reading = "state";
        $value = $s;
      }

      foreach my $device (@{$devices}) {
        my $h = $defs{@{$device}[0]};
        next if( !$h );
        next if( $dev->{NAME} ne $h->{NAME} );
        my $regex = @{$device}[1];
        next if( defined($regex) && $reading !~ m/^$regex$/);
        CommandTrigger( "", "$name $dev->{NAME}.$reading: $value" );
      }
    }
  }

  return undef;
}

sub
readingsGroup_Set($@)
{
  my ($hash, $name, $cmd, $param, @a) = @_;
  my $ret = "";

  return undef;
}

sub
readingsGroup_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];
  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];

  my $ret = "";
  if( $cmd eq "html" ) {
    return readingsGroup_2html($hash);
  }

  return undef;
  return "Unknown argument $cmd, choose one of html:noArg";
}

1;

=pod
=begin html

<a name="readingsGroup"></a>
<h3>readingsGroup</h3>
<ul>
  Displays a collection of readings from on or more devices.

  <br><br>
  <a name="readingsGroup_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; readingsGroup &lt;device&gt;[:regex] [&lt;device-2&gt;[:regex-2]] ... [&lt;device-n&gt;[:regex-n]]</code><br>
    <br>

    Notes:
    <ul>
      <li>If regex starts with a + it will be matched against the internal values of the device instead of the readinsg.</li>
      <li>For internal values no longpoll update is possible. Refresh the page to update the values.</li>
    </ul><br>

    Examples:
    <ul>
      <code>
        define batteries readingsGroup .*:battery</code><br>
      <br>
        <code>define temperatures readingsGroup s300th.*:temperature</code><br>
      <br>
        <code>define heizung readingsGroup t1:temperature t2:temperature t3:temperature<br>
        attr heizung notime 1<br>
        attr heizung mapping {'t1.temperature' => 'Vorlauf', 't2.temperature' => 'R&amp;uuml;cklauf', 't3.temperature' => 'Zirkulation'}</br>
        attr heizung style style="font-size:20px"<br>
      <br>
        define systemStatus readingsGroup sysstat<br>
        attr systemStatus notime 1<br>
        attr systemStatus nostate 1<br>
        attr systemStatus mapping { 'load' => 'Systemauslastung', 'temperature' => 'Systemtemperatur in &amp;deg;C'}<br>
      </code><br>
    </ul>
  </ul><br>

  <a name="readingsGroup_Set"></a>
    <b>Set</b>
    <ul>
    </ul><br>

  <a name="readingsGroup_Get"></a>
    <b>Get</b>
    <ul>
    </ul><br>

  <a name="readingsGroup_Attr"></a>
    <b>Attributes</b>
    <ul>
      <li>noheading<br>
        If set to 1 the readings table will have no heading.</li>
      <li>nostate<br>
        If set to 1 the state reading is excluded.</li>
      <li>notime<br>
        If set to 1 the reading timestamp is not displayed.</li>
      <li>mapping<br>
        A perl expression enclosed in {} that returns a hash that maps reading names to the displayed name.
        The Keys can be either the name of the reading or &lt;device&gt;.&lt;reading&gt;.
        %DEVICE and %READING are replaced by the device name and reading name respectively, e.g:<br>
          <code>attr temperatures mapping {temperature => "%DEVICE Temperatur"}</code>
        </li>
      <li>separator<br>
        The separator to use between the device name and the reading name if no mapping is given. Defaults to ':'
        a space can be enteread as <code>&amp;nbsp;</code></li>
      <li>style<br>
        Specify an HTML style for the readings table, e.g.:<br>
          <code>attr temperatures style style="font-size:20px"</code></li>
      <li>nameStyle<br>
        Specify an HTML style for the reading names, e.g.:<br>
          <code>attr temperatures nameStyle style="font-weight:bold"</code></li>
      <li>valueStyle<br>
        Specify an HTML style for the reading values, e.g.:<br>
          <code>attr temperatures valueStyle style="text-align:right"</code></li>
    </ul><br>

      The nameStyle and valueStyle attributes can also contain a perl expression enclosed in {} that returns the style string to use. The perl code can use $DEVICE,$READING and $VALUE, e.g.:<br>
    <ul>
          <code>attr batteries valueStyle {($VALUE ne "ok")?'style="color:red"':'style="color:green"'}</code><br>
          <code>attr temperatures valueStyle {($DEVICE =~ m/aussen/)?'style="color:green"':'style="color:red"'}</code>
    </ul>
      Note: The perl expressions are evaluated only once during html creation and will not reflect value updates with longpoll.
      Refresh the page to update the dynamic style.

</ul>

=end html
=cut
