# $Id$

package main;
use strict;
use warnings;

sub CommandExportdevice($$);

########################################
sub exportdevice_Initialize($$) {
    my %hash = (
        Fn  => "CommandExportdevice",
        Hlp => "<device>",
    );
    $cmds{exportdevice} = \%hash;
}

########################################
sub CommandExportdevice($$) {
    my ( $cl, $param ) = @_;
    my @a     = split( "[ \t][ \t]*", $param );
    my $quote = 0;
    my $str   = "";

    return "Usage: exportdevice [devspec] [quote]"
      if ( $a[0] eq "?" );

    $quote = 1
      if ( $a[0] eq "quote" || $a[1] eq "quote" );

    $a[0] = ".*"
      if ( int(@a) < 1 || $a[0] eq "quote" );

    my $mname = "";
    foreach my $dev ( devspec2array( $a[0], $cl ) ) {
        next if ( !$defs{$dev} );

        # module header (only once)
        if ( $mname ne $defs{$dev}{TYPE} ) {
            $mname = $defs{$dev}{TYPE};
            my $ver = fhem "version $defs{$dev}{TYPE}";
            $ver =~ s/\n\n+/\n# /g;
            $ver =~ s/^/# /g;
            $str .= "\n\n# TYPE: $defs{$dev}{TYPE}\n$ver\n\n";
        }

        # device definition
        if ( $dev ne "global" ) {
            my $def = $defs{$dev}{DEF};
            if ( defined($def) ) {
                if ($quote) {
                    $def =~ s/;/;;/g;
                    $def =~ s/\n/\\\n/g;
                }
                $str .= "define $dev $defs{$dev}{TYPE} $def\n";
            }
            else {
                $str .= "define $dev $defs{$dev}{TYPE}\n";
            }
        }

        # device attributes
        foreach my $a (
            sort {
                return -1
                  if ( $a eq "userattr" );    # userattr must be first
                return 1 if ( $b eq "userattr" );
                return $a cmp $b;
            } keys %{ $attr{$dev} }
          )
        {
            next
              if ( $dev eq "global"
                && ( $a eq "configfile" || $a eq "version" ) );
            my $val = $attr{$dev}{$a};
            if ($quote) {
                $val =~ s/;/;;/g;
                $val =~ s/\n/\\\n/g;
            }
            $str .= "attr $dev $a $val\n";
        }

        $str .= "\n";
    }

    my $return;
    $return = "#\n# Flat Export created by "
      if ( !$quote );
    $return = "#\n# Quoted Export created by "
      if ($quote);

    return
        $return
      . AttrVal( "global", "version", "fhem.pl:?/?" )
      . "\n# on "
      . TimeNow() . "\n#"
      . $str
      if ( $str ne "" );
    return "No device found: $a[0]";
}

1;

=pod
=item command
=item summary exports definition and attributes of devices
=item summary_DE exportiert die Definition und die Attribute von Ger&auml;ten
=begin html

<a name="exportdevice"></a>
<h3>exportdevice</h3>
<ul>
  <code>exportdevice [devspec] [quote]</code>
  <br><br>
  Output a complete device and attribute definition of FHEM devices. This is
  one of the few commands which return a string in a normal case.<br>
  See the <a href="#devspec">Device specification</a> section for details on
  &lt;devspec&gt;.
  <br><br>
  The output can be used for reimport using FHEMWEB or telnet command line.<br>
  The optional paramter "quote" may be added to receive fhem.cfg compatible output.
  <br><br>

  Example:
  <pre><code>  fhem> exportdevice Office

# 
# Export created by fhem.pl:12022/2016-08-21 
# on 2016-08-22 01:02:59 
# 


# TYPE: FS20 
# File       Rev   Last Change 
# 10_FS20.pm 11984 2016-08-19 12:47:50Z rudolfkoenig 

define Office FS20 1234 12 
attr Office userattr Light Light_map structexclude 
attr Office IODev CUL_0 
attr Office Light AllLights 
attr Office group Single Lights 
attr Office icon light_office 
attr Office model fs20st 
attr Office room Light

  </code></pre>
</ul>

=end html
=begin html_DE

<a name="exportdevice"></a>
<h3>exportdevice</h3>
<ul>
  <code>exportdevice [devspec] [quote]</code>
  <br><br>
  Gibt die komplette Definition und Attribute eines FHEM Ger&auml;tes aus. Dies
  ist eines der wenigen Befehle, die im Normalfall eine Zeichenkette ausgeben.<br>
  Siehe den Abschnitt &uuml;ber <a href="#devspec">Ger&auml;te-Spezifikation</a>
  f&uuml;r Details der &lt;devspec&gt;.
  <br><br>
  Die Ausgabe kann f&uuml;r einen Reimport mittels FHEMWEB oder Telnet
  Kommandozeile verwendet werden.<br>
  Der optionale Parameter "quote" kann genutzt werden, um eine fhem.cfg
  kompatible Ausgabe zu erhalten.
  <br><br>
  Beispiel:
  <pre><code>  fhem> exportdevice Office

# 
# Export created by fhem.pl:12022/2016-08-21 
# on 2016-08-22 01:02:59 
# 


# TYPE: FS20 
# File       Rev   Last Change 
# 10_FS20.pm 11984 2016-08-19 12:47:50Z rudolfkoenig 

define Office FS20 1234 12 
attr Office userattr Light Light_map structexclude 
attr Office IODev CUL_0 
attr Office Light AllLights 
attr Office group Single Lights 
attr Office icon light_office 
attr Office model fs20st 
attr Office room Light

  </code></pre>
</ul>

=end html_DE
=cut
