########################################################################################
#
# DoorPi.pm
#
# FHEM module to communicate with a Raspberry Pi door station
#
# Prof. Dr. Peter A. Henning, 2016
# 
# Version 0.4 - April 2016
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
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
########################################################################################

package main;

use strict;
use warnings;

use JSON; # imports encode_json, decode_json, to_json and from_json.

use vars qw{%attr %defs};

sub Log($$);

#-- globals on start

#-- these we may get on request
my %gets = (
  "config:noArg"    => "C",
  "history:noArg"   => "H"
);

########################################################################################
#
# DoorPi_Initialize
#
# Parameter hash
#
########################################################################################

sub DoorPi_Initialize ($) {
  my ($hash) = @_;
  
  $hash->{DefFn}    = "DoorPi_Define";
  $hash->{UndefFn}  = "DoorPi_Undef";
  $hash->{AttrFn}   = "DoorPi_Attr";
  $hash->{GetFn}    = "DoorPi_Get";
  $hash->{SetFn}    = "DoorPi_Set";
  #$hash->{NotifyFn} = "DoorPi_Notify";
  $hash->{InitFn}   = "DoorPi_Init";

  $hash->{AttrList}= "verbose ".
                     "language:de,en ".
                     "doorbutton dooropencmd doorlockcmd doorunlockcmd ".
                     "lightbutton lightoncmd lighttimercmd lightoffcmd ".
                     "dashlightbutton ".
                     $readingFnAttributes;
                     
  $hash->{FW_detailFn}  = "DoorPi_makeTable";
  $hash->{FW_summaryFn} = "DoorPi_makeTable";
  $hash->{FW_atPageEnd} = 1;
}

########################################################################################
#
# DoorPi_Define - Implements DefFn function
#
# Parameter hash, definition string
#
########################################################################################

sub DoorPi_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "[DoorPi] Define the IP address of DoorPi as a parameter"
    if(@a != 3);
  return "[DoorPi] Invalid IP address of DoorPi"
    if( $a[2] !~ m|\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?(\:\d+)?| );
  
  my $dev = $a[2];
  #-- split into parts
  my @tcp = split(':',$dev);
  #-- when the specified ip address contains a port already, use it as supplied
  if ( $tcp[1] ){
    $hash->{TCPIP} = $dev;
  }else{
    $hash->{TCPIP} = $tcp[0].":80";
  };
    
  @{$hash->{DATA}} = ();
  @{$hash->{HELPER}->{CMDS}} = ();
  
  $modules{DoorPi}{defptr}{$a[0]} = $hash;

  #-- InternalTimer blocks if init_done is not true
  my $oid = $init_done;
  $init_done = 1;
  readingsSingleUpdate($hash,"state","Initialized",1);
   
  DoorPi_GetConfig($hash);
  DoorPi_GetHistory($hash);
  $init_done = $oid;
  return undef;
}

#######################################################################################
#
# DoorPi_Undef - Implements UndefFn function
#
# Parameter hash = hash of device addressed
#
#######################################################################################

sub DoorPi_Undef ($) {
  my ($hash) = @_;
  delete($modules{DoorPi}{defptr}{NAME});
  #RemoveInternalTimer($hash);
  return undef;
}

#######################################################################################
#
# DoorPi_Attr - Set one attribute value
#
#  Parameter hash = hash of device addressed
#            a = argument array
#
########################################################################################

sub DoorPi_Attr(@) {
  my ($do,$name,$key,$value) = @_;
  
  my $hash = $main::defs{$name};
  my $ret;
  
  if ( $do eq "set") {
  	ARGUMENT_HANDLER: {
      $key eq "interval" and do {
        $hash->{interval} = $value;
        if ($main::init_done) {
          # WHAT ?
        }
        last;
      };
    }
  }
  return $ret;
}
  
########################################################################################
#
# DoorPi_Get -  Implements GetFn function 
#
# Parameter hash, argument array
#
########################################################################################

sub DoorPi_Get ($@) {
  my ($hash, @a) = @_;
  
  #-- check syntax
  return "[DoorPi] DoorPi_Get needs exactly one parameter" if(@a != 2);
  my $name = $hash->{NAME};
  my $v;

  #-- current configuration
  if($a[1] eq "config") {
    $v = DoorPi_GetConfig($hash);
  #-- history
  }elsif($a[1] eq "history") {
    $v = DoorPi_GetHistory($hash);                                         
  } else {
    return "DoorPi_Get with unknown argument $a[1], choose one of " . join(" ", sort keys %gets);
  }
  
  if(defined($v)) {
     Log GetLogLevel($name,2), "[DoorPi_Get] $a[1] error $v";
     return "$a[0] $a[1] => Error $v";
  }
  return "$a[0] $a[1] => ok";
}
 
########################################################################################
#
# DoorPi_Set - Implements SetFn function
#
# Parameter hash, a = argument array
#
########################################################################################

sub DoorPi_Set ($@) {
  my ($hash, @a) = @_;
  my $name = shift @a;
  my ($newkeys,$key,$value,$v);

  #-- commands
  my $door     = AttrVal($name, "doorbutton", "door");
  my $doorsubs = "open";
  $doorsubs   .= ",lock"
    if(AttrVal($name, "doorlockcmd",undef));
  $doorsubs   .= ",unlock"
    if(AttrVal($name, "doorunlockcmd",undef));
    
  my $light    = AttrVal($name, "lightbutton", "light");
  my $dashlight    = AttrVal($name, "dashlightbutton", "dashlight");

  #-- for the selector: which values are possible
  if ($a[0] eq "?"){
    $newkeys = join(" ",@{ $hash->{HELPER}->{CMDS} });
    #Log 1,"=====> newkeys before subs $newkeys";
    $newkeys =~ s/$door/$door:$doorsubs/g;               # FHEMWEB sugar
    $newkeys =~ s/$light/$light:on,on-for-timer,off/g;   # FHEMWEB sugar
    $newkeys =~ s/$dashlight/$dashlight:on,off/g;        # FHEMWEB sugar
    $newkeys =~ s/button(\d\d?)/button$1:noArg/g;        # FHEMWEB sugar
    $newkeys =~ s/purge/purge:noArg/g;                   # FHEMWEB sugar
    #Log 1,"=====> newkeys after subs $newkeys ($door,$light)";
    return $newkeys;
  }
  
  $key   = shift @a;
  $value = shift @a; 
  
  return "[DoorPi_Set] With unknown argument $key, choose one of " . join(" ", @{$hash->{HELPER}->{CMDS}})
    if ( !grep( /$key/, @{$hash->{HELPER}->{CMDS}} ) && !($key eq "call") );

  #-- hidden command to be used by DoorPi for adding a new call
  if( $key eq "call" ){
    if( $value eq "start" ){
      readingsSingleUpdate($hash,"call","started",1);
    }elsif( $value eq "end" ){
      readingsSingleUpdate($hash,"call","ended",1);
      DoorPi_GetHistory($hash);
    }elsif( $value eq "rejected" ){
      readingsSingleUpdate($hash,"call","rejected",1);
      DoorPi_GetHistory($hash);
    }elsif( $value eq "dismissed" ){
      readingsSingleUpdate($hash,"call","dismissed",1);
      DoorPi_GetHistory($hash);
    }
  #-- door opening
  }elsif( $key eq "$door" ){
    if( $value eq "open" ){
      $v=DoorPi_Cmd($hash,"door");
      if(AttrVal($name, "dooropencmd",undef)){
        fhem(AttrVal($name, "dooropencmd",undef));
      }
    }
  #-- scene lighting
  }elsif( $key eq "$light" ){
    my $light    = AttrVal($name, "lightbutton", "light");
    if( $value eq "on" ){
      $v=DoorPi_Cmd($hash,"lighton");
      readingsSingleUpdate($hash,$light,"on",1);
    }elsif( $value eq "off" ){
      $v=DoorPi_Cmd($hash,"lightoff");
      readingsSingleUpdate($hash,$light,"off",1);
    }
  #-- dashboard lighting
  }elsif( $key eq "$dashlight" ){
    my $dashlight    = AttrVal($name, "dashlightbutton", "dashlight");
    if( $value eq "on" ){
      $v=DoorPi_Cmd($hash,"dashlighton");
      readingsSingleUpdate($hash,$dashlight,"on",1);
    }elsif( $value eq "off" ){
      $v=DoorPi_Cmd($hash,"dashlightoff");
      readingsSingleUpdate($hash,$dashlight,"off",1);
    }
  }elsif( $key =~ /button(\d\d?)/){
     $v=DoorPi_Cmd($hash,$key);
  }elsif( $key eq "purge"){
     $v=DoorPi_Cmd($hash,"purge");
  }elsif( $key eq "clear"){
     $v=DoorPi_Cmd($hash,"clear");
  }
  
  if(defined($v)) {
     Log GetLogLevel($name,2), "[DoorPi_Set] $key error $v";
     return "$key => Error $v";
  }
  return "$key => ok";
}

#######################################################################################
#
# DoorPi_GetConfig - acts as callable program DoorPi_GetConfig($hash)
#                    and as callback program  DoorPi_GetConfig($hash,$err,$status)
#
# Parameter hash, err, status 
#
#######################################################################################

sub DoorPi_GetConfig () {
  my ($hash,$err,$status) = @_;
  my $name = $hash->{NAME};
  my $url;
  
  #-- get configuration from doorpi
  if ( !$hash ){
    Log 1,"[DoorPi_GetConfig] called without hash";
    return undef;
  }elsif ( $hash && !$err && !$status ){
    $url    = "http://".$hash->{TCPIP}."/status?module=config";
    #Log 1,"[DoorPi_GetConfig] called with only hash => Issue a non-blocking call to $url";  
    HttpUtils_NonblockingGet({
      url      => $url,
      callback=>sub($$$){ DoorPi_GetConfig($hash,$_[1],$_[2]) }
    });
    return undef;
  }elsif ( $hash && $err ){
    Log 1,"[DoorPi_GetConfig] has error $err";
    readingsSingleUpdate($hash,"config",$err,0);
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  #Log 1,"[DoorPi_GetConfig] has obtained data";
 
  #-- crude test if this is valid JSON or some HTML page
  if( substr($status,0,1) eq "<" ){
    Log 1,"[DoorPi_GetConfig] but data is invalid";
    readingsSingleUpdate($hash,"config","invalid data",0);
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  
  my $json  = JSON->new->utf8;
  my $jhash0 = $json->decode( $status );
  
  #-- decode config 
  my $keyboards = $jhash0->{"config"}->{"keyboards"};
  my $fskey;
  my $fscmds;
  foreach my $key (sort(keys $keyboards)) {
    $fskey = $key
      if( $keyboards->{$key} eq "filesystem");
  }
  if($fskey){
    Log 1,"[DoorPi_GetConfig] keyboard \'filesystem\' defined as '$fskey'";
    $hash->{HELPER}->{vkeyboard}=$fskey;
    $fscmds = $jhash0->{"config"}->{$fskey."_InputPins"};
    foreach my $key (sort(keys $fscmds)) {
      push(@{ $hash->{HELPER}->{CMDS}},$key);
    }
  }else{
    Log 1,"[DoorPi_GetConfig] Warning: No keyboard \"filesystem\" defined";
  };
  $hash->{HELPER}->{wwwpath} = $jhash0->{"config"}->{"DoorPiWeb"}->{"www"};
   
  #-- put into READINGS
  readingsSingleUpdate($hash,"state","Initialized",1);
  readingsSingleUpdate($hash,"config","ok",1);
  return undef;
}
 
#######################################################################################
#
# DoorPi_GetHistory - acts as callable program DoorPi_GetHistory($hash)
#                     and as callback program  DoorPi_GetHistory($hash,$err1,$status1)
#                     and as callback program  DoorPi_GetHistory($hash,$err1,$status1,$err2,$status2)
#
# Parameter hash
#
#######################################################################################

sub DoorPi_GetHistory () {
  my ($hash,$err1,$status1,$err2,$status2) = @_;
  my $name = $hash->{NAME};
  my $url;
  
    if( $hash->{READINGS}{state}{VAL} ne "Initialized"){
    Log 1,"[DoorPi_GetHistory] cannot be called, no connection";
    return
  }
  
  #-- obtain call history and snapshot history from doorpi
  if ( !$hash ){
    Log 1,"[DoorPi_GetHistory] called without hash";
    return undef;
  }elsif ( $hash && !$err1 && !$status1 && !$err2 && !$status2 ){
    $url    = "http://".$hash->{TCPIP}."/status?module=history_event";
    #Log 1,"[DoorPi_GetHistory] called with only hash => Issue a non-blocking call to $url";  
    HttpUtils_NonblockingGet({
      url      => $url,
      callback=>sub($$$){ DoorPi_GetHistory($hash,$_[1],$_[2]) }
    });
    return undef;
  }elsif ( $hash && $err1 && !$status1 && !$err2 && !$status2 ){
    Log 1,"[DoorPi_GetHistory] has error $err1";
    readingsSingleUpdate($hash,"history",$err1,0);
    readingsSingleUpdate($hash,"state","Error",1);
    return undef;
  }elsif ( $hash && !$err1 && $status1 && !$err2 && !$status2 ){
    $url    = "http://".$hash->{TCPIP}."/status?module=history_snapshot";
    #Log 1,"[DoorPi_GetHistory] called with hash and data from first call => Issue a non-blocking call to $url";  
    HttpUtils_NonblockingGet({
      url      => $url,
      callback=>sub($$$){ DoorPi_GetHistory($hash,$err1,$status1,$_[1],$_[2]) }
    });
    return undef;
  }elsif ( $hash && !$err1 && $status1 && $err2){
    Log 1,"[DoorPi_GetHistory] has error2 $err2";
    readingsSingleUpdate($hash,"history",$err2,0);
    readingsSingleUpdate($hash,"state","Error",1);
    return undef;
  }
  #Log 1,"[DoorPi_GetHistory] has obtained data in two calls";

  #-- crude test if this is valid JSON or some HTML page
  if( substr($status1,0,1) eq "<" ){
    Log 1,"[DoorPi_GetHistory] but data from first call is invalid";
    readingsSingleUpdate($hash,"history","invalid data 1st call",0);
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  if( substr($status2,0,1) eq "<" ){
    Log 1,"[DoorPi_GetHistory] but data from second call is invalid";
    readingsSingleUpdate($hash,"history","invalid data 2nd call",0);
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  
  my $json  = JSON->new->utf8;
  my $jhash0 = $json->decode( $status1 );
  my $khash0 = $json->decode( $status2 );

  #-- decode call history
  my @history_event    = @{$jhash0->{"history_event"}};
  my @history_snapshot = @{$khash0->{"history_snapshot"}};
  my $call = "";
  
  #-- clear list of calls
  @{$hash->{DATA}} = ();
  
  #-- going backward through the calls 
  my ($callend,$calletime,$calletarget,$callstime,$callstarget,$callsnap,$callrecord,$callstring);
  for (my $i=0; $i<@history_event; $i++) {
     my $event = $history_event[$i];
     
     if( $event->{"event_name"} eq "OnCallStateChange" ){
        my $status1 = $event->{"additional_infos"};
        #-- workaround for bug in DoorPi
        $status1 =~ tr/'/"/;
        my $jhash1 = from_json( $status1 );
        my $call_state = $jhash1->{"call_state"};
        #-- end of call
        if( ($call eq "") && (($call_state == 18) || ($call_state == 13)) ){
          $call        = "active";
          $callrecord  = "";
          $callend     = $jhash1->{"state"};
          $callend =~ s/Call //;
          if( $callend eq "released" ){
             #-- check previous 4 events
             for( my $j=1; $j<5; $j++ ){
               if( $history_event[$i+$j]->{"event_name"} eq "OnCallStateChange"){
                  my $status2 = $history_event[$i+$j]->{"additional_infos"};
                  #-- workaround for bug in DoorPi
                  $status2 =~ tr/'/"/;
                  my $jhash2 = from_json( $status2 );
                  if( $jhash2->{"state"} eq "Busy Here" ){
                     $callend = "busy";
                     last;
                  }elsif( $jhash2->{"state"} eq "Call ended" ){
                     $callend = "ok";
                     last;
                  }
                }
             }
          }elsif( $callend eq "terminated" ){
             if( $history_event[$i-1]->{"event_name"} eq "OnSipPhoneCallTimeoutNoResponse"){
                $callend = "no response";
             }
          }
          $calletime   = $event->{"start_time"};
          $calletarget = $jhash1->{"remote_uri"};
        }elsif( ($call eq "active") && ($call_state == 2) ){
          $call        = "";
          $callstime   = $event->{"start_time"};
          $callstarget = $jhash1->{"remote_uri"};
          #-- 
          if( $calletarget ne $callstarget){
             Log 1,"[DoorPi_GetHistory] Found error in call history of target $calletarget";
          }else{
             #-- Format values
             my $state     = ""; 
             my ($sec, $min, $hour, $day,$month,$year,$wday) = (localtime($callstime))[0,1,2,3,4,5,6]; 
             $year += 1900;
             my $monthn = ("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")[$month];
             $wday  = ("So", "Mo", "Di", "Mi", "Do", "Fr", "Sa")[$wday];
             my $timestamp = sprintf("%s, %2d %s %d %02d:%02d:%02d", $wday,$day,$monthn,$year,$hour, $min, $sec);
             my $number    = $callstarget;
             $number =~ s/sip://;
             $number =~ s/\@.*//;
             my $result    = $callend;
             my $duration  = int(($calletime - $callstime)*10+0.5)/10;
             
             my $record    = $callrecord; 
             $record =~ s/^.*records\///;
             #-- workaround for buggy DoorPi
             $record       = sprintf("%d-%02d-%2d_%02d-%02d-%02d.wav", $year,($month+1),$day,$hour, $min, $sec)
               if( $callend eq "ok");
             
             #-- this is the snapshot file if taken at the same time
             my $snapshot  = sprintf("%d-%02d-%2d_%02d-%02d-%02d.jpg", $year,($month+1),$day,$hour, $min, $sec);
             #-- check if it is present in the list of snapshots
             my $found = 0;
             for( my $i=0; $i<@history_snapshot; $i++){
                if( index($history_snapshot[$i],$snapshot) > -1){
                   $found = 1;
                   last;
                 }
              }
              #-- if not, look for a file made a second later
              if( $found == 0 ){
                 ($sec, $min, $hour, $day,$month,$year,$wday) = (localtime($callstime+1))[0,1,2,3,4,5,6]; 
                 $year += 1900;
                 $monthn = ("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")[$month];
                 $wday  = ("So", "Mo", "Di", "Mi", "Do", "Fr", "Sa")[$wday];
                
                 #-- this is the snapshot file if taken at the same time
                 $snapshot  = sprintf("%d-%02d-%2d_%02d-%02d-%02d.jpg", $year,($month+1),$day,$hour, $min, $sec);
                 #-- check if it is present in the list of snapshots
                 $found = 0;
                 for( my $i=0; $i<@history_snapshot; $i++){
                   if( index($history_snapshot[$i],$snapshot) > -1){
                      $found = 1;
                      last;
                    }
                 }
                 if( $found == 0 ){
                    Log 1,"[DoorPi_GetHistory] No snapshot found with $snapshot";
                 }
             }
            
             #-- store this
             push(@{ $hash->{DATA}}, [$state,$timestamp,$number,$result,$duration,$snapshot,$record] );
          }
        }
     }  
     #-- other events during call active
     if( ($call eq "active") && ($event->{"event_name"} eq "OnRecorderStarted") ){ 
        my $status3 = $event->{"additional_infos"};
        $status3 =~ tr/'/"/;
        my $jhash1 = from_json( $status3 );
        $callrecord = $jhash1->{"last_record_filename"};
      }
  }
  
  #-- going backward through the events to find last action for dashlight and light
  my $dashlightstate = "off";  
  my $dashlight    = AttrVal($name, "dashlightbutton", "dashlight");
  for (my $i=0; $i<@history_event; $i++) {
       if( $history_event[$i]->{"event_name"} =~ /OnKeyPressed_webservice\.dashlight(.*)/ ){
         $dashlightstate=$1;
         last;
       }
  }
  
  my $lightstate = "off";
  my $light    = AttrVal($name, "lightbutton", "light");
  for (my $i=0; $i<@history_event; $i++) {
       if( $history_event[$i]->{"event_name"} =~ /OnKeyPressed_webservice\.light(.*)/ ){
         $lightstate=$1;
         last;
       }
  }
  
  #--put into READINGS
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"number_calls",int(@{ $hash->{DATA}}));
  readingsBulkUpdate($hash,"history","ok");
  readingsBulkUpdate($hash,$dashlight,$dashlightstate);
  readingsBulkUpdate($hash,$light,$lightstate);
  readingsEndUpdate($hash,1); 
  return undef;
}

########################################################################################
#
# DoorPi_Cmd - Write command to DoorPi.
#              acts as callable program DoorPi_Cmd($hash,$cmd)
#                     and as callback program  DoorPi_GetHistory($hash,$cmd,$err,$data)
# 
# Parameter hash, cmd = command 
#
########################################################################################

 sub DoorPi_Cmd () {
  my ($hash, $cmd, $err, $data) = @_;
  my $name = $hash->{NAME};
 
  my $url;
  
  if( $hash->{READINGS}{state}{VAL} ne "Initialized"){
    Log 1,"[DoorPi_Cmd] cannot be called, no connection";
    return
  }
    
  if ( $hash && !$data){
     $url    = "http://".$hash->{TCPIP}."/control/trigger_event?".
               "event_name=OnKeyPressed_".$hash->{HELPER}->{vkeyboard}.".".
               $cmd."&event_source=doorpi.keyboard.from_filesystem";
     #Log 1,"[DoorPi_Cmd] called with only hash => Issue a non-blocking call to $url";  
     HttpUtils_NonblockingGet({
        url      => $url,
        callback=>sub($$$){ DoorPi_Cmd($hash,$cmd,$_[1],$_[2]) }
     });
     return undef;
  }elsif ( $hash && $err ){
    Log 1,"[DoorPi_Cmd] has error $err";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
  #Log 1,"[DoorPi_Cmd] has obtained data";
 
  #-- crude test if this is valid JSON or some HTML page
  if( substr($data,0,1) eq "<" ){
    Log 1,"[DoorPi_Cmd] invalid data";
    readingsSingleUpdate($hash,"state","Error",1);
    return;
  }
    
  my $json = JSON->new->utf8;
  my $jhash = $json->decode( $data );
  my $msg   = $jhash->{'message'};
  my $suc   = $jhash->{'success'};
  if( $suc ){
    return $msg;
  }
  return undef;
}



#######################################################################################
#
# DoorPi_maketable 
#   
# FW_detailFn & FW_summaryFn handler for creating the html output in FHEMWEB
#
#######################################################################################

sub DoorPi_makeTable($$$$){
    my ($FW_wname, $devname, $room, $extPage) = @_;
    my $hash = $defs{$devname};
    return DoorPi_list2html($hash)
}
 
#######################################################################################
#
# DoorPi_list2html creating the call list as html string or json array
#
#######################################################################################

sub DoorPi_list2html($;$){
    my ($hash, $to_json) = @_;
    return undef if( !$hash );
    
    my $name = $hash->{NAME};
    my $wwwpath = $hash->{HELPER}->{wwwpath};
    my $alias = AttrVal($hash->{NAME}, "alias", $hash->{NAME});
    my ($state,$timestamp,$number,$result,$duration,$snapshot,$record,$nrecord);
    
    my $td_style = 'style="padding-left:6px;padding-right:6px;"';
    my @json_output = ();
    my $line;
    
    my $old_locale = setlocale(LC_ALL);
    
    if(AttrVal($name, "language", "en") eq "de"){
        setlocale(LC_ALL, "de_DE.utf8");
    }else{
        setlocale(LC_ALL, "en_US.utf8");
    }
    
    my $ret .= "<table>";
    
    if(AttrVal($name, "no-heading", "0") eq "0" and defined($FW_ME) and defined($FW_subdir))
    {
        $ret .= '<tr><td>';
        $ret .= '<div class="devType"><a href="'.$FW_ME.$FW_subdir.'?detail='.$name.'">'.$alias.'</a>'.(IsDisabled($name) ? ' (disabled)' : '').'</div>' 
          unless($FW_webArgs{"detail"});
        $ret .= '</td></tr>';
    }
    
    $ret .= "<tr><td>";
    #-- div tag to support inform updates
    $ret .= '<div class="fhemWidget" informId="'.$name.'" cmd="" arg="fbcalllist" dev="'.$name.'">';   
    if( exists($hash->{DATA}) && (int(@{$hash->{DATA}}) > 0) ){
       $ret .= '<table class="block fbcalllist">';
    
       if(AttrVal($name, "language", "en") eq "de"){
          $state     = "Wer";
          $timestamp = "Zeitpunkt";
          $number    = "Rufnummer";
          $result    = "Ergebnis";
          $duration  = "Dauer";
          $record    = "Aufzeichnung";
       }else{
          $state     = "Who";
          $timestamp = "Timestamp";
          $number    = "Number";
          $result    = "Result";
          $duration  = "Duration";
          $record    = "Recording";
       }
       $ret .= '<tr align="center" number="$count" class="doorpicalllist odd">';
       $ret .= '<td name="state" class="doorpicalllist" '.$td_style.'>'.$state.'</td>';
       $ret .= '<td name="timestamp" class="doorpicalllist" '.$td_style.'>'.$timestamp.'</td>';
       $ret .= '<td name="number" class="doorpicalllist" '.$td_style.'>'.$number.'</td>';
       $ret .= '<td name="result" class="doorpicalllist" '.$td_style.'>'.$result.'</td>';
       $ret .= '<td name="duration" class="doorpicalllist" '.$td_style.'>'.$duration.'</td>';
       $ret .= '<td name="record" class="doorpicalllist" '.$td_style.'>'.$record.'</td>';
       $ret .= '</tr>';
       
        my @list = @{$hash->{DATA}};
        for(my $index=0; $index<(@list); $index++){
           my @data   = @{$list[$index]};            
           $state     = $data[0];
           $timestamp = $data[1];
           $number    = $data[2];
           $result    = $data[3];
           $duration  = $data[4];
           $snapshot  = $data[5];
           $record    = $data[6];
           
           if(AttrVal($name, "language", "en") eq "de"){
              $result =~ s/busy/besetzt/;
              $result =~ s/no\sresponse/ohne Antw./;
           }
           
           if( $record ne ""){
             my $rs = $record;
             $rs =~ s/.*$wwwpath\///;
             $record = '<a href="http://'.$hash->{TCPIP}.'/'.$record.'">'.$rs.'</a>';
           }
           
           if( $snapshot ne ""){
             $state = '<a href="http://'.$hash->{TCPIP}.'/'.$snapshot.'"><img src="http://'.$hash->{TCPIP}.'/'.$snapshot.'" width="40" height="30"></a>';
           }
           
           $ret .= '<tr align="center" number="$count" class="doorpicalllist '.($index % 2 == 1 ? "odd" : "even").'">';
           $ret .= '<td name="state" class="doorpicalllist" '.$td_style.'>'.$state.'</td>';
           $ret .= '<td name="timestamp" class="doorpicalllist" '.$td_style.'>'.$timestamp.'</td>';
           $ret .= '<td name="number" class="doorpicalllist" '.$td_style.'>'.$number.'</td>';
           $ret .= '<td name="result" class="doorpicalllist" '.$td_style.'>'.$result.'</td>';
           $ret .= '<td name="duration" class="doorpicalllist" '.$td_style.'>'.$duration.'</td>';
           $ret .= '<td name="record" class="doorpicalllist" '.$td_style.'>'.$record.'</td>';
           $ret .= '</tr>';
        }
        $ret .= "</table></div>";
     }else{
        if(AttrVal($name, "language", "en") eq "de"){
            $ret .= "leer";
        }else{
            $ret .= "empty";
        }
    }

    $ret .= "</td></tr></table>";    
    setlocale(LC_ALL, $old_locale);
    
   return ($ret);
}


1;

=pod
=begin html

 <a name="DoorPi"></a>
        <h3>DoorPi</h3>
        <p>FHEM module to communicate with a Raspberry Pi door station running DoorPi<br />
        <br /><h4>Example</h4><br />
        <p>
            <code>define DoorStation DoorPi 192.168.0.51</code>
            <br />
        </p><br />
        <a name="DoorPi_Define"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; DoorPi &lt;IP address&gt;</code> 
            <br /><br /> Define a DoorpiPi instance.<br /><br />
        </p>
        <ul>
          
            <li>
                <code>&lt;IP address&gt;</code>
                <br /> </li>
        </ul>
         <br />
        <a name="DoorPi_Set"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="doorpi_door">
                    <code>set &lt;name&gt; door open[|locked|unlocked] </code></a><br />
                    Activate the door opener in DoorPi, accompanied by an optional FHEM command
                    specified in the <i>dooropencmd</i> attribute.
                    <br><b>If the Attributes doorlockcmd and doorunlockcmd are specified, these commands may be used to lock and unlock the door</b><br>
                    Instead of <i>door</i>, one must use the value of the doorbutton attribute.</li>
            <li><a name="doorpi_dashlight">
                    <code>set &lt;name&gt; dashlight on|off </code></a><br />
                    Set the dashlight (illuminating the door station) on or off.
                    Instead of <i>dashlight</i>, one must use the value of the dashlightbutton attribute</li>
            <li><a name="doorpi_light">
                    <code>set &lt;name&gt; light on|on-for-timer|off </code></a><br />
                    Set the scene light (illuminating the visitor) on, on for a minute or off.
                    Instead of <i>light</i>, one must use the value of the lightbutton attribute</li>
             <li><a name="doorpi_button">
                    <code>set &lt;name&gt; <i>buttonDD</i>  </code></a><br />
                    Activate one of the virtual buttons specified  in DoorPi.
            <li><a name="doorpi_purge">
                    <code>set &lt;name&gt; purge </code></a><br />
                    Clean all recordings and snapshots which are older than the current process </li>
            <li><a name="doorpi_clear">
                    <code>set &lt;name&gt; clear </code></a><br />
                    Clear all recordings and snapshots </li>
        </ul>
        <br />
        <a name="DoorPi_Get"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="doorpi_config">
                    <code>get &lt;name&gt; config</code></a>
                <br /> Returns the current configuration of DoorPi </li>
            <li><a name="doorpi_history">
                    <code>get &lt;name&gt; history</code></a>
                <br /> Returns the current call history of DoorPi </li>
        </ul>
        <h4>Attributes</h4>
        <ul>
            <li><a name="doorpi_doorbutton"><code>attr &lt;name&gt; doorbutton
                        &lt;string&gt;</code></a>
                <br />DoorPi name for door action (default: door)</li>
            <li><a name="doorpi_dooropencmd"><code>attr &lt;name&gt; dooropencmd
                        &lt;string&gt;</code></a>
                <br />FHEM command additionally executed for door opening action (no default)</li>
            <li><a name="doorpi_doorlockcmd"><code>attr &lt;name&gt; doorlockcmd
                        &lt;string&gt;</code></a>
                <br />FHEM command for door locking action (no default)</li>
            <li><a name="doorpi_doorunlockcmd"><code>attr &lt;name&gt; doorunlockcmd
                        &lt;string&gt;</code></a>
                <br />FHEM command for door unlocking action (no default)</li>
            <li><a name="doorpi_lightbutton"><code>attr &lt;name&gt; lightbutton
                        &lt;string&gt;</code></a>
                <br />DoorPi name for light action (default: light)</li>
            <li><a name="doorpi_dashlightbutton"><code>attr &lt;name&gt; dashlightbutton
                        &lt;string&gt;</code></a>
                <br />DoorPi name for dashlight action (default: dashlight)</li>
            <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        </ul>
        
=end html
=cut





