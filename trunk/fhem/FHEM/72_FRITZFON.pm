###############################################################
# $Id: $
#
#  72_FRITZFON.pm
#
#  (c) 2014 Torsten Poitzsch < torsten . poitzsch at gmx . de >
#
#  This module handles the Fritz!Phone MT-F 
#
#  Copyright notice
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
##############################################################################
#
# define <name> FRITZFON
#
##############################################################################

package main;

use strict;
use warnings;
use Blocking;


sub FRITZFON_Log($$$);
sub FRITZFON_Init($);
sub FRITZFON_Ring($$);
sub FRITZFON_Exec($$);
  
sub ##########################################
FRITZFON_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/FRITZFON_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $hash, $loglevel, "FRITZFON $instName: $sub.$xline " . $text;
}

sub ##########################################
FRITZFON_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "FRITZFON_Define";
  $hash->{UndefFn}  = "FRITZFON_Undefine";

  $hash->{SetFn}    = "FRITZFON_Set";
  $hash->{GetFn}    = "FRITZFON_Get";
  $hash->{AttrFn}   = "FRITZFON_Attr";
  $hash->{AttrList} = "disable:0,1 "
                ."ringWithIntern:0,1,2 "
                .$readingFnAttributes;

} # end FRITZFON_Initialize


sub ##########################################
FRITZFON_Define($$)
{
   my ($hash, $def) = @_;
   my @args = split("[ \t][ \t]*", $def);

   return "Usage: define <name> FRITZFON" if(@args <2 || @args >2);  

   my $name = $args[0];

   $hash->{NAME} = $name;

   $hash->{STATE}       = "Initializing";
   $hash->{Message}     = "FHEM";
   $hash->{fhem}{modulVersion} = '$Date: $';

   RemoveInternalTimer($hash);
 # Get first data after 2 seconds
   InternalTimer(gettimeofday() + 2, "FRITZFON_Init", $hash, 0);
 
   return undef;
} #end FRITZFON_Define


sub ##########################################
FRITZFON_Undefine($$)
{
  my ($hash, $args) = @_;

  RemoveInternalTimer($hash);

  return undef;
} # end FRITZFON_Undefine


sub ##########################################
FRITZFON_Attr($@)
{
   my ($cmd,$name,$aName,$aVal) = @_;
      # $cmd can be "del" or "set"
      # $name is device name
      # aName and aVal are Attribute name and value
   my $hash = $defs{$name};

   if ($cmd eq "set")
   {
   }

   return undef;
} # FRITZFON_Attr ende


sub ##########################################
FRITZFON_Set($$@) 
{
   my ($hash, $name, $cmd, @val) = @_;
   my $resultStr = "";
   
   if( lc $cmd eq 'reinit' ) 
   {
      FRITZFON_Init($hash);
      return undef;
   }
   elsif ( lc $cmd eq 'ring')
   {
      if (int @val > 0) 
      {
         FRITZFON_Ring $hash, join("|", @val);
         return undef;
      }
      else
      {
         return "Missing parameters after command 'set $name $cmd'";
      }
   }
   elsif ( lc $cmd eq 'message')
   {
      if (int @val > 0) 
      {
         $hash->{Message} = substr (join(" ", @val),0,30) ;
         return undef;
      }
      else
      {
         return "Missing parameters after command 'set $name $cmd'";
      }
   }
   my $list = "reinit:noArg"
            . " message"
            . " ring";
   return "Unknown argument $cmd, choose one of $list";

} # end FRITZFON_Set


sub ##########################################
FRITZFON_Get($@)
{
  my ($hash, $name, $cmd) = @_;
  my $result;
  my $message;
  
  my $list = "";
  return "Unknown argument $cmd, choose one of $list";

} # end FRITZFON_Get


# Starts the data capturing and sets the new timer
sub ##########################################
FRITZFON_Init($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};
   my $result;
   
   readingsBeginUpdate($hash);

   foreach (1..6)
   {
     # Dect-Telefonname
      FRITZFON_Init_Reading($hash, 
         "dect".$_."_name", 
         "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/Name");
     # Dect-Interne Nummer
      FRITZFON_Init_Reading($hash, 
         "dect".$_."_intern", 
         "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/Intern");
     # Dect-Internal Ring Tone
      FRITZFON_Init_Reading($hash, 
         "dect".$_."_intRingTone", 
         "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/IntRingTone");
     # Dect-Internal Ring Tone
      FRITZFON_Init_Reading($hash, 
         "dect".$_."_imagePath ", 
         "ctlmgr_ctl r telcfg settings/Foncontrol/User".$_."/ImagePath ");
     # Handset manufacturer
      FRITZFON_Init_Reading($hash, 
         "dect".$_."_manufacturer", 
         "ctlmgr_ctl r dect settings/Handset".($_-1)."/Manufacturer");   
   }
   foreach (0..3)
   {
     # Analog-Telefonname
      if (FRITZFON_Init_Reading($hash, 
         "fon".$_."_name", 
         "ctlmgr_ctl r telcfg settings/MSN/Port".$_."/Name"))
      {
         readingsBulkUpdate($hash, "fon".$_."_intern", $_);
      }
   }
   readingsEndUpdate( $hash, 1 );
}

sub ##########################################
FRITZFON_Init_Reading($$$)
{
   my ($hash, $rName, $cmd) = @_;
   my $result = FRITZFON_Exec( $hash, $cmd);
   if ($result) {
      readingsBulkUpdate($hash, $rName, $result);
   } elsif (defined $hash->{READINGS}{$rName} ) {
      delete $hash->{READINGS}{$rName};
   }
   return $result;
}


sub ##########################################
FRITZFON_Ring($$) 
{
   my ($hash, $val) = @_;
   my $name = $hash->{NAME};
   
   my $timeOut = 10;
 
   if ( exists( $hash->{helper}{RUNNING_PID} ) )
   {
      FRITZFON_Log $hash, 5, "Killing existing background process ".$hash->{helper}{RUNNING_PID};
      BlockingKill( $hash->{helper}{RUNNING_PID} ); 
      delete($hash->{helper}{RUNNING_PID});
   }
 
   $hash->{helper}{RUNNING_PID} = BlockingCall("FRITZFON_Ring_Run", $name."|".$val, 
                                       "FRITZFON_Ring_Done", $timeOut,
                                       "FRITZFON_Ring_Aborted", $hash);
} # end FRITZFON_Ring

sub ##########################################
FRITZFON_Ring_Run($$) 
{
   my ($string) = @_;
   my ($name, $intNo, $duration, $ringTone) = split /\|/, $string;
   my $hash = $defs{$name};
   
   my $fonType;
   my $fonTypeNo;
   my $result;
   my $curIntRingTone;
   my $curCallerName;
   
   if (610<=$intNo && $intNo<=615)
   {
      $fonType = "DECT"; $fonTypeNo = $intNo - 609; 
   }
   
   return $name."|0|Error: Internal number '$intNo' not valid" 
      unless defined $fonType;

   $duration = 5 
      unless defined $duration;

   my $msg = $hash->{Message};
   $msg = "FHEM"
      unless defined $msg;
      
   my $ringWithIntern = AttrVal( $name, "ringWithIntern",  0 );
   
   # uses name of virtual port 0 (dial port 1) to show message on ringing phone
   if ($ringWithIntern =~ /^(1|2)$/ )
   {
      $curCallerName = FRITZFON_Exec( $hash, "ctlmgr_ctl r telcfg settings/MSN/Port".($ringWithIntern-1)."/Name");
      FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '$msg'");
   }
   
   if ($fonType eq "DECT" )
   {
      return $name."|0|Error: Internal number ".$intNo." does not exist"
         unless FRITZFON_Exec( $hash, "ctlmgr_ctl r telcfg settings/Foncontrol/User".$fonTypeNo."/Intern");
      if (defined $ringTone)
      {
         $curIntRingTone = FRITZFON_Exec( $hash, "ctlmgr_ctl r telcfg settings/Foncontrol/User".$fonTypeNo."/IntRingTone");
         FRITZFON_Log $hash, 5, "Current internal ring tone of DECT ".$fonTypeNo." is ".$curIntRingTone;
         FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$fonTypeNo."/IntRingTone ".$ringTone);
         FRITZFON_Log $hash, 5, "Set internal ring tone of DECT ".$fonTypeNo." to ".$ringTone;
      }
      sleep 0.5;
      FRITZFON_Log $hash, 5, "Ringing $intNo for $duration seconds";
      FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg settings/DialPort 1");
      FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg command/Dial **".$intNo);
      FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg settings/DialPort 50");
      sleep $duration;
      FRITZFON_Log $hash, 5, "Hangup ".$intNo;
      FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg command/Hangup **".$intNo);
      if (defined $ringTone)
      {
         FRITZFON_Log $hash, 5, "Set internal ring tone of DECT ".$fonTypeNo." back to ".$curIntRingTone;
         FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg settings/Foncontrol/User".$fonTypeNo."/IntRingTone ".$curIntRingTone);
      }
   }

   if ($ringWithIntern =~ /^(1|2)$/ )
   {
      FRITZFON_Exec( $hash, "ctlmgr_ctl w telcfg settings/MSN/Port".($ringWithIntern-1)."/Name '$curCallerName'");
   }

   return $name."|1|";
}

sub ##########################################
FRITZFON_Ring_Done($$) 
{
   my ($string) = @_;
   return unless defined $string;

   my ($name, $success, $result) = split("\\|", $string);
   my $hash = $defs{$name};
   
   delete($hash->{helper}{RUNNING_PID});

   if ($success != 1)
   {
      FRITZFON_Log $hash, 1, $result;
   }
}

sub ##########################################
FRITZFON_Ring_Aborted($$) 
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  FRITZFON_Log $hash, 1, "Timeout when ringing";
}

# Executed the command on the FritzBox Shell
sub ############################################
FRITZFON_Exec($$)
{
	my ($hash, $cmd) = @_;
  return qx($cmd);
}

##################################### 

1;

=pod
=begin html

<a name="FRITZFON"></a>
<h3>FRITZFON</h3>
<div  style="width:800px"> 
<ul>
   The module allows Fritz!Box owners to use a phone as a signaling device. It supports also some special features of the Fritz!Fons, e.g. MT-F.
   <br>
   It has to run in an FHEM process <b>on</b> the box.
   <br>
   <br/><br/>
   <a name="FRITZFONdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; FRITZFON</code>
      <br>
      Example:
      <br>
      <code>define Telefon FRITZFON</code>
      <br/><br/>
   </ul>
  
   <a name="FRITZFONset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; reinit</code>
         <br>
         Reads in some information of the connected phone devices.
      </li><br>
      <li><code>set &lt;name&gt; ring &lt;internalNumber&gt; [duration] [ringTone]</code>
         <br>
         Rings the internal number for duration (seconds) and (if possible) with the given ring tone.
         <br>
      </li><br>
      <li><code>set &lt;name&gt; message &lt;text&gt;</code>
      <br>
      Stores the text to show it later as 'caller' on the ringing phone.
      This is done by changing the name of the calling internal number.
      Maximal 30 characters are allowed.
      </li><br>
   </ul>  

   <a name="FRITZFONget"></a>
   <b>Get</b>
   <ul>
      not implemented yet
   </ul>  
  
   <a name="FRITZFONattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>ringWithIntern &lt;internalNumber&gt;</code>
      <br>
      To show a message during a ring the caller needs to be an internal phone number.
      </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
   <br>

   <a name="FRITZFONreading"></a>
   <b>Readings</b>
   <ul><br>
      <li><b>dect</b><i>1</i><b>_intRingTone</b> - Internal ring tone of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_intern</b> - Internal number of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_manufacturer</b> - Manufacturer of the DECT device <i>1</i></li>
      <li><b>dect</b><i>1</i><b>_name</b> - Internal name of the DECT device <i>1</i></li>
   </ul>
   <br>
</ul>
</div>

=end html

=cut