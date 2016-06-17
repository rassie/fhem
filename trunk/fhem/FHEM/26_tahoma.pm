# $Id$
################################################################
#
#  Copyright notice
#
#  (c) 2014 mike3436 (mike3436@online.de)
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################ 
# $Id: 26_tahoma.pm
#
# 2014-08-01 V 0100 first Version using XML Interface 

package main;

use strict;
use warnings;

use Encode qw(encode_utf8);
use XML::Simple qw(:strict);

use LWP::UserAgent;
use LWP::ConnCache;
use HTTP::Cookies;  

sub tahoma_parseGetSetupPlaces($$);

my $hash_;

sub tahoma_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "tahoma_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "tahoma_Notify";
  $hash->{UndefFn}  = "tahoma_Undefine";
  $hash->{SetFn}    = "tahoma_Set";
  $hash->{GetFn}    = "tahoma_Get";
  $hash->{AttrFn}   = "tahoma_Attr";
  $hash->{AttrList} = "IODev ".
                      "debug:1 ".
                      "disable:1 ".
                      "interval ".
                      "logfile ".
                      "url ".
                      "userAgent ".
                      "proxy ";
  $hash->{AttrList} .= $readingFnAttributes;
}

#####################################

sub tahoma_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  my $subtype;
  my $name = $a[0];
  if( $a[2] eq "DEVICE" && @a == 4 ) {
    $subtype = "DEVICE";

    my $device = $a[3];
    my $fid = (split "/", $device)[-1];

    $hash->{device} = $device;
    $hash->{fid} = $fid;

    $hash->{INTERVAL} = 2;

    my $d = $modules{$hash->{TYPE}}{defptr}{"$fid"};
    return "device $device already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"$fid"} = $hash;

  } elsif( $a[2] eq "PLACE" && @a == 4 ) {
    $subtype = "PLACE";

    my $oid = $a[@a-1];
    my $fid = (split "-", $oid)[0];

    $hash->{oid} = $oid;
    $hash->{fid} = $fid;

    $hash->{INTERVAL} = 0;

    my $d = $modules{$hash->{TYPE}}{defptr}{"$fid"};
    return "place oid $oid already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"$fid"} = $hash;

  } elsif( $a[2] eq "SCENE" && @a == 4 ) {
    $subtype = "SCENE";

    my $oid = $a[@a-1];
    my $fid = (split "-", $oid)[0];

    $hash->{oid} = $oid;
    $hash->{fid} = $fid;

    $hash->{INTERVAL} = 0;

    my $d = $modules{$hash->{TYPE}}{defptr}{"$fid"};
    return "scene oid $oid already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"$fid"} = $hash;

  } elsif( $a[2] eq "ACCOUNT" && @a == 5 ) {
    $subtype = "ACCOUNT";

    my $username = $a[@a-2];
    my $password = $a[@a-1];

    $hash->{Clients} = ":tahoma:";

    $hash->{username} = $username;
    $hash->{password} = $password;

    $hash->{INTERVAL} = 2;

  } else {
    return "Usage: define <name> tahoma device\
       define <name> tahoma ACCOUNT username password\
       define <name> tahoma DEVICE id\
       define <name> tahoma SCENE oid username password\
       define <name> tahoma PLACE oid"  if(@a < 4 || @a > 5);
  }

  $hash->{NAME} = $name;
  $hash->{SUBTYPE} = $subtype;

  $hash->{STATE} = "Initialized";

  if( $init_done ) {
    tahoma_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
    tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
    tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "PLACE" );
    tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "SCENE" );
  }

  return undef;
}

sub tahoma_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  tahoma_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
  tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
  tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "PLACE" );
  tahoma_initDevice($hash) if( $hash->{SUBTYPE} eq "SCENE" );
}

sub tahoma_Undefine($$)
{
  my ($hash, $arg) = @_;

  delete( $modules{$hash->{TYPE}}{defptr}{"$hash->{device}"} ) if( $hash->{SUBTYPE} eq "DEVICE" );
  delete( $modules{$hash->{TYPE}}{defptr}{"$hash->{oid}"} ) if( $hash->{SUBTYPE} eq "PLACE" );
  delete( $modules{$hash->{TYPE}}{defptr}{"$hash->{oid}"} ) if( $hash->{SUBTYPE} eq "SCENE" );

  return undef;
}

sub tahoma_login($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_login";
  
  $hash->{logged_in} = undef;
  $hash->{url} = "https://www.tahomalink.com/enduser-mobile-web/externalAPI/";
  $hash->{url} = $attr{$name}{url} if (defined $attr{$name}{url});
  $hash->{userAgent} = "TaHoma/3.1 CFNetwork/548.1.4 Darwin/11.0.0";
  $hash->{userAgent} = $attr{$name}{userAgent} if (defined $attr{$name}{userAgent});
  $hash->{timeout} = 10;

  print "login start\n";
  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'login',
    data => {'userId' => $hash->{username} , 'userPassword'  => $hash->{password}},
    callback => \&tahoma_dispatch,
    nonblocking => 0,
  });
  return if (!$hash->{logged_in});
  
  my @startup_pages = ( 'getEndUser',
                        'getSetup',
                        'getActionGroups',
                        'getWeekPlanning',
                        'getScheduledExecutions',
                        'getHistory',
                        'getSensorTriggers',
                        'getUserPreferences',
                        'getSetupOptions',
                        'getAvailableProtocolsType',
                        'getActiveProtocolsType',
                        'getSetupQuota',
                        'getSetupDawnAndDuskTimes' );

  foreach my $page (@startup_pages) {
    my $subpage = "";
    $subpage = '?gatewayId='.$hash->{gatewayId} if (substr($page, -13, 13) eq 'ProtocolsType');
    $subpage = '?quotaId=smsCredit' if ($page eq 'getSetupQuota');
    tahoma_UserAgent_NonblockingGet({
      timeout => 10,
      noshutdown => 1,
      hash => $hash,
      page => $page,
      subpage => $subpage,
      callback => \&tahoma_dispatch,
      nonblocking => 0,
    });
    return if (!$hash->{logged_in});
  }
  
  tahoma_refreshState($hash, 0);
  tahoma_requestState($hash, 0);
  tahoma_getEvents($hash, 1);
}

sub tahoma_refreshState($$)
{
  my ($hash,$nonblocking) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_refreshState";

  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'refreshAllStates',
    callback => \&tahoma_dispatch,
    nonblocking => $nonblocking,
  });
}

sub tahoma_getEvents($$)
{
  my ($hash,$nonblocking) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_getEvents";

  if( !$hash->{logged_in} ) {
    tahoma_login($hash);
    return undef;
  }

  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'getEvents',
    callback => \&tahoma_dispatch,
    nonblocking => $nonblocking,
  });
}

sub tahoma_readStatusTimer($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my ($seconds) = gettimeofday();
  $hash->{refreshStateTimer} = $seconds + 10 if ( (!defined($hash->{refreshStateTimer})) || (!$hash->{logged_in}) );
  
  if( $seconds < $hash->{refreshStateTimer} )
  {
    Log3 $name, 4, "$name: refreshing event";
    tahoma_getEvents($hash, 1);
  }
  else
  {
    Log3 $name, 4, "$name: refreshing state";
    tahoma_refreshState($hash, 0);
    tahoma_requestState($hash, 1);
    $hash->{refreshStateTimer} = $seconds + 300;
  }

  InternalTimer(gettimeofday()+2, "tahoma_readStatusTimer", $hash, 0);
}

sub tahoma_connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_connect";

  RemoveInternalTimer($hash);
  tahoma_login($hash);

  my ($seconds) = gettimeofday();
  $hash->{refreshStateTimer} = $seconds + 10;
  tahoma_readStatusTimer($hash);
}

sub tahoma_initDevice($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $subtype = $hash->{SUBTYPE};

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  my $device;
  if( $hash->{device} ) {
    $device = tahoma_getDeviceDetail( $hash, $hash->{device} );
    #Log3 $name, 4, Dumper($device);
  } elsif( $hash->{oid} ) {
    $device = tahoma_getDeviceDetail( $hash, $hash->{oid} );
    #Log3 $name, 4, Dumper($device);
  }

  if( $device && $subtype eq 'DEVICE' ) {
    Log3 $name, 4, "$name: I/O device is label=".encode_utf8($device->{label});
    $hash->{inType} = $device->{type};
    $hash->{inLabel} = encode_utf8($device->{label});
    $hash->{inControllable} = $device->{controllable};
    $hash->{inPlaceOID} = $device->{placeOID};
  }
  elsif( $device && $subtype eq 'PLACE' ) {
    Log3 $name, 4, "$name: I/O device is label=".encode_utf8($device->{label});
    $hash->{inType} = $device->{type};
    $hash->{inLabel} = encode_utf8($device->{label});
    $hash->{inOID} = $device->{oid};
  }
  elsif( $device && $subtype eq 'SCENE' ) {
    Log3 $name, 4, "$name: I/O device is label=".encode_utf8($device->{label});
    $hash->{inType} = $device->{type};
    $hash->{inLabel} = encode_utf8($device->{label});
    $hash->{inOID} = $device->{oid};
  }


  my $state_format;
  if( $device->{state} ) {
    delete($hash->{dataTypes});
    delete($hash->{helper}{dataTypes});

    my @reading_names = ();
    foreach my $type (@{$device->{state}}) {
      $hash->{dataTypes} = "" if ( !defined($hash->{dataTypes}) );
      $hash->{dataTypes} .= "," if ( $hash->{dataTypes} );
      $hash->{dataTypes} .= $type->{name};
      #Log3 $name, 4, "state=$type->{name}";

      push @reading_names, lc($type);

      if( $type->{name} eq "core:ClosureState" ) {
        $state_format .= " " if( $state_format );
        $state_format .= "Closure: ClosureState";
      } elsif( $type->{name} eq "core:OpenClosedState" ) {
        $state_format .= " " if( $state_format );
        $state_format .= "Closed: OpenClosedState";
      }
    }

    $hash->{helper}{readingNames} = \@reading_names;
  }
  #$attr{$name}{stateFormat} = $state_format if( !defined( $attr{$name}{stateFormat} ) && defined($state_format) );
}

sub tahoma_getDevices($;$)
{
  my ($hash,$blocking) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "tahoma_getDevices";

  tahoma_UserAgent_NonblockingGet({
    noshutdown => 1,
    hash => $hash,
    page => 'getSetup',
    callback => \&tahoma_dispatch,
    nonblocking => !$blocking,
  });

  return $hash->{helper}{devices};
}

sub tahoma_getDeviceDetail($$)
{
  my ($hash,$id) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "getDeviceDetails $id";

  $hash = $hash->{IODev} if( defined($hash->{IODev}) );

  foreach my $device (@{$hash->{helper}{devices}}) {
    return $device if( defined($device->{deviceURL}) && ($device->{deviceURL} eq $id)  );
    return $device if( defined($device->{oid}) && ($device->{oid} eq $id) );
  }

  Log3 $name, 4, "getDeviceDetails $id not found";
  
  return undef;
}

sub tahoma_requestState($$)
{
  my ($hash,$nonblocking) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "tahoma_requestState";

  my $data = '<?xml version="1.0" encoding="UTF-8"?><statesRequest>';
  
  foreach my $device (@{$hash->{helper}{devices}}) {
    if( defined($device->{deviceURL}) && defined($device->{state}) )
    {
      $data .= '<device deviceURL="'.$device->{deviceURL}.'">';
      foreach my $state (@{$device->{state}}) {
        $data .= '<state name="' . $state->{name} . '"/>';
      }
      $data .= '</device>';
    }
  }
  
  $data .= '</statesRequest>';

  Log3 $name, 5, "tahoma_requestState data=".$data;
  
  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash,
    page => 'getStates',
    data => encode_utf8($data),
    callback => \&tahoma_dispatch,
    nonblocking => $nonblocking,
  });
  
}

sub tahoma_getDeviceList($$$)
{
  my ($hash,$oid,$deviceList) = @_;
  #print "tahoma_getDeviceList oid=$oid devices=".scalar @{$deviceList}."\n";
  
  my $devices = $hash->{helper}{devices};
  foreach my $device (@{$devices}) {
    if ( defined($device->{deviceURL}) && defined($device->{placeOID}) && defined($device->{type}) ) {
      if (($device->{type} eq '1') && ($device->{placeOID} eq $oid)) {
        push ( @{$deviceList}, { device => $device->{deviceURL}, type => $device->{type} } ) ;
        #print "tahoma_getDeviceList url=$device->{deviceURL} devices=".scalar @{$deviceList}."\n";
      }
    } elsif ( defined($device->{oid}) && defined($device->{place}) ) {
      if ($device->{oid} eq $oid)
      {
        foreach my $place (@{$device->{place}}) {
          tahoma_getDeviceList($hash,$place->{oid},$deviceList);
        }
      }
    }
  }
}

sub tahoma_applyRequest($$$)
{
  my ($hash,$nonblocking,$value) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "tahoma_applyRequest";

  if ( !defined($hash->{IODev}) || !(defined($hash->{device}) || defined($hash->{oid})) || !defined($hash->{inLabel}) || !defined($hash->{inType}) ) {
    Log3 $name, 4, "tahoma_applyRequest failed - define error";
    return;
  }
  
  my @devices = ();
  if ( defined($hash->{device}) ) {
    push ( @devices, { device => $hash->{device}, type => $hash->{inType} } );
  } else {
    tahoma_getDeviceList($hash->{IODev},$hash->{oid},\@devices);
  }

  Log3 $name, 4, "tahoma_applyRequest devices=".scalar @devices;
  foreach my $dev (@devices) {
    Log3 $name, 4, "tahoma_applyRequest devices=$dev->{device} type=$dev->{type}";
  }
  
  return if (scalar @devices < 1);
  
  my $data = '<?xml version="1.0" encoding="UTF-8"?><applyRequest><actionGroup label="';
  $data .= $hash->{inLabel}.' - Positionieren auf '.$value.' % - iPhone">';
  foreach my $device (@devices) {
    $data .= '<action deviceURL="'.$device->{device}.'">';
    $data .= '<command name="setClosure"><parameter value="'.$value.'" type="'.$device->{type}.'"/></command></action>';
  }
  $data .= '</actionGroup></applyRequest>';

  Log3 $name, 3, "tahoma_applyRequest data=".$data;
  
  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash->{IODev},
    page => 'apply',
    data => encode_utf8($data),
    callback => \&tahoma_dispatch,
    nonblocking => $nonblocking,
  });
}

sub tahoma_scheduleActionGroup($$$)
{
  my ($hash,$nonblocking,$delay) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "tahoma_scheduleActionGroup";

  if ( !defined($hash->{IODev}) || !defined($hash->{oid}) ) {
    Log3 $name, 3, "tahoma_scheduleActionGroup failed - define error";
    return;
  }

  $delay = 0 if(!defined($delay));
  
  tahoma_UserAgent_NonblockingGet({
    timeout => 10,
    noshutdown => 1,
    hash => $hash->{IODev},
    page => 'scheduleActionGroup',
    subpage => '?oid='.$hash->{oid}.'&delay='.$delay,
    callback => \&tahoma_dispatch,
    nonblocking => $nonblocking,
  });
}

sub tahoma_dispatch($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if( $err ) {
    Log3 $name, 2, "$name: http request failed: $err";
    $hash->{logged_in} = 0;
  } elsif( $data ) {
    $data =~ tr/\r\n//d;
    Log3 $name, 4, "$name: tahoma_dispatch page=$param->{page} dataLen=".length $data;
    Log3 $name, (length $data > 120)?3:5, "$name: tahoma_dispatch data=".encode_utf8($data);

    my $xml = XMLin($data, KeyAttr => { }, ForceArray => [ 'gateway', 'state', 'place', 'device', 'event' ], keeproot => 1);

    if( $xml->{errorResponse} ) {
      $hash->{lastError} = $xml->{errorResponse}{message};
      $hash->{logged_in} = 0;
      return;
    }

    if( $param->{page} eq 'getEvents' ) {
      tahoma_parseGetEvents($hash,$xml);
    } elsif( $param->{page} eq 'apply' ) {
      tahoma_parseApplyRequest($hash,$xml);
    } elsif( $param->{page} eq 'getSetup' ) {
      tahoma_parseGetSetup($hash,$xml);
    } elsif( $param->{page} eq 'refreshAllStates' ) {
      tahoma_parseRefreshAllStates($hash,$xml);
    } elsif( $param->{page} eq 'getStates' ) {
      tahoma_parseGetStates($hash,$xml);
    } elsif( $param->{page} eq 'login' ) {
      tahoma_parseLogin($hash,$xml);
    } elsif( $param->{page} eq 'getActionGroups' ) {
      tahoma_parseGetActionGroups($hash,$xml);
    } elsif( $param->{page} eq 'scheduleActionGroup' ) {
      tahoma_parseScheduleActionGroup($hash,$xml);
    }
    
  }
}

sub tahoma_autocreate($)
{
  my($hash) = @_;
  my $name = $hash->{NAME};

  if( !$hash->{helper}{devices} ) {
    tahoma_getDevices($hash);
    return undef;
  }

  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "autocreate");
    return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
  }
  
  print "tahoma_autocreate begin\n";

  my $autocreated = 0;

  my $devices = $hash->{helper}{devices};
  foreach my $device (@{$devices}) {
    my ($id, $fid, $devname, $define);
    if ($device->{deviceURL}) {
      $id = $device->{deviceURL};
      $fid = (split("/",$id))[-1];
      $devname = "tahoma_". $fid;
      $define = "$devname tahoma DEVICE $id";
      if( defined($modules{$hash->{TYPE}}{defptr}{"$fid"}) ) {
        Log3 $name, 4, "$name: device '$fid' already defined";
        next;
      }
    } elsif ( $device->{oid} ) {
      $id = $device->{oid};
      $fid = (split("-",$id))[0];
      $devname = "tahoma_". $fid;
      $define = "$devname tahoma PLACE $id" if (!defined $device->{action});
      $define = "$devname tahoma SCENE $id" if (defined $device->{action});
      if( defined($modules{$hash->{TYPE}}{defptr}{"$fid"}) ) {
        Log3 $name, 4, "$name: device '$fid' already defined";
        next;
      }
    }

    Log3 $name, 3, "$name: create new device '$devname' for device '$id'";
    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias $device->{uiClass} ".encode_utf8($device->{label})) if( defined($device->{label}) && defined($device->{uiClass}) );
      $cmdret= CommandAttr(undef,"$devname alias room ".encode_utf8($device->{label})) if( defined($device->{label}) && defined($device->{oid}) && !defined($device->{action}) );
      $cmdret= CommandAttr(undef,"$devname alias scene ".encode_utf8($device->{label})) if( defined($device->{label}) && defined($device->{oid}) && defined($device->{action}) );
      $cmdret= CommandAttr(undef,"$devname room tahoma");
      $cmdret= CommandAttr(undef,"$devname IODev $name");
      $cmdret= CommandAttr(undef,"$devname webCmd dim") if( defined($device->{uiClass}) && ($device->{uiClass} eq "RollerShutter") );

      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );
  print "tahoma_autocreate end, new=$autocreated\n";
}

sub tahoma_parseLogin($$)
{
  my($hash, $xml) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseLogin";
  if (defined $xml->{errorResponse}) {
    $hash->{logged_in} = 0;
    $hash->{STATE} = $xml->{errorResponse}{message};
  } else {
    $hash->{logged_in} = 1;
  }
}

sub tahoma_parseGetEvents($$)
{
  my($hash, $xml) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: tahoma_parseGetEvent";

  $hash->{refresh_event} = $xml;

  if( $hash->{logged_in} ) {
    $hash->{STATE} = "Connected";
  } else {
    $hash->{STATE} = "Disconnected";
  }
  
  if( defined($xml->{eventPollResponse}{events}{event}) ) {
    #print Dumper($xml);
    foreach my $devices ( @{$xml->{eventPollResponse}{events}{event}} ) {
      if( defined($devices->{deviceURL}) ) {
        #print "\nDevice=$devices->{deviceURL} found\n";
        my $id = $devices->{deviceURL};
        my $fid = (split("/",$id))[-1];
        my $devname = "tahoma_". $fid;
        my $d = $modules{$hash->{TYPE}}{defptr}{"$fid"};
        if( defined($d) && $d->{NAME} eq $devname )
        {
          #print "\nDevice=$devices->{deviceURL} updated\n";
          readingsBeginUpdate($d);
          foreach my $state (@{$devices->{deviceStates}{state}}) {
            #print "$devname $state->{name} = $state->{value}\n";
            readingsBulkUpdate($d, "state", "dim".$state->{value}) if ($state->{name} eq "core:ClosureState");
            readingsBulkUpdate($d, "devicestate", $state->{value}) if ($state->{name} eq "core:OpenClosedState");
            #readingsBulkUpdate($d, (split(":",$state->{name}))[-1], encode_utf8($state->{value}));
          }
          my ($seconds) = gettimeofday();
          readingsBulkUpdate( $d, ".lastupdate", $seconds, 0 );
          readingsEndUpdate($d,1);
        }
      }
    }
  }
  
}

sub tahoma_parseApplyRequest($$)
{
  my($hash, $xml) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseApplyRequest";
  if (defined($xml->{applyResponse}{apply}{execId})) {
    $hash->{InExecId} = $xml->{applyResponse}{apply}{execId};
  } else {
    $hash->{InExecId} = "undefined";
  }
}

sub tahoma_parseGetSetup($$)
{
  my($hash, $xml) = @_;
  my $name = $hash->{NAME};
  
  $hash->{gatewayId} = $xml->{setupResponse}{setup}{gateways}{gateway}[0]{gatewayId};

  my @devices = ();
  foreach my $device (@{$xml->{setupResponse}{setup}{devices}{device}}) {
    push( @devices, $device );
  }
  
  $hash->{helper}{devices} = \@devices;

  if ($xml->{setupResponse}{setup}{place}) {
    my $places = $xml->{setupResponse}{setup}{place};
    #Log3 $name, 4, "$name: tahoma_parseGetSetup places= " . Dumper($places);
    tahoma_parseGetSetupPlaces($hash, $places);
  }

  tahoma_autocreate($hash);
}

sub tahoma_parseGetSetupPlaces($$)
{
  my($hash, $places) = @_;
  my $name = $hash->{NAME};
  #Log3 $name, 4, "$name: tahoma_parseGetSetupPlaces " . Dumper($places);

  my $devices = $hash->{helper}{devices};
  
  if (ref $places eq 'ARRAY') {
    #Log3 $name, 4, "$name: tahoma_parseGetSetupPlaces isArray";
    foreach my $place (@{$places}) {
      push( @{$devices}, $place );
      my $placesNext = $place->{place};
      tahoma_parseGetSetupPlaces($hash, $placesNext ) if ($placesNext);
    }
  }
  else {
    #Log3 $name, 4, "$name: tahoma_parseGetSetupPlaces isScalar";
    push( @{$devices}, $places );
    my $placesNext = $places->{place};
    tahoma_parseGetSetupPlaces($hash, $placesNext) if ($placesNext);
  }

}

sub tahoma_parseGetActionGroups($$)
{
  my($hash, $xml) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseGetActionGroups";
  
  my $devices = $hash->{helper}{devices};
  foreach my $action (@{$xml->{actionGroupResponse}{actionGroup}}) {
    push( @{$devices}, $action );
  }
  tahoma_autocreate($hash);
}

sub tahoma_parseRefreshAllStates($$)
{
  my($hash, $xml) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseRefreshAllStates";
}

sub tahoma_parseGetStates($$)
{
  my($hash, $states) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseGetStates";

  if( defined($states->{statesResponse}) ) {
    foreach my $devices ( @{$states->{statesResponse}{device}} ) {
      if( defined($devices->{deviceURL}) ) {
        my $id = $devices->{deviceURL};
        my $fid = (split("/",$id))[-1];
        my $devname = "tahoma_". $fid;
        my $d = $modules{$hash->{TYPE}}{defptr}{"$fid"};
        if( defined($d) && $d->{NAME} eq $devname )
        {
          readingsBeginUpdate($d);
          foreach my $state (@{$devices->{state}}) {
            readingsBulkUpdate($d, "state", "dim".$state->{value}) if ($state->{name} eq "core:ClosureState");
            readingsBulkUpdate($d, "devicestate", $state->{value}) if ($state->{name} eq "core:OpenClosedState");
            #readingsBulkUpdate($d, (split(":",$state->{name}))[-1], encode_utf8($state->{value}));
          }
          my ($seconds) = gettimeofday();
          readingsBulkUpdate( $d, ".lastupdate", $seconds, 0 );
          readingsEndUpdate($d,1);
        }
      }
    }
  }
}

sub tahoma_parseScheduleActionGroup($$)
{
  my($hash, $xml) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 4, "$name: tahoma_parseScheduleActionGroup";
}

sub tahoma_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list;
  if( $hash->{SUBTYPE} eq "DEVICE" ) {
    $list = "updateAll:noArg";

    if( $cmd eq "updateAll" ) {
      my ($seconds) = gettimeofday();
      $hash->{refreshStateTimer} = $seconds;
      return undef;
    }

  } elsif( $hash->{SUBTYPE} eq "SCENE"
      || $hash->{SUBTYPE} eq "PLACE" ) {
    $list = "";

  } elsif( $hash->{SUBTYPE} eq "ACCOUNT" ) {
    $list = "devices:noArg";

    if( $cmd eq "devices" ) {
      my $devices = tahoma_getDevices($hash,1);
      my $ret;
      foreach my $device (@{$devices}) {
        $ret .= "$device->{deviceURL}\t".encode_utf8($device->{label})."\t$device->{uiClass}\t$device->{controllable}\t\n" if ($device->{deviceURL});
        $ret .= "$device->{oid}\t".encode_utf8($device->{label})."\n" if ($device->{oid});
      }

      $ret = "id\t\t\t\tname\t\t\tuiClass\t\tcontrollable\n" . $ret if( $ret );
      $ret = "no devices found" if( !$ret );
      return $ret;
    }
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub tahoma_Set($$@)
{
  my ($hash, $name, $cmd, $val) = @_;

  my $list = "";
  if( $hash->{SUBTYPE} eq "DEVICE" ||
      $hash->{SUBTYPE} eq "PLACE" ) {
    $list = "dim:slider,0,1,100";

    if( $cmd eq "dim" ) {
      #if( $hash->{SUBTYPE} eq "DEVICE" ) {
        tahoma_applyRequest($hash,1,$val);
      #}
      return undef;
    }
  }
  
  if( $hash->{SUBTYPE} eq "SCENE") {
    $list = "start:noArg startAt";

    if( $cmd eq "start" ) {
      tahoma_scheduleActionGroup($hash,1,0);
      return undef;
    }
    
    if( $cmd eq "startAt" ) {
      tahoma_scheduleActionGroup($hash,1,$val);
      return undef;
    }
  }
  
  return "Unknown argument $cmd, choose one of $list";
}

sub tahoma_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval");
  $attrVal = 60*5 if($attrName eq "interval" && $attrVal < 60*5 && $attrVal != 0);

  if( $attrName eq "interval" ) {
    my $hash = $defs{$name};
    $hash->{INTERVAL} = $attrVal;
    $hash->{INTERVAL} = 60*5 if( !$attrVal );
  } elsif( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    RemoveInternalTimer($hash);
    if( $cmd eq "set" && $attrVal ne "0" ) {
    } else {
      $attr{$name}{$attrName} = 0;
    }
  }

  if( $cmd eq "set" ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}

sub tahoma_UserAgent_NonblockingGet($)
{
	my ($param) = @_;
  my ($hash) = $param->{hash};
  return if (!defined $hash);

  my $name = $hash->{NAME};
  Log3 $name, 5, "tahoma_UserAgent_NonblockingGet page=$param->{page}";
  
  my $agent = $hash->{socket};
  if (!defined $agent)
  {
    $agent = LWP::UserAgent->new(
      cookie_jar => HTTP::Cookies->new(hide_cookie2 => 1),
      requests_redirectable => [ 'GET', 'HEAD', 'POST' ]
    );
    $hash->{socket} = $agent;

    my $proxy = $attr{$name}{proxy};
    my $userAgent = $hash->{userAgent};
    $agent->agent("$userAgent") if (defined $userAgent);
    $agent->default_header('Accept-Language' => "de-de");
    $agent->default_header('Accept-Encoding' => "gzip, deflate");
    $agent->proxy(['http', 'https'], "$proxy") if (defined $proxy);
    # keep alive
    $agent->conn_cache(LWP::ConnCache->new());

    Log3 $name, 4, "tahoma_UserAgent_NonblockingGet create userAgent $userAgent, proxy=$proxy";
  }
  
  my $response = "";
  my $url = $hash->{url} . $param->{page};
  $url .= $param->{subpage} if (defined $param->{subpage});
  $url .= '.xml' if (substr($url,0,4) eq 'file');

  my $nonblocking = $param->{nonblocking} && !(substr($url,0,4) eq 'file');

  if ($param->{data} && !(substr($url,0,4) eq 'file'))
  {
    my $data = $param->{data};
    if (ref $data eq ref {}) {
      if (!$nonblocking) {
        $response = $agent->post( $url, $data );
      } else {
        $response = $agent->post( $url, $data, ':content_cb' => sub()
          {
            my ($content, $response, $protocol, $entry) = @_;
            $param->{callback}($param, undef, $content);
            return;
          } );
      }
    } else {
      if (!$nonblocking) {
        $response = $agent->post( $url, content => $data );
      } else {
        $response = $agent->post( $url, content => $data, ':content_cb' => sub()
          {
            my ($content, $response, $protocol, $entry) = @_;
            $param->{callback}($param, undef, $content);
            return;
          } );
      }
    }
  } else {
      if (!$nonblocking) {
        $response = $agent->get( $url );
      } else {
        $response = $agent->get( $url, ':content_cb' => sub()
          {
            my ($content, $response, $protocol, $entry) = @_;
            $param->{callback}($param, undef, $content);
            return;
          } );
      }
  }
  return if ($nonblocking);
  
  my ($err,$data);
  if ($response->is_success)
  {
    $err = "";
    $data = $response->decoded_content();
    
  } else {
    $err = $response->message;
    $data = "";
  }

	$param->{callback}($param, $err, $data) if($param->{callback});
}



1;

=pod
=begin html

<a name="tahoma"></a>
<h3>tahoma</h3>
<ul>
  xxx<br><br>

  Notes:
  <ul>
    <li>XML::Simple has to be installed on the FHEM host.</li>
  </ul><br>

  <a name="tahoma_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; tahoma ACCOUNT &lt;username&gt; &lt;password&gt;</code><br>
    <code>define &lt;name&gt; tahoma DEVICE &lt;DeviceURL&gt;</code><br>
    <code>define &lt;name&gt; tahoma PLACE &lt;oid&gt;</code><br>
    <code>define &lt;name&gt; tahoma SCENE &lt;oid&gt;</code><br>
    <br>

    Defines a tahoma device.<br><br>
    If a tahoma device of the type ACCOUNT is created, all other devices acessable by the tahoma gateway are automaticaly created.
    <br>

    Examples:
    <ul>
      <code>define tahomaDev tahoma ACCOUNT abc@test.com myPassword </code><br>
      <code>define tahomaD01 tahoma DEVICE io://0234-5678-9012/23234545</code><br>
      <code>define tahomaP01 tahoma PLACE abc12345-0a23-0b45-0c67-d5e6f7a1b2c3</code><br>
      <code>define tahomaS01 tahoma SCENE 4ef30a23-0b45-0c67-d5e6-f7a1b2c32e3f</code><br>
    </ul>
  </ul><br>
</ul>

=end html
=cut
