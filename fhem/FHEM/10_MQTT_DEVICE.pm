##############################################
#
# fhem bridge to mqtt (see http://mqtt.org)
#
# Copyright (C) 2014 Norbert Truchsess
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
# $Id$
#
##############################################

use strict;
use warnings;
use GPUtils qw(:all);

use Net::MQTT::Constants;
use Net::MQTT::Message;

my %sets = (
);

my %gets = (
  "version"   => "",
  "readings"  => ""
);

my %qos = map {qos_string($_) => $_} (MQTT_QOS_AT_MOST_ONCE,MQTT_QOS_AT_LEAST_ONCE,MQTT_QOS_EXACTLY_ONCE);

sub MQTT_DEVICE_Initialize($) {

  my $hash = shift @_;

  # Consumer
  $hash->{DefFn}    = "MQTT_DEVICE_Define";
  $hash->{UndefFn}  = "MQTT_DEVICE_Undef";
  #$hash->{SetFn}    = "MQTT_DEVICE_Set";
  $hash->{GetFn}    = "MQTT_DEVICE_Get";
  $hash->{NotifyFn} = "MQTT_DEVICE_Notify";
  $hash->{AttrFn}   = "MQTT_DEVICE_Attr";
  
  $hash->{AttrList} =
    "IODev ".
    "qos:".join(",",keys %qos)." ".
    "publish-topic-base ".
    "publishState ".
    "publishReading_.* ".
    "subscribeSet ".
    "subscribeSet_.* ".
    $main::readingFnAttributes;
}

sub MQTT_DEVICE_Define($$) {
  my ( $hash, $def ) = @_;

  $hash->{NOTIFYDEV} = $hash->{DEF};
  $hash->{qos} = MQTT_QOS_AT_MOST_ONCE;
  $hash->{subscribe} = [];
  if ($main::init_done) {
    return MQTT_DEVICE_Start($hash);
  } else {
    return undef;
  }
}

sub MQTT_DEVICE_Undef($) {
  MQTT_DEVICE_Stop(shift);
}

sub MQTT_DEVICE_Get($$@) {
  my ($hash, $name, $command) = @_;
  return "Need at least one parameters" unless (defined $command);
  return "Unknown argument $command, choose one of " . join(" ", sort keys %gets)
    unless (defined($gets{$command}));

  COMMAND_HANDLER: {
    # populate dynamically from keys %{$defs{$sdev}{READINGS}}
    $command eq "readings" and do {
      my $base = AttrVal($name,"publish-topic-base","/$hash->{DEF}/");
      foreach my $reading (keys %{$main::defs{$hash->{DEF}}{READINGS}}) {
        unless (defined main::AttrVal($name,"publishReading_$reading",undef)) {
          main::CommandAttr($hash,"$name publishReading_$reading $base$reading");
        }
      };
      last;
    };
  };
}

sub MQTT_DEVICE_Notify() {
  my ($hash,$dev) = @_;

  main::Log3($hash->{NAME},5,"Notify for $dev->{NAME}");
  foreach my $event (@{$dev->{CHANGED}}) {
    $event =~ /^([^:]+)(: )?(.*)$/;
    main::Log3($hash->{NAME},5,"$event, '".((defined $1) ? $1 : "-undef-")."', '".((defined $3) ? $3 : "-undef-")."'");
    if (defined $3 and $3 ne "") {
      if (defined $hash->{publishReadings}->{$1}) {
        MQTT_send_publish($hash->{IODev}, topic => $hash->{publishReadings}->{$1}, message => $3, qos => $hash->{qos});
        readingsSingleUpdate($hash,"transmission-state","publish sent",1);
      }
    } else {
      if (defined $hash->{publishState}) {
        MQTT_send_publish($hash->{IODev}, topic => $hash->{publishState}, message => $1, qos => $hash->{qos});
        readingsSingleUpdate($hash,"transmission-state","publish sent",1);
      }
    }
  }
}

sub MQTT_DEVICE_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;

  my $hash = $main::defs{$name};
  ATTRIBUTE_HANDLER: {
    $attribute =~ /^subscribeSet(_?)(.*)/ and do {
      if ($command eq "set") {
        $hash->{subscribeSets}->{$value} = $2;
        push @{$hash->{subscribe}},$value unless grep {$_ eq $value} @{$hash->{subscribe}};
        if ($main::init_done) {
          if (my $mqtt = $hash->{IODev}) {;
            my $msgid = MQTT_send_subscribe($mqtt,
              topics => [[$value => $hash->{qos} || MQTT_QOS_AT_MOST_ONCE]],
            );
            $hash->{message_ids}->{$msgid}++;
            readingsSingleUpdate($hash,"transmission-state","subscribe sent",1)
          }
        }
      } else {
        if ($main::init_done) {
          if (my $mqtt = $hash->{IODev}) {;
            my $msgid = MQTT_send_unsubscribe($mqtt,
              topics => [$value],
            );
            $hash->{message_ids}->{$msgid}++;
          }
        }
        delete $hash->{subscribeSets}->{$value};
        $hash->{subscribe} = [grep { $_ != $value } @{$hash->{subscribe}}];
      }
      last;
    };
    $attribute eq "publishState" and do {
      if ($command eq "set") {
        $hash->{publishState} = $value;
      } else {
        delete $hash->{publishState};
      }
      last;
    };
    $attribute =~ /^publishReading_(.+)$/ and do {
      if ($command eq "set") {
        $hash->{publishReadings}->{$1} = $value;
      } else {
        delete $hash->{publishReadings}->{$1};
      }
      last;
    };
    $attribute eq "qos" and do {
      if ($command eq "set") {
        $hash->{qos} = $qos{$value};
      } else {
        $hash->{qos} = MQTT_QOS_AT_MOST_ONCE;
      }
      last;
    };
    $attribute eq "IODev" and do {
      if ($command eq "set") {
      } else {
      }
      last;
    };
  }
}

sub MQTT_DEVICE_Start($) {
  my $hash = shift;
  my $name = $hash->{NAME};
  if (! (defined AttrVal($name,"stateFormat",undef))) {
    $main::attr{$name}{stateFormat} = "transmission-state";
  }
  if (@{$hash->{subscribe}}) {
    my $msgid = MQTT_send_subscribe($hash->{IODev},
      topics => [map { [$_ => $hash->{qos} || MQTT_QOS_AT_MOST_ONCE] } @{$hash->{subscribe}}],
    );
    $hash->{message_ids}->{$msgid}++;
    readingsSingleUpdate($hash,"transmission-state","subscribe sent",1)
  }
}

sub MQTT_DEVICE_Stop($) {
  my $hash = shift;
  if (@{$hash->{subscribe}}) {
    my $msgid = MQTT_send_unsubscribe($hash->{IODev},
      topics => [@{$hash->{subscribe}}],
    );
    $hash->{message_ids}->{$msgid}++;
    readingsSingleUpdate($hash,"transmission-state","unsubscribe sent",1)
  }
}

sub MQTT_DEVICE_onmessage($$$) {
  my ($hash,$topic,$message) = @_;
  if (defined (my $command = $hash->{subscribeSets}->{$topic})) {
    my @args = split ("[ \t]+",$message);
    if ($command eq "") {
      main::Log3($hash->{NAME},5,"calling DoSet($hash->{DEF}".(@args ? ",".join(",",@args) : ""));
      main::DoSet($hash->{DEF},@args);
    } else {
      main::Log3($hash->{NAME},5,"calling DoSet($hash->{DEF},$command".(@args ? ",".join(",",@args) : ""));
      main::DoSet($hash->{DEF},$command,@args);
    }
  }
}
1;

=pod
=begin html

<a name="MQTT_DEVICE"></a>
<h3>MQTT</h3>
<ul>
  acts as a bridge in between an fhem-device and <a href="http://mqtt.org">mqtt</a>-topics.
  <br><br>
  requires a <a href="#MQTT">MQTT</a>-device as IODev<br><br>
  
  Note: this module is based on module <a href="https://metacpan.org/pod/distribution/Net-MQTT/lib/Net/MQTT.pod>Net::MQTT</a>.
  <br><br>
  
  <a name="MQTT_DEVICEdefine"></a>
  <b>Define</b><br>
  <ul><br>
    <code>define &lt;name&gt; MQTT_DEVICE &lt;fhem-device-name&gt;</code> <br>
    Specifies the MQTT device.<br>
    &lt;fhem-device-name&gt; is the fhem-device this MQTT_DEVICE is linked to.<br>
    <br>
    <a name="MQTT_DEVICEget"></a>
    <b>Get</b>
    <ul>
      <li>
        <code>get &lt;name&gt; readings</code><br>
        retrieves all existing readings from fhem-device and configures (default-)topics for them.
      </li><br>
    </ul>
    <br><br>

    <a name="MQTTattr"></a>
    <b>Attributes</b><br>
    <ul>
      <li>...<br>
      ...
      </li>
    </ul>
  </ul>
</ul>
<br>

=end html
=cut
