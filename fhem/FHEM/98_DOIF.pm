#############################################
# $Id$
#
# This file is part of fhem.
#
# Fhem is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
# Fhem is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################


package main;
use strict;
use warnings;
use Color;
use vars qw($FW_CSRF);

sub DOIF_cmd ($$$$);
sub DOIF_Notify ($$);

sub DOIF_delTimer($)
{
  my ($hash) = @_;
  RemoveInternalTimer($hash);
  foreach my $key (keys %{$hash->{triggertime}}) {
    RemoveInternalTimer (\$hash->{triggertime}{$key});
  }
  foreach my $key (keys %{$hash->{ptimer}}) {
    RemoveInternalTimer ($key);
  }
}

sub DOIF_delAll($)
{
  my ($hash) = @_;
  delete ($hash->{helper});
  delete ($hash->{condition});
  delete ($hash->{do});
  delete ($hash->{devices});
  delete ($hash->{time});
  delete ($hash->{timer});
  delete ($hash->{timers});
  delete ($hash->{itimer});
  delete ($hash->{timeCond});
  delete ($hash->{realtime});
  delete ($hash->{localtime});
  delete ($hash->{days});
  delete ($hash->{readings});
  delete ($hash->{internals});
  delete ($hash->{trigger});
  delete ($hash->{triggertime});
  delete ($hash->{ptimer});
  delete ($hash->{interval});
  delete ($hash->{perlblock});
  delete ($hash->{var});

  foreach my $key (keys %{$hash->{Regex}}) {
    delete $hash->{Regex}{$key} if ($key !~ "STATE|DOIF_Readings|uiTable");
  }
  foreach my $key (keys %{$defs{$hash->{NAME}}{READINGS}}) {
    delete $defs{$hash->{NAME}}{READINGS}{$key} if ($key =~ "^(Device|state|error|warning|cmd|e_|timer_|wait_|matched_|last_cmd|mode|block_)");
  }
}

sub DOIF_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "DOIF_Define";
  $hash->{SetFn}   = "DOIF_Set";
  $hash->{GetFn}   = "DOIF_Get";
  $hash->{UndefFn}  = "DOIF_Undef";
  $hash->{AttrFn}   = "DOIF_Attr";
  $hash->{NotifyFn} = "DOIF_Notify";
  $hash->{FW_deviceOverview} = 1;
  $hash->{FW_addDetailToSummary} = 1;
  $hash->{FW_detailFn} = "DOIF_detailFn";
  $hash->{FW_summaryFn}  = "DOIF_summaryFn";
  #$hash->{FW_atPageEnd} = 1;

  $data{FWEXT}{DOIF}{SCRIPT} = "doif.js";

  $hash->{AttrList} = "disable:0,1 loglevel:0,1,2,3,4,5,6 wait do:always,resetwait cmdState startup state initialize repeatsame repeatcmd waitsame waitdel cmdpause timerWithWait:1,0 notexist selftrigger:wait,all timerevent:1,0 checkReadingEvent:1,0 addStateEvent:1,0 checkall:event,timer,all weekdays setList:textField-long readingList DOIF_Readings:textField-long uiTable:textField-long ".$readingFnAttributes;
}

# uiTable
sub DOIF_reloadFW {
  map { FW_directNotify("#FHEMWEB:$_", "location.reload()", "") } devspec2array("TYPE=FHEMWEB");
}

sub DOIF_hsv
{
  my ($cur,$min,$max,$min_s,$max_s,$s,$v)=@_;
  
  my $m=($max_s-$min_s)/($max-$min);
  my $n=$min_s-$min*$m;
  if ($cur>$max) {
   $cur=$max;
  } elsif ($cur<$min) {
    $cur=$min;
  }
    
  my $h=$cur*$m+$n;
  $h /=360;
  $s /=100;
  $v /=100;  
  
  my($r,$g,$b)=Color::hsv2rgb ($h,$s,$v);
  $r *= 255;
  $g *= 255;
  $b *= 255;
  return sprintf("#%02X%02X%02X", $r+0.5, $g+0.5, $b+0.5);
}


sub DOIF_rgb {
  my ($sc,$ec,$pct,$max,$cur) = @_;
  $cur = ($cur =~ /(-?\d+(\.\d+)?)/ ? $1 : 0);
  $pct = ($cur-$pct)/($max-$pct) if (@_ == 5);
  my $prefix = "";
  $prefix = "#" if ("$sc $ec"=~"#");
  $sc =~ s/^#//;
  $ec =~ s/^#//;
  $pct = $pct > 1 ? 1 : $pct;
  $pct = $pct < 0 ? 0 : $pct;
  $sc =~/([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})/;
  my @sc = (hex($1),hex($2),hex($3));
  $ec =~/([0-9A-F]{2})([0-9A-F]{2})([0-9A-F]{2})/;
  my @ec = (hex($1),hex($2),hex($3));
  my @rgb;
  for (0..2) {
    $rgb[$_] = sprintf("%02X", int(($ec[$_] - $sc[$_])*$pct + $sc[$_] + .5));
  }
  return $prefix.join("",@rgb);
} 

#sub DOIF_Icon {
#  my ($dev, $reading, $icon, $cmd, $type) = @_;
#  my $val = ReadingsVal($dev,$reading,"???");
#  $type= $reading eq 'state' ? 'set' : 'setreading' if (!defined $type);
#  my $ret = FW_makeImage($icon,$cmd,"icon");
#  $ret = FW_pH "cmd.$dev=$type $dev $reading $cmd", $ret, 0, "webCmd", 1;
#  return "$ret";
#}

sub DOIF_UpdateCell
{
  my ($hash,$doifId,$dev,$reading) =@_;
  my $pn = $hash->{NAME};
  my $retVal="";
  my $retStyle="";
  my $reg="";
  my $VALUE="";
  if ($doifId =~ /.*_(.*)_c_(.*)_(.*)_(.*)_(.*)$/) {
    eval ($hash->{$1}{table}{$2}{$3}{$4}{$5});
    if ($@) {
        my $err="$pn: eval: $hash->{$1}{table}{$2}{$3}{$4}{$5} error: $@" ;
        Log3 $pn,3,$err; 
    }
  }
}

sub DOIF_Widget
{
  my ($hash,$reg,$doifId,$value,$style,$widget,$dev,$reading,$command)=@_;
  if ($reg) {
    return DOIF_Widget_Register($doifId,$value,$style,$widget,$dev,$reading,$command);
  } else {
    DOIF_Widget_Update($hash->{NAME},$doifId,$value,$style,$widget,$dev,$reading,$command);
  }
}

sub DOIF_Widget_Update
{
  my ($pn,$doifId,$value,$style,$widget,$dev,$reading,$command)=@_;
  if (defined $widget) {
    if (1) {
      map { 
         FW_directNotify("#FHEMWEB:$_", "doifUpdateCell('$pn','informid','$dev-$reading','$value')","")
      } devspec2array("TYPE=FHEMWEB");
    }
  } else {
      map { 
         FW_directNotify("#FHEMWEB:$_", "doifUpdateCell('$pn','doifId','$doifId','$value','display:inline;$style')","")
      } devspec2array("TYPE=FHEMWEB") if ($value ne "");
  }
}

sub DOIF_Widget_Register
{
  my ($doifId,$value,$style,$widget,$dev,$reading,$command)=@_;
  my $type;
  my $cmd='';
  if (defined $widget) {
    if (defined $command) {
      if ($command =~ /^([^ ]*) *(.*)/) {
        $type = !defined $1 ? '': $1;
        $cmd = !defined $2 ? '': $2;
      } else {
        $type=$command;
      } 
    } else {
      $type= $reading eq 'state' ? 'set' : 'setreading';
    }
    $cmd = $cmd eq '' ? $reading : $cmd;
    return "<div class='fhemWidget' cmd='$cmd' reading='$reading' dev='$dev' arg='$widget' current='$value' type='$type'></div>";
  } else {
    return "<div class='dval' doifId='$doifId' style='display:inline;$style'>$value</div>";
  }
}
 
sub DOIF_RegisterCell
{
  my ($hash,$table,$func,$r,$c,$cc,$cr) =@_;
  my $event;
  my $err;
  my $dev="";
  my $reading="";
  my $value="";
  my $expr;
  my $style;
  my $widget;
  my $command;
  my $cell;
  my $widsty=0;
  my $trigger=0;
  
  if ($func=~ /^\s*(STY[ \t]*\(|WID[ \t]*\()/) {
    my ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($func,'[\(\)]');
      if ($err) {
        return $err;
      } elsif ($currentBlock ne "") {
      $cell=$currentBlock;
    } 
  } else {
    $cell=$func;
  }
  
  my $doifId="$hash->{NAME}_".$table."_c_".$r."_".$c."_".$cc."_".$cr;
  if ($func=~ /^\s*STY[ \t]*\(/) {
    $widsty=1;
    ($expr,$style) = SplitDoIf(',',$cell);
  } elsif ($func=~ /^\s*WID[ \t]*\(/) {
    $widsty=2;
    ($expr,$widget,$command) = SplitDoIf(',',$cell);
  } else {
    $expr=$cell;
  }
  ($expr,$err,$event)=ReplaceAllReadingsDoIf($hash,$expr,($table eq "uiTable" ? -5:-6),0,$doifId);
  if ($err) {
    $err="'error $err: in expression: $expr'";
    return $err;
  } else {
    eval $expr;
    if ($@) {
      return "'error $@ in expression: $expr'";
    }
  }
  $trigger=$event; 
  if (defined($widget)) {
    if ($event) {
      $dev=$hash->{$table}{dev} if (defined $hash->{$table}{dev});
      $reading=$hash->{$table}{reading} if (defined $hash->{$table}{reading});
    } else {
      return "'no trigger reading in widget: $expr'";
    }
    ($widget,$err,$event)=ReplaceAllReadingsDoIf($hash,$widget,($table eq "uiTable" ? -5:-6),0,$doifId);
    $trigger=$event if ($event);
    if ($err) {
      $err="'error $err: in widget: $widget'";
      return $err;
    } else {
      eval $widget;
      if ($@) {
        return "'error $@ in widget: $widget'";
      }
    }
  } else {
    $widget="";
  }
  if (defined $style) {
    ($style,$err,$event)=ReplaceAllReadingsDoIf($hash,$style,($table eq "uiTable" ? -5:-6),0,$doifId);
    $trigger=$event if ($event);
    if ($err) {
      $err="'error $err: in style: $style'";
      return $err;
    } else {
      eval $style;
      if ($@) {
        return "'error $@ in style: $style'";
      }
    }
  } else {
    $style='""';
  }
  
  if ($widsty==2) {
      $reading="state" if ($reading eq '&STATE');
      return "DOIF_Widget(".'$hash,$reg,'."'$doifId',$expr,$style,$widget,'$dev','$reading'".(defined $command ? ",$command)":")");
  } elsif (($widsty==1) or $trigger) {
      return "DOIF_Widget(".'$hash,$reg,'."'$doifId',$expr,$style)";
  } else {
      return $expr;
  }
  return ""
}

sub parse_tpl
{
  my ($hash,$wcmd,$table) = @_;
  my $d=$hash->{NAME};
  my $err="";
  while ($wcmd =~ /(?:^|\n)\s*IMPORT\s*(.*)(\n|$)/g) {
    $err=import_tpl($hash,$1,$table);
    return ($err,"") if ($err);
  }
  
  #$wcmd =~ s/(^|\n)\s*\#.*(\n|$)/\n/g;
  #$wcmd =~ s/(#.*\n)|(#.*$)|\n/ /g;
  $wcmd =~ s/(##.*\n)|(##.*$)/\n/g;
  $wcmd =~ s/(^|\n)\s*IMPORT.*(\n|$)//g;
  $wcmd =~ s/\$TPL\{/\$hash->\{$table\}\{template\}\{/g;
  #$wcmd =~ s/\$TD{/\$hash->{$table}{td}{/g;
  #$wcmd =~ s/\$TC{/\$hash->{$table}{tc}{/g;
  $wcmd =~ s/\$ATTRIBUTESFIRST/\$hash->{$table}{attributesfirst}/;
  
  $wcmd =~ s/\$TC\{/\$hash->{$table}{tc}\{/g;
  $wcmd =~ s/\$hash->\{$table\}\{tc\}\{([\d,.]*)?\}.*(\".*\")/for my \$i ($1) \{\$hash->\{$table\}\{tc\}\{\$i\} = $2\}/g;
  
  $wcmd =~ s/\$TR\{/\$hash->{$table}{tr}\{/g;
  $wcmd =~ s/\$hash->\{$table\}\{tr\}\{([\d,.]*)?\}.*(\".*\")/for my \$i ($1) \{\$hash->\{$table\}\{tr\}\{\$i\} = $2\}/g;
  
  $wcmd =~ s/\$TD\{(.*)?\}\{(.*)?\}.*(\".*\")/for my \$rowi ($1) \{for my \$coli ($2) \{\$hash->\{$table\}\{td\}\{\$rowi\}\{\$coli\} = $3\}\}/g;
  $wcmd =~ s/\$TABLE/\$hash->{$table}{tablestyle}/;

  $wcmd =~ s/\$VAR/\$hash->{var}/g;
  $wcmd =~ s/\$SELF/$d/g;
  $wcmd =~ s/FUNC_/DOIF_FUNC_$d\_/g;
  $wcmd =~ s/PUP[ \t]*\(/DOIF_tablePopUp(\"$d\",/g;
  $wcmd =~ s/\$SHOWNOSTATE/\$hash->{$table}{shownostate}/;
  $wcmd =~ s/\$SHOWNODEVICELINK/\$hash->{$table}{shownodevicelink}/;
  $wcmd =~ s/\$SHOWNODEVICELINE/\$hash->{$table}{shownodeviceline}/;
  
  if ($wcmd=~ /^\s*\{/) { # perl block
    my ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($wcmd,'[\{\}]');
    if ($err) {
        return ("error in $table: $err","");
    } elsif ($currentBlock ne "") {
      $currentBlock ="no warnings 'redefine';".$currentBlock;
      eval ($currentBlock);
      if ($@) {
        $err="$d: error: $@ in $table: $currentBlock";
        return ($err,"");
      }
      $wcmd=$tailBlock;
    }
  }
  
  $wcmd =~ s/^\s*//;
  $wcmd =~ s/[ \t]*\n/\n/g;
  $wcmd =~ s/,[ \t]*[\n]+/,/g;
  $wcmd =~ s/\.[ \t]*[\n]+/\./g;
  $wcmd =~ s/\|[ \t]*[\n]+/\|/g;
  $wcmd =~ s/>[ \t]*[\n]+/>/g;
  
  my $tail=$wcmd;
  my $beginning;
  my $currentBlock;
  
  while($tail =~ /(?:^|\n)\s*DEF\s*(TPL_[^ ^\t^\(]*)[^\(]*\(/g) {
    ($beginning,$currentBlock,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
    if ($err) {
        return ("error in $table: $err","");
    } elsif ($currentBlock ne "") {
      $hash->{$table}{tpl}{$1}=$currentBlock;
    }
  }
  return ("",$tail);
}

sub import_tpl
{
  my ($hash,$file,$table) = @_;
  my $fh;
  my $err;
  if(!open($fh, $file)) {
    return "Can't open $file: $!";
  }
  my @tpl=<$fh>;
  close $fh;
  my $wcmd=join("",@tpl);
  ($err,$wcmd)=parse_tpl($hash,$wcmd,$table);
  return $err if ($err);
  return "";
}

sub DOIF_uiTable_def 
{
  my ($hash,$wcmd,$table) = @_;
  return undef if (!$wcmd); 
  my $err="";
  delete ($hash->{Regex}{$table});
  delete ($hash->{$table});
  ($err,$wcmd)=parse_tpl($hash,$wcmd,$table);
  return $err if ($err);
  
  my @rcmd = split(/\n/,$wcmd);
  my $ii=0;
  for (my $i=0; $i<@rcmd; $i++) {
    next if ($rcmd[$i] =~ /^\s*$/);
    my @ccmd = SplitDoIf('|',$rcmd[$i]);
    for (my $k=0;$k<@ccmd;$k++) {
      if ($ccmd[$k] =~ /^\s*(TPL_[^ ^\t^\(]*)[^\(]*\(/g) {
        my $template=$1;
        if (defined $hash->{$table}{tpl}{$template}) {
          my $templ=$hash->{$table}{tpl}{$template};
          my ($beginning,$currentBlock,$err,$tail)=GetBlockDoIf($ccmd[$k],'[\(\)]');
          if ($err) {
            return "error in $table: $err";
          } elsif ($currentBlock ne "") {
            my @param = SplitDoIf(',',$currentBlock);
            for (my $j=0;$j<@param;$j++) {
              my $p=$j+1;
              $templ =~ s/\$$p/$param[$j]/g;
            }
            $ccmd[$k]=$templ;
          }
        } else {
          return ("no Template $template defined");
        }
      }
      my @cccmd = SplitDoIf(',',$ccmd[$k]);
      for (my $l=0;$l<@cccmd;$l++) {
        my @crcmd = SplitDoIf('.',$cccmd[$l]);
        for (my $m=0;$m<@crcmd;$m++) {
          $hash->{$table}{table}{$ii}{$k}{$l}{$m}= DOIF_RegisterCell($hash,$table,$crcmd[$m],$ii,$k,$l,$m);
          
        }
      }
    }
    $ii++;
  }
  return undef;
  ##$hash->{$table}{tabledef}=DOIF_RegisterEvalAll($hash);
}

sub DOIF_RegisterEvalAll
{
  my ($hash,$d,$table) = @_;
  my $ret = "";
  my $reg=1;
  return undef if (!defined $hash->{$table}{table});
  #$ret =~ s/class\=\'block\'/$hash->{$table}{table}/ if($hash->{$table}{table});
  if ($table eq "uiTable") {
    $ret .= "\n<table uitabid='DOIF-$d' class=' block wide ".$table."doif doif-$d ' style='".($hash->{$table}{tablestyle} ? $hash->{$table}{tablestyle} : "")."'".
      " doifnostate='".($hash->{$table}{shownostate} ? $hash->{$table}{shownostate} : "")."'".
      " doifnodevline='".($hash->{$table}{shownodeviceline} ? $hash->{$table}{shownodeviceline} : "")."'".
      " doifattrfirst='".($hash->{$table}{attributesfirst} ? $hash->{$table}{attributesfirst} : "")."'".
      ">"; 
    #$ret .= "\n<table uitabid='DOIF-$d' class=' ".$table."doif doif-$d ' style='".($hash->{$table}{tablestyle} ? $hash->{$table}{tablestyle} : "")."'>"; 
  } else {
   $ret .= "\n<table uitabid='DOIF-$d' class=' ".$table."doif doif-$d ' style='".($hash->{$table}{tablestyle} ? $hash->{$table}{tablestyle} : "")."'". 
      " doifattrfirst='".($hash->{$table}{attributesfirst} ? $hash->{$table}{attributesfirst} : "")."'".
      ">"; 
  }
  my $lasttr =scalar keys %{$hash->{$table}{table}};
  for (my $i=0;$i < $lasttr;$i++){
    my $class = ($i&1)?"class='odd'":"class='even'";
    $ret .="<tr ";
    $ret .=((defined $hash->{$table}{tr}{$i}) ? $hash->{$table}{tr}{$i}:"");
    $ret .=" ".(($i&1) ? $hash->{$table}{tr}{odd}:"") if (defined $hash->{$table}{tr}{odd});
    $ret .=" ".((!($i&1)) ? $hash->{$table}{tr}{even}:"") if (defined $hash->{$table}{tr}{even});
    $ret .=" ".(($i==$lasttr-1) ? $hash->{$table}{tr}{last}:"") if (defined $hash->{$table}{tr}{last});
    $ret .=" $class >";
    my $lastc =scalar keys %{$hash->{$table}{table}{$i}};
    for (my $k=0;$k < $lastc;$k++){
      $ret .="<td ";
      $ret .=((defined $hash->{$table}{td}{$i}{$k}) ? $hash->{$table}{td}{$i}{$k}:"");
      $ret .=" ".((defined $hash->{$table}{tc}{$k} )? $hash->{$table}{tc}{$k}:"");
      $ret .=" ".(($k&1)?$hash->{$table}{tc}{odd}:"") if (defined $hash->{$table}{tc}{odd});
      $ret .=" ".((!($k&1))?$hash->{$table}{tc}{even}:"") if (defined $hash->{$table}{tc}{even});
      $ret .=" ".(($k==$lastc-1)?$hash->{$table}{tc}{last}:"") if (defined $hash->{$table}{tc}{last});
      $ret .=">";
      my $lastcc =scalar keys %{$hash->{$table}{table}{$i}{$k}};
      for (my $l=0;$l < $lastcc;$l++){
      for (my $m=0;$m < scalar keys %{$hash->{$table}{table}{$i}{$k}{$l}};$m++) {
          if (defined $hash->{$table}{table}{$i}{$k}{$l}{$m}){
            my $value= eval ($hash->{$table}{table}{$i}{$k}{$l}{$m});
            if (defined ($value)) {
              if (defined $defs{$value} and (!defined $hash->{$table}{shownodevicelink} or !$hash->{$table}{shownodevicelink})) {
                $ret.="<a href='$FW_ME?detail=$value$FW_CSRF'>$value</a>";
              } else {
                $ret.=$value;
              }
            }
          }
        }
        $ret.="<br>" if ($l+1 != $lastcc);
      }
      $ret.="</td>";
    }
    $ret .= "</tr>";
  }
  $ret .= "</table>\n"; # if ($table eq "uiTable");
  
  #$hash->{$table}{deftable}=$ret;
  return $ret;
}

sub DOIF_tablePopUp {
  my ($pn,$d,$icon,$table) = @_;
  $table = $table ? $table : "uiTable";
  if ($defs{$d} && AttrVal($d,$table,"")) {
    my $ret = "<a href=\"#\" onclick=\"doifTablePopUp('$defs{$d}','$d','$pn','$table')\">".FW_makeImage($icon)."</a>";
  } else {
    return "no device $d or attribut $table";
  }
}

sub DOIF_summaryFn ($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};
  my $ret = "";
  # if ($hash->{uiTable}{shownostate}) {
   # return "";
  # }
  #Log3 $d,1,"vor DOIF_RegisterEvalAll uiState d: $d";
  $ret=DOIF_RegisterEvalAll($hash,$d,"uiState");
  #Log3 $d,1,"nach DOIF_RegisterEvalAll";
  return $ret;
}

sub DOIF_detailFn ($$$$) {
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};
  my $ret = "";
  #Log3 $d,1,"vor DOIF_RegisterEvalAll uiTable";
  $ret=DOIF_RegisterEvalAll($hash,$d,"uiTable");
  #Log3 $d,1,"nach DOIF_RegisterEvalAll";
  return $ret;
}

sub GetBlockDoIf ($$)
{
  my ($cmd,$match) = @_;
  my $count=0;
  my $first_pos=0;
  my $last_pos=0;
  my $err="";
  while($cmd =~ /$match/g) {
    if (substr($cmd,pos($cmd)-1,1) eq substr($match,2,1)) {
      $count++;
      $first_pos=pos($cmd) if ($count == 1);
    } elsif (substr($cmd,pos($cmd)-1,1) eq substr($match,4,1)) {
      $count--;
    }
    if ($count < 0)
    {
      $err="right bracket without left bracket";
      return ("",substr($cmd,pos($cmd)-1),$err,"");
    }

    if ($count == 0) {
      $last_pos=pos($cmd);
      last;
    }
  }
  if ($count > 0) {
    $err="no right bracket";
    return ("",substr($cmd,$first_pos-1),$err);
  }
  if ($first_pos) {
    return (substr($cmd,0,$first_pos-1),substr($cmd,$first_pos,$last_pos-$first_pos-1),"",substr($cmd,$last_pos));
  } else {
    return ($cmd,"","","");
  }
}

sub GetCommandDoIf ($$)
{
  my ($separator,$tailBlock) = @_;
  my $char;
  my $beginning;
  my $currentBlock;
  my $err;
  my $cmd="";
  while ($tailBlock=~ /^([^$separator^"^\[^\{^\(]*)/g) {
       $char=substr($tailBlock,pos($tailBlock),1);
       if ($char eq $separator) {
         $cmd=$cmd.substr($tailBlock,0,pos($tailBlock));
         $tailBlock=substr($tailBlock,pos($tailBlock)+1);
         return($cmd,$tailBlock,"");
       } elsif ($char eq '{') {
         ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\{\}]');
         return ($currentBlock,$tailBlock,$err) if ($err);
         $cmd=$cmd.$beginning."{$currentBlock}";
       } elsif ($char eq '(') {
         ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\(\)]');
         return ($currentBlock,$tailBlock,$err) if ($err);
         $cmd=$cmd.$beginning."($currentBlock)";
       } elsif ($char eq '[') {
         ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\[\]]');
         return ($currentBlock,$tailBlock,$err) if ($err);
         $cmd=$cmd.$beginning."[$currentBlock]";
       } elsif ($char eq '"') {
         if ($tailBlock =~ /(^[^"]*"[^"]*")(.*)/) {
           $cmd=$cmd.$1;
           $tailBlock=$2;
         }
       }
  }
  if ($cmd eq "") {
    $cmd=$tailBlock;
  } else {
    $cmd=$cmd.$tailBlock
  }
  return ($cmd,"","");
}

sub EvalValueDoIf($$$)
{
  my ($hash,$attr,$value)=@_;
  return "" if (!defined($value) or $value eq "");
  my $err="";
  my $pn=$hash->{NAME};
   $value =~ s/\$SELF/$pn/g;
  ($value,$err)=ReplaceAllReadingsDoIf($hash,$value,-1,1);
  if ($err) {
    my $error="$pn: error in $attr: $err";
    Log3 $pn,4 , $error;
    readingsSingleUpdate ($hash, "error", $error,0);
    $value=0;
  } else {
     my $ret = eval $value;
     if ($@) {
       my $error="$pn: error in $attr: $value";
       Log3 $pn,4 , $error;
       readingsSingleUpdate ($hash, "error", $error,0);
       $value=0;
     } else {
       $value=$ret;
     }
  }
  return ($value);
}

sub EvalCmdStateDoIf($$)
{
  my ($hash,$state)=@_;
  my $err;
  my $pn=$hash->{NAME};
  ($state,$err)=ReplaceAllReadingsDoIf($hash,$state,-1,1);
  if ($err) {
    Log3 $pn,4 , "$pn: error in state: $err" if ($err);
    $state=$err;
  } else {
    ($state,$err)=EvalAllDoIf($hash, $state);
    if ($err) {
      Log3 $pn,4 , "$pn: error in state: $err" if ($err);
      $state=$err;
    }
  }
  return($state)
}

sub SplitDoIf($$)
{
  my ($separator,$tailBlock)=@_;
  my @commands;
  my $cmd;
  my $err;
  if (defined $tailBlock) {
    while ($tailBlock ne "") {
      ($cmd,$tailBlock,$err)=GetCommandDoIf($separator,$tailBlock);
      push(@commands,$cmd) if (defined $cmd);
    }
  }
  return(@commands);
}

sub EventCheckDoif($$$$)
{
  my ($n,$dev,$eventa,$NotifyExp)=@_;
  my $found=0;
  my $s;
  return 0 if ($dev ne $n);
  return 0 if(!$eventa);
  my $max = int(@{$eventa});
  my $ret = 0;
  if ($NotifyExp eq "") {
    return 1 ;
  }
  for (my $i = 0; $i < $max; $i++) {
    $s = $eventa->[$i];
    $s = "" if(!defined($s));
    $found = ($s =~ m/$NotifyExp/);
    if ($found) {
      return 1;
    }
  }
  return 0;
}

sub AggrIntDoIf
{
  my ($hash,$modeType,$device,$reading,$cond,$default)=@_;
  my $num=0;
  my $value="";
  my $sum=0;
  my $average;
  my $extrem;
  my $name;
  my $devname;
  my $err;
  my $ret;
  my $result;
  my @devices;
  my $group;
  my $room;
  my $STATE;
  my $TYPE;
  my $warning=0;
  my $mode=substr($modeType,0,1);
  my $type;
  my $format;
  my $place;
  my $number;
  my $readingRegex;
  
  if ($modeType =~ /.(sum|average|max|min)?[:]?(?:(a|d)?(\d)?)?/) {
    $type = (defined $1)? $1 : "";
    $format= (defined $2)? $2 : "";
    $place= $3;
  }
  
  if (defined $default) {
    if ($default =~ /^"(.*)"$/) {
      $default = $1;
    } else {
      $default=EvalValueDoIf($hash,"default",$default);
    }
  }
  
  if (defined $reading) {
    if ($reading =~ /^"(.*)"$/) {
      $readingRegex = $1;
    }
  }

  foreach my $name (($device eq "") ? keys %defs:grep {/$device/} keys %defs) {
    next if($attr{$name} && $attr{$name}{ignore});
    foreach my $reading ((defined $readingRegex) ? grep {/$readingRegex/} keys %{$defs{$name}{READINGS}} : $reading) {
      $value="";
      $number="";
      if ($reading) {
        if (defined $defs{$name}{READINGS}{$reading}) {
          $value=$defs{$name}{READINGS}{$reading}{VAL};
          $number = ($value =~ /(-?\d+(\.\d+)?)/ ? $1 : 0);
        } else {
          next;
        }
      }
      if ($cond) {
        if ($cond =~ /^"(.*)"$/) {
           if (defined $defs{$name}{READINGS}{$reading}) {
             $ret=($value =~ /$1/); 
           }
        } else {
          $_=$value;
          $STATE=Value($name);
          $TYPE=$defs{$name}{TYPE};
          $group=AttrVal($name,"group","");
          $room=AttrVal($name,"room","");
          $lastWarningMsg="";
          $ret = eval $cond;
          if ($@) {
            $@ =~ s/^(.*) at \(eval.*\)(.*)$/$1,$2/;
            if (defined $hash) {
               Log3 ($hash->{NAME},3 , "$hash->{NAME}: aggregate function: error in condition: $cond, $@");
            }
            return("error in aggregate function: ".$@);
          }
          if ($lastWarningMsg) {
            $warning=1;
            $lastWarningMsg =~ s/^(.*) at \(eval.*$/$1/;
            Log3 ($hash->{NAME},3 , "$hash->{NAME}: aggregate function: warning in condition: $cond, Device: $name");
            readingsSingleUpdate ($hash, "warning_aggr", "condition: $cond , device: $name, $lastWarningMsg",0);
          } 
          $lastWarningMsg="";
        }
      } else {
        $ret=1;
      }
      if ($format eq "a") {
        $devname=AttrVal($name,"alias",$name);
      } else {
        $devname=$name;
      }
      if ($ret) {
        if ($type eq ""){
          $num++;
          push (@devices,$devname);
        } elsif (defined $value) {
          if ($type eq "sum" or $type eq "average") {
            $num++;
            push (@devices,$devname);
            $sum+=$number;
          } elsif ($type eq "max") {
              if (!defined $extrem or $number>$extrem) {
                $extrem=$number;
                @devices=($devname);
              }  
          } elsif ($type eq "min") {
              if (!defined $extrem or $number<$extrem) {
                $extrem=$number;
                @devices=($devname);
              }
          }
        }
      }
    }
  }
  
  delete ($defs{$hash->{NAME}}{READINGS}{warning_aggr}) if (defined $hash and $warning==0);
  
  if ($type eq "max" or $type eq "min") {
    $extrem=0 if (!defined $extrem);  
    $result=$extrem;
  } elsif ($type eq "sum") {
    $result= $sum;
  } elsif ($type eq "average") {
    if ($num>0) {
      $result=($sum/$num)
    }
  } else {
    $result=$num;
  }
  if ($mode eq "#") {
    if ($format eq "d") {
      $result = ($result =~ /(-?\d+(\.\d+)?)/ ? $1 : 0);
      $result = round ($result,$place) if (defined $place);
    } 
    if ($num==0 and defined $default) {
      return ($default);
    } else {    
      return ($result);
    }
  } elsif ($mode eq "@") {
    if ($num==0 and defined $default) {
      @devices =($default);
    }
    return (sort @devices);
  }
  return 0;
}

sub AggrDoIf
{
  my ($modeType,$device,$reading,$cond,$default)=@_;
  return (AggrIntDoIf(undef,$modeType,$device,$reading,$cond,$default));
}

sub AggregateDoIf
{
  my ($hash,$modeType,$device,$reading,$cond,$default)=@_;
  my $mode=substr($modeType,0,1);
  my $type=substr($modeType,1);
  my $splittoken=",";
  if ($modeType =~ /.(?:sum|average|max|min)?[:]?[^s]*(?:s\((.*)\))?/) {
    $splittoken=$1 if (defined $1);
  } 
  if ($mode eq "#") {
    return (AggrIntDoIf($hash,$modeType,$device,$reading,$cond,$default));
  } elsif ($mode eq "@") {
    return (join ($splittoken,AggrIntDoIf($hash,$modeType,$device,$reading,$cond,$default)));
  }
  return ("");
}

sub EventDoIf
{
  my ($n,$hash,$NotifyExp,$check,$filter,$output,$default)=@_;

  my $dev=$hash->{helper}{triggerDev};
  my $eventa=$hash->{helper}{triggerEvents};
  if ($check) {
    if ($dev eq "" or $dev ne $n) {
      if (defined $filter) {
        return ($default)
      } else {
        return 0;
      }
    }
  } else {
    if ($dev eq "" or $n and $dev !~ /$n/) {
      if (defined $filter) {
        return ($default)
      } else {
        return 0;
      }
    }
  }
  return 0 if(!$eventa);
  my $max = int(@{$eventa});
  my $ret = 0;
  if ($NotifyExp eq "") {
    return 1 if (!defined $filter);
  }
  my $s;
  my $found;
  my $element;
  for (my $i = 0; $i < $max; $i++) {
    $s = $eventa->[$i];
    $s = "" if(!defined($s));
    $found = ($s =~ m/$NotifyExp/);
    if ($found or $NotifyExp eq "") {
      $hash->{helper}{event}=$s;
      if (defined $filter) {
        $element = ($s =~  /$filter/) ? $1 : "";
        if ($element) {
          if ($output ne "") {
            $element= eval $output;
            if ($@) {
              Log3 ($hash->{NAME},4 , "$hash->{NAME}: $@");
              readingsSingleUpdate ($hash, "error", $@,0);
              return(undef);
            }
          }
          return ($element);
        }
      } else {
        return 1;
      }
    }
    #if(!$found && AttrVal($n, "eventMap", undef)) {
    #  my @res = ReplaceEventMap($n, [$n,$s], 0);
    #  shift @res;
    #  $s = join(" ", @res);
    #  $found = ("$n:$s" =~ m/^$re$/);
  }
  if (defined $filter) {
    return ($default);
  } else {
    return 0;
  }
}

sub InternalDoIf
{
  my ($hash,$name,$internal,$default,$regExp,$output)=@_;

  $default=AttrVal($hash->{NAME},'notexist','') if (!defined $default);
  $regExp='' if (!defined $regExp);
  $output='' if (!defined $output);
  if ($default =~ /^"(.*)"$/) {
    $default = $1;
  } else {
    $default=EvalValueDoIf($hash,"default",$default);
  }
  my $r="";
  my $element;
  return ($default) if (!defined $defs{$name});
  return ($default) if (!defined $defs{$name}{$internal});
  $r=$defs{$name}{$internal};
  if ($regExp) {
    $element = ($r =~  /$regExp/) ? $1 : "";
    if ($output) {
      $element= eval $output;
      if ($@) {
        Log3 ($hash->{NAME},4 , "$hash->{NAME}: $@");
        readingsSingleUpdate ($hash, "error", $@,0);
        return(undef);
      }
    }
  } else {
    $element=$r;
  }
  return($element);
}

sub ReadingSecDoIf($$)
{
  my ($name,$reading)=@_;
  my ($seconds, $microseconds) = gettimeofday();
  return ($seconds - time_str2num(ReadingsTimestamp($name, $reading, "1970-01-01 01:00:00")));
}

sub ReadingValDoIf
{
  my ($hash,$name,$reading,$default,$regExp,$output)=@_;

  $default=AttrVal($hash->{NAME},'notexist','') if (!defined $default);
  $output='' if (!defined $output);
  $regExp='' if (!defined $regExp);
  if ($default =~ /^"(.*)"$/) {
    $default = $1;
  } else {
    $default=EvalValueDoIf($hash,"default",$default);
  }
  my $r;
  my $element;
    return ($default) if (!defined $defs{$name});
    return ($default) if (!defined $defs{$name}{READINGS});
    return ($default) if (!defined $defs{$name}{READINGS}{$reading});
    $r=$defs{$name}{READINGS}{$reading}{VAL};
    $r="" if (!defined($r));
    if ($regExp) {
      if ($regExp =~ /^d(\d)?/) {
        my $round=$1;
        $r = ($r =~ /(-?\d+(\.\d+)?)/ ? $1 : 0);
        $r = round ($r,$round) if (defined $round); 
        $regExp="(.*)";
      }
      "" =~ /()()()()()()()()()/; #reset $1, $2...
      $element = ($r =~  /$regExp/) ? $1 : "";
      if ($output) {
        $element= eval $output;
        if ($@) {
          Log3 ($hash->{NAME},4 , "$hash->{NAME}: $@");
          readingsSingleUpdate ($hash, "error", $@,0);
          return(undef);
        }
      }
    } else {
      $element=$r;
    }
    return($element);
}

sub EvalAllDoIf($$)
{
  my ($hash,$tailBlock)= @_;
  my $eval="";
  my $beginning;
  my $err;
  my $cmd="";
  my $ret="";
  my $eventa=$hash->{helper}{triggerEvents};
  my $device=$hash->{helper}{triggerDev};
  my $event=$hash->{helper}{event};
  my $events="";
  if ($eventa) {
    $events=join(",",@{$eventa});
  }
  while ($tailBlock ne "") {
    ($beginning,$eval,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\{\}]');
    return ($eval,$err) if ($err);
    if ($eval) {
      if (substr($eval,0,1) eq "(") {
	    $eval=$1 if ($eval =~/^\((.*)\)$/);
        my $ret = eval $eval;
        return($eval." ",$@) if ($@);
        $eval=$ret;
      } else {
        $eval="{".$eval."}";
      }
    }
    $cmd.=$beginning.$eval;
  }
  return ($cmd,"");
}

sub ReplaceAggregateDoIf($$$)
{
  my ($hash,$block,$eval) = @_;
  my $exp;
  my $nameExp;
  my $notifyExp;
  my $match;
  my $reading;
  my $aggrType;
  my $default;
  
  ($block,$default)=SplitDoIf(",",$block);
  
  if ($block =~ /^([^"]*)(.*)/) {
    $aggrType=$1;
    $block=$2;
  }
  
  ($exp,$reading,$match)=SplitDoIf(":",$block);
  if ($exp =~ /^"(.*)"/){
    $exp=$1;
    if ($exp =~ /([^\:]*):(.*)/) {
      $nameExp=$1;
      $notifyExp=$2;
    } else {
      $nameExp=$exp;
    }
  }
  $nameExp="" if (!defined $nameExp);
  $notifyExp="" if (!defined $notifyExp);
  
  if (defined $default) {
    $match="" if (!defined $match);
    $block="AggregateDoIf(".'$hash'.",'$aggrType','$nameExp','$reading','$match','$default')";
  } elsif (defined $match) {
    $block="AggregateDoIf(".'$hash'.",'$aggrType','$nameExp','$reading','$match')";
  } elsif (defined $reading) {
    $block="AggregateDoIf(".'$hash'.",'$aggrType','$nameExp','$reading')";
  } else {
     $block="AggregateDoIf(".'$hash'.",'$aggrType','$nameExp')";
  }
  
  if ($eval) {
    my $ret = eval $block;
    return($block." ",$@) if ($@);
    $block=$ret;
  }
  return ($block,undef);
}

sub ReplaceEventDoIf($)
{
  my ($block) = @_;
  my $exp;
  my $exp2;
  my $nameExp;
  my $notifyExp;
  my $default;
  my $filter;
  my $output;

  ($exp,$default)=SplitDoIf(",",$block);
  ($exp2,$filter,$output)=SplitDoIf(":",$exp);
  if ($exp2 =~ /^"(.*)"/){
    $exp2=$1;
    if ($exp2 =~ /([^\:]*):(.*)/) {
      $nameExp=$1;
      $notifyExp=$2;
    } else {
      $nameExp=$exp2;
    }
  }
  $nameExp="" if (!defined $nameExp);
  $notifyExp="" if (!defined $notifyExp);
  $output="" if (!defined $output);
  if (defined $default) {
    if ($default =~ /"(.*)"/) {
      $default = $1;
    }
    if (defined $filter) {
      if ($filter =~ /"(.*)"/) {
        $filter=$1;
      } else {
        return ($filter,"wrong filter Regex")
      }
    } else {
       $filter='[^\:]*: (.*)';
    }
  } else {
    if (defined $filter) {
      return ($block,"default value must be defined")
    } else {
      $block="EventDoIf('$nameExp',".'$hash,'."'$notifyExp',0)";
      return ($block,undef);
    }
  }
  $block="EventDoIf('$nameExp',".'$hash,'."'$notifyExp',0,'$filter','$output','$default')";
  return ($block,undef);
}

sub ReplaceReadingDoIf($)
{
  my ($element) = @_;
  my $beginning;
  my $tailBlock;
  my $err;
  my $regExp="";
  my $name;
  my $reading;
  my $format;
  my $output="";
  my $exp;
  my $default;
  my $param="";


  ($exp,$default)=SplitDoIf(",",$element);
  $default="" if (!defined($default));

  my $internal="";
  my $notifyExp="";
  if ($exp =~ /^([^:]*):(".*")/) {
    $name=$1;
    $reading=$2;
  } elsif ($exp =~ /^([^:]*)(?::([^:]*)(?::(.*))?)?/) {
    $name=$1;
    $reading=$2;
    $format=$3;
  }
  if ($name) {
    if ($reading) {
      if (substr($reading,0,1) eq "\?") {
        $notifyExp=substr($reading,1);
        return("EventDoIf('$name',".'$hash,'."'$notifyExp',1)","",$name,undef,undef);
      } elsif ($reading =~ /^"(.*)"$/g)  {
        $notifyExp=$1;
        return("EventDoIf('$name',".'$hash,'."'$notifyExp',1)","",$name,undef,undef);
      }
      $internal = substr($reading,1) if (substr($reading,0,1) eq "\&");
      if ($format) {
        if ($format eq "sec") {
          return("ReadingSecDoIf('$name','$reading')","",$name,$reading,undef);
        } elsif (substr($format,0,1) eq '[') { #old Syntax
          ($beginning,$regExp,$err,$tailBlock)=GetBlockDoIf($format,'[\[\]]');
          return ($regExp,$err) if ($err);
          return ($regExp,"no round brackets in regular expression") if ($regExp !~ /.*\(.*\)/);
        } elsif ($format =~ /^"([^"]*)"(?::(.*))?/){
          $regExp=$1;
          $output=$2;
          return ($regExp,"no round brackets in regular expression") if ($regExp !~ /.*\(.*\)/);
        } elsif ($format =~ /^(d[^:]*)(?::(.*))?/) {
          $regExp =$1;
          $output=$2;
        }
          else {
          return($format,"unknown expression format");
        }
      }
      $output="" if (!defined($output));

      if ($output) {
        $param=",'$default','$regExp','$output'";
      } elsif ($regExp) {
        $param=",'$default','$regExp'";
      } elsif ($default) {
        $param=",'$default'";
      }
      if ($internal) {
        return("InternalDoIf(".'$hash'.",'$name','$internal'".$param.")","",$name,undef,$internal);
      } else {
        return("ReadingValDoIf(".'$hash'.",'$name','$reading'".$param.")","",$name,$reading,undef);
      }
    } else {
      if ($default) {
        $param=",'$default'";
      }
      return("InternalDoIf(".'$hash'.",'$name','STATE'".$param.")","",$name,undef,'STATE');
    }
  }
}

sub ReplaceReadingEvalDoIf($$$)
{
  my ($hash,$element,$eval) = @_;
  my ($block,$err,$device,$reading,$internal)=ReplaceReadingDoIf($element);
  return ($block,$err) if ($err);
  if ($eval) {
   #   return ("[".$element."]","") if(!$defs{$device});
   #   return ("[".$element."]","") if (defined ($reading) and !defined($defs{$device}{READINGS}{$reading}));
   #   return ("[".$element."]","") if (defined ($internal) and !defined($defs{$device}{$internal}));
    my $ret = eval $block;
    return($block." ",$@) if ($@);
    $block=$ret;
  }
  return ($block,"",$device,$reading,$internal);
}

sub AddItemDoIf($$)
{
  my ($items,$item)=@_;
  if (!$items) {
    $items=" $item ";
  } elsif ($items !~ / $item /) {
    $items.="$item ";
  }
  return $items;
}

sub AddRegexpTriggerDoIf
{
  my ($hash,$type,$regexp,$element,$dev,$reading)= @_;
  
  $dev="" if (!defined($dev));
  $reading="" if (!defined($reading));
  my $regexpid='"'.$regexp.'"';

  if ($dev) {
    if ($reading){
      $hash->{Regex}{$type}{$dev}{$element}{$reading}=(($reading =~ "^\&") ? "\^$dev\$":"\^$dev\$:\^$reading: ");
    } elsif ($regexp) {
      $hash->{Regex}{$type}{$dev}{$element}{$regexpid}="\^$dev\$:$regexp";
    }
    return;
  }
  $hash->{Regex}{$type}{$dev}{$element}{$regexpid}=$regexp;
}

sub addDOIF_Readings($$)
{
  my ($hash,$DOIF_Readings) = @_;
  delete $hash->{DOIF_Readings};
  delete $hash->{Regex}{DOIF_Readings};
  my @list=SplitDoIf(',',$DOIF_Readings);
  my $reading;
  my $readingdef;
  
  for (my $i=0;$i<@list;$i++)
  {
    ($reading,$readingdef)=SplitDoIf(":",$list[$i]);
    if (!$readingdef) {
      return ($DOIF_Readings,"no reading definiton: $list[$i]");
    }
    if ($reading =~ /^\s*([a-z0-9._-]*[a-z._-]+[a-z0-9._-]*)\s*$/i) {
      my ($def,$err)=ReplaceAllReadingsDoIf($hash,$readingdef,-4,0,$1);
      return ($def,$err) if ($err);
      $hash->{DOIF_Readings}{$1}=$def;
    } else {
      return ($list [$i],"wrong reading specification for: $reading");
    }
  }
  return ("","");
}

sub setDOIF_Reading
{
  my ($hash,$DOIF_Reading,$reading) = @_;
  $lastWarningMsg="";
  my $ret = eval $hash->{DOIF_Readings}{$DOIF_Reading};
  if ($@) {
    $@ =~ s/^(.*) at \(eval.*\)(.*)$/$1,$2/;
    $ret="error in DOIF_Readings: ".$@;
  }
  if ($lastWarningMsg) {
    $lastWarningMsg =~ s/^(.*) at \(eval.*$/$1/;
    Log3 ($hash->{NAME},3 , "$hash->{NAME}: warning in DOIF_Readings: $DOIF_Reading");
  } 
  $lastWarningMsg="";
  if ($ret ne ReadingsVal($hash->{NAME},$DOIF_Reading,"")){
    push (@{$hash->{helper}{DOIF_Readings_events}},"$DOIF_Reading: $ret");
    readingsSingleUpdate ($hash,$DOIF_Reading,$ret,0);
  }
}

sub ReplaceAllReadingsDoIf
{
  my ($hash,$tailBlock,$condition,$eval,$id)= @_;
  my $block="";
  my $beginning;
  my $err;
  my $cmd="";
  my $ret="";
  my $device="";
  my $nr;
  my $timer="";
  my $event=0;
  my $definition=$tailBlock;
  my $reading;
  my $internal;
  my $trigger=1;
  if (!defined $tailBlock) {
    return ("","");
  }
  $tailBlock =~ s/\$SELF/$hash->{NAME}/g;
  while ($tailBlock ne "") {
    ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\[\]]');
    return ($block,$err) if ($err);
    if ($block ne "") {
      if (substr($block,0,1) eq "?") {
            $block=substr($block,1);
            $trigger=0;
      } else {
        $trigger=1;
      }
      if ($block =~ /^(?:(?:#|@)[^"]*)"([^"]*)"/) {
        ($block,$err)=ReplaceAggregateDoIf($hash,$block,$eval);
        return ($block,$err) if ($err);
        if ($trigger) {
          $event=1;
          if ($condition >= 0) {
            AddRegexpTriggerDoIf($hash,"cond",$1,$condition);
          } elsif ($condition == -2) {
            AddRegexpTriggerDoIf($hash,"STATE",$1,"STATE");
          } elsif ($condition == -4) {
            AddRegexpTriggerDoIf($hash,"DOIF_Readings",$1,$id);
          } elsif ($condition == -5) {
            AddRegexpTriggerDoIf($hash,"uiTable",$1,$id);
          }  elsif ($condition == -6) {
            AddRegexpTriggerDoIf($hash,"uiState",$1,$id);
          } 
        }
      } elsif ($block =~ /^"([^"]*)"/) {
        ($block,$err)=ReplaceEventDoIf($block);
        return ($block,$err) if ($err);
        if ($trigger) {
          if ($condition>=0) {
            AddRegexpTriggerDoIf($hash,"cond",$1,$condition);
            $event=1;
          } elsif ($condition == -4) {
            AddRegexpTriggerDoIf($hash,"DOIF_Readings",$1,$id);
          } else {
            $block="[".$block."]";
          }
        } else {
          $block="[".$block."]";
        }
      } else {
        $trigger=0 if (substr($block,0,1) eq "\$");
        if ($block =~ /^\$?[a-z0-9._]*[a-z._]+[a-z0-9._]*($|:.+$|,.+$)/i) {
          ($block,$err,$device,$reading,$internal)=ReplaceReadingEvalDoIf($hash,$block,$eval);
          return ($block,$err) if ($err);
          if ($condition >= 0) {
            if ($trigger) {
              $hash->{devices}{$condition} = AddItemDoIf($hash->{devices}{$condition},$device);
              $hash->{devices}{all} = AddItemDoIf($hash->{devices}{all},$device);
              $event=1;
            }
            $hash->{readings}{$condition} = AddItemDoIf($hash->{readings}{$condition},"$device:$reading") if (defined ($reading) and $trigger);
            $hash->{internals}{$condition} = AddItemDoIf($hash->{internals}{$condition},"$device:$internal") if (defined ($internal));
            $hash->{readings}{all} = AddItemDoIf($hash->{readings}{all},"$device:$reading") if (defined ($reading) and $trigger);
            $hash->{internals}{all} = AddItemDoIf($hash->{internals}{all},"$device:$internal") if (defined ($internal));
            $hash->{trigger}{all} = AddItemDoIf($hash->{trigger}{all},"$device") if (!defined ($internal) and !defined($reading));

          } elsif ($condition == -2) {
            if ($trigger) {
              AddRegexpTriggerDoIf($hash,"STATE","","STATE",$device,((defined $reading) ? $reading : "&STATE"));
              $event=1;
            }
          } elsif ($condition == -3) {
              $hash->{itimer}{all} = AddItemDoIf($hash->{itimer}{all},$device);
          } elsif ($condition == -4) {
            if ($trigger) {
              AddRegexpTriggerDoIf($hash,"DOIF_Readings","",$id,$device,((defined $reading) ? $reading :"&STATE"));
              $event=1;
            }
          } elsif ($condition == -5) {
            if ($trigger) {
              AddRegexpTriggerDoIf($hash,"uiTable","",$id,$device,((defined $reading) ? $reading : "&STATE"));
              $hash->{uiTable}{dev}=$device;
              $hash->{uiTable}{reading}=((defined $reading) ? $reading : "&STATE");
              $event=1;
            }
          } elsif ($condition == -6) {
            if ($trigger) {
              AddRegexpTriggerDoIf($hash,"uiState","",$id,$device,((defined $reading) ? $reading : "&STATE"));
              $hash->{uiState}{dev}=$device;
              $hash->{uiState}{reading}=((defined $reading) ? $reading : "&STATE");
              $event=1;
            }
          }
        } elsif ($condition >= 0) {
          ($timer,$err)=DOIF_CheckTimers($hash,$block,$condition,$trigger);
          return($timer,$err) if ($err);
          if ($timer) {
            $block=$timer;
            $event=1 if ($trigger);
          }
        } else {
          $block="[".$block."]";
        }
      }
    }
    $cmd.=$beginning.$block;
  }
  #return ($definition,"no trigger in condition") if ($condition >=0 and $event == 0);
  return ($cmd,"",$event);
}

sub
ParseCommandsDoIf($$$)
{
  my($hash,$tailBlock,$eval) = @_;
  my $pn=$hash->{NAME};
  my $currentBlock="";
  my $beginning="";
  my $err="";
  my $pos=0;
  my $last_error="";
  my $ifcmd;
  my $ret;
  my $eventa=$hash->{helper}{triggerEvents};
  my $device=$hash->{helper}{triggerDev};
  my $event=$hash->{helper}{event};
  my $events="";
  if ($eventa) {
    $events=join(",",@{$eventa});
  }
  while ($tailBlock ne "") {
    if ($tailBlock=~ /^\s*\{/) { # perl block
      ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\{\}]');
      return ($currentBlock,$err) if ($err);
      if ($currentBlock ne "") {
         ($currentBlock,$err)=ReplaceAllReadingsDoIf($hash,$currentBlock,-1,$eval);
         return ($currentBlock,$err) if ($err);
         if ($eval) {
           ($currentBlock,$err)=EvalAllDoIf($hash,$currentBlock);
           return ($currentBlock,$err) if ($err);
         }
      }
      $currentBlock="{".$currentBlock."}";
    } elsif ($tailBlock =~ /^\s*IF/) {
      my $ifcmd="";
      ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\(\)]'); #condition
      return ($currentBlock,$err) if ($err);
      $ifcmd.=$beginning."(".$currentBlock.")";
      ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\(\)]'); #if case
      return ($currentBlock,$err) if ($err);
      $ifcmd.=$beginning."(".$currentBlock.")";
      if ($tailBlock =~ /^\s*ELSE/) {
        ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\(\)]'); #else case
        return ($currentBlock,$err) if ($err);
      $ifcmd.=$beginning."(".$currentBlock.")";
      }
      $currentBlock=$ifcmd;
    } else {
      if ($tailBlock =~ /^\s*\(/) { # remove bracket
          ($beginning,$currentBlock,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\(\)]');
          return ($currentBlock,$err) if ($err);
          #$tailBlock=substr($tailBlock,pos($tailBlock)) if ($tailBlock =~ /^\s*,/g);
      } else {
        ($currentBlock,$tailBlock)=GetCommandDoIf(',',$tailBlock);
      }
      if ($currentBlock ne "") {
       ($currentBlock,$err)=ReplaceAllReadingsDoIf($hash,$currentBlock,-1,$eval);
       return ($currentBlock,$err) if ($err);
       if ($eval) {
         ($currentBlock,$err)=EvalAllDoIf($hash, $currentBlock);
         return ($currentBlock,$err) if ($err);
       }
      }
    }
    if ($eval) {
	   if ($currentBlock =~ /^{.*}$/) {
	     $ret = AnalyzePerlCommand(undef,$currentBlock);
	   } else {
         $ret = AnalyzeCommandChain(undef,$currentBlock);
       }
	   if ($ret) {
         Log3 $pn,2 , "$pn: $currentBlock: $ret";
         $last_error.="$currentBlock: $ret ";
       }
    }
    $tailBlock=substr($tailBlock,pos($tailBlock)) if ($tailBlock =~ /^\s*,/g);
  }
  return("",$last_error);
}

sub DOIF_weekdays($$)
{
  my ($hash,$weekdays)=@_;
  my @days=SplitDoIf(',',AttrVal($hash->{NAME},"weekdays","So,Mo,Di,Mi,Do,Fr,Sa,WE,AT"));
  for (my $i=0;$i<@days;$i++)
  {
    $weekdays =~ s/$days[$i]/$i/;
  }
  return($weekdays);
}


sub
DOIF_CheckTimers($$$$)
{
  my $i=0;
  my @nrs;
  my @times;
  my $nr=0;
  my $days="";
  my $err;
  my $beginning;
  my $pos;
  my $time;
  my $block;
  my $result;
  my ($hash,$timer,$condition,$trigger)=@_;
  $timer =~ s/\s//g;
  while ($timer ne "") {
     if ($timer=~ /^\+\(/) {
      ($beginning,$time,$err,$timer)=GetBlockDoIf($timer,'[\(\)]');
      return ($time,$err) if ($err);
      $time="+(".$time.")";
      ($result,$err)=ReplaceAllReadingsDoIf($hash,$time,-3,0);
      return ($time,$err) if ($err);
    } elsif ($timer=~ /^\(/) {
      ($beginning,$time,$err,$timer)=GetBlockDoIf($timer,'[\(\)]');
      return ($time,$err) if ($err);
      $time="(".$time.")";
      ($result,$err)=ReplaceAllReadingsDoIf($hash,$time,-3,0);
      return ($time,$err) if ($err);
    } elsif ($timer=~ /^\{/) {
      ($beginning,$time,$err,$timer)=GetBlockDoIf($timer,'[\{\}]');
      return ($time,$err) if ($err);
      $time="{".$time."}";
    } elsif ($timer=~ m/^\+\[([0-9]+)\]:([0-5][0-9])/g) {
      $pos=pos($timer);
      $time=substr($timer,0,$pos);
      $timer=substr($timer,$pos);
    } elsif ($timer=~ /^\+\[/) {
      ($beginning,$time,$err,$timer)=GetBlockDoIf($timer,'[\[\]]');
      return ($time,$err) if ($err);
      $time="+[".$time."]";
      ($result,$err)=ReplaceAllReadingsDoIf($hash,$time,-3,0);
      return ($time,$err) if ($err);
    } elsif ($timer=~ /^\[/) {
      ($beginning,$time,$err,$timer)=GetBlockDoIf($timer,'[\[\]]');
      return ($time,$err) if ($err);
      $time="[".$time."]";
      ($result,$err)=ReplaceAllReadingsDoIf($hash,$time,-3,0);
      return ($time,$err) if ($err);
    } elsif ($timer =~ /-/g) {
      $pos=pos($timer)-1;
      $time=substr($timer,0,$pos);
      $timer=substr($timer,$pos);
    } else {
      ($time,$days)=split(/\|/,$timer);
      $timer="";
    }
    $times[$i]=$time;
    $nrs[$i++]=$hash->{helper}{last_timer}++;
    if ($timer) {
      if ($timer =~ /\-/g) {
        $timer=substr($timer,pos($timer));
      } elsif ($timer =~ /\|/g) {
        $days=substr($timer,pos($timer));
        $timer="";
      } else {
        return ($timer,"wrong time format");
      }
    }
  }
  $days = "" if (!defined ($days));
  for (my $j=0; $j<$i;$j++) {
    $nr=$nrs[$j];
    $time=$times[$j];
    $time .=":00" if ($time =~ m/^[0-9][0-9]:[0-5][0-9]$/);
    $hash->{timer}{$nr}=0;
    $hash->{time}{$nr}=$time;
    $hash->{timeCond}{$nr}=$condition;
    $hash->{days}{$nr}=$days if ($days ne "");
    if ($init_done) {
      DOIF_SetTimer($hash,"DOIF_TimerTrigger",$nr);
      #$err=(DOIF_SetTimer($hash,"DOIF_TimerTrigger",$nr));
      #return($hash->{time}{$nr},$err) if ($err);
    }
    $hash->{timers}{$condition}.=" $nr " if ($trigger);
  }
  if ($i == 2) {
    if ($days eq "") {
      $block='DOIF_time($hash,'.$nrs[0].','.$nrs[1].',$wday,$hms)';
    } else {
      $block='DOIF_time($hash,'.$nrs[0].','.$nrs[1].',$wday,$hms,"'.$days.'")';
    }
    $hash->{interval}{$nrs[0]}=-1;
    $hash->{interval}{$nrs[1]}=$nrs[0];
  } else {
    if ($days eq "") {
      $block='DOIF_time_once($hash,'.$nrs[0].',$wday)';
    } else {
      $block='DOIF_time_once($hash,'.$nrs[0].',$wday,"'.$days.'")';
    }
  }
  return ($block,"");
}

sub
DOIF_time
{
  my $ret=0;
  my ($hash,$b,$e,$wday,$hms,$days)=@_;
  $days="" if (!defined ($days));
  return 0 if (!defined $hash->{realtime}{$b});
  return 0 if (!defined $hash->{realtime}{$e});
  my $begin=$hash->{realtime}{$b};
  my $end=$hash->{realtime}{$e};
  my $err;
  return 0 if ($begin eq $end);
  ($days,$err)=ReplaceAllReadingsDoIf($hash,$days,-1,1);
  if ($err) {
    my $errmsg="error in days: $err";
    Log3 ($hash->{NAME},4 , "$hash->{NAME}: $errmsg");
    readingsSingleUpdate ($hash, "error", $errmsg,0);
    return 0;
  }
  $days=DOIF_weekdays($hash,$days);
  my $we=DOIF_we($wday);
  if ($end gt $begin) {
    if ($hms ge $begin and $hms lt $end) {
      $ret=1;
    }
  } else {
    if ($hms ge $begin) {
      $ret=1;
    } elsif ($hms lt $end) {
      $wday=6 if ($wday-- == 0);
      $we=DOIF_we($wday);
      $ret=1;
    }
  }
  if ($ret == 1) {
    return 1 if ($days eq "" or $days =~ /$wday/ or ($days =~ /7/ and $we) or ($days =~ /8/ and !$we));
  }
  return 0;
}

sub
DOIF_time_once
{
  my ($hash,$nr,$wday,$days)=@_;
  $days="" if (!defined ($days));
  my $flag=$hash->{timer}{$nr};
  my $err;
  ($days,$err)=ReplaceAllReadingsDoIf($hash,$days,-1,1);
  if ($err) {
    my $errmsg="error in days: $err";
    Log3 ($hash->{NAME},4 , "$hash->{NAME}: $errmsg");
    readingsSingleUpdate ($hash, "error", $errmsg,0);
    return 0;
  }
  $days=DOIF_weekdays($hash,$days);
  my $we=DOIF_we($wday);
  if ($flag) {
    return 1 if ($days eq "" or $days =~ /$wday/ or ($days =~ /7/ and $we) or ($days =~ /8/ and !$we));
  }
  return 0;
}

############################
sub
DOIF_SetState($$$$$)
{
  my ($hash,$nr,$subnr,$event,$last_error)=@_;
  my $pn=$hash->{NAME};
  my $cmdNr="";
  my $cmd="";
  my $err="";
  my $attr=AttrVal($hash->{NAME},"cmdState","");
  my $state=AttrVal($hash->{NAME},"state","");
  $state =~ s/\$SELF/$pn/g;
  my @cmdState=SplitDoIf('|',$attr);
  $nr=ReadingsVal($pn,"cmd_nr",0)-1 if (!$event);
  if ($nr!=-1) {
    $cmdNr=$nr+1;
    my @cmdSubState=SplitDoIf(',',$cmdState[$nr]);
    if (defined $cmdSubState[$subnr]) {
      $cmd=EvalCmdStateDoIf($hash,$cmdSubState[$subnr]);
    } else {
      if (defined $hash->{do}{$nr}{$subnr+1}) {
        $cmd="cmd_".$cmdNr."_".($subnr+1);
      } else {
        if (defined ($cmdState[$nr]) and defined $cmdSubState[$subnr]) {
          $cmd=EvalCmdStateDoIf($hash,$cmdState[$nr]);
        } else {
          $cmd="cmd_$cmdNr";
        }
      }
    }
  }
  if ($cmd =~ /^"(.*)"$/) {
    $cmd=$1;
  }
  readingsBeginUpdate($hash);
  if ($event) {
    push (@{$hash->{helper}{DOIF_eventas}},"cmd_nr: $cmdNr");
    readingsBulkUpdate($hash,"cmd_nr",$cmdNr);
    if (defined $hash->{do}{$nr}{1}) {
      readingsBulkUpdate($hash,"cmd_seqnr",$subnr+1);
      push (@{$hash->{helper}{DOIF_eventas}},("cmd_seqnr: ".($subnr+1)));
      readingsBulkUpdate($hash,"cmd",$cmdNr.".".($subnr+1));
    } else {
      delete ($defs{$hash->{NAME}}{READINGS}{cmd_seqnr});
      push (@{$hash->{helper}{DOIF_eventas}},"cmd: $cmdNr");
      readingsBulkUpdate($hash,"cmd",$cmdNr);
    }
    push (@{$hash->{helper}{DOIF_eventas}},"cmd_event: $event");
    readingsBulkUpdate($hash,"cmd_event",$event);
    if ($last_error) {
      push (@{$hash->{helper}{DOIF_eventas}},"error: $last_error");
      readingsBulkUpdate($hash,"error",$last_error);
    } else {
      delete ($defs{$hash->{NAME}}{READINGS}{error});
    }
  }

 # if ($state and !defined $hash->{do}{$nr}{$subnr+1}) {
 if ($state) {
    my $stateblock='\['.$pn.'\]';
    $state =~ s/$stateblock/$cmd/g;
    $state=EvalCmdStateDoIf($hash,$state);
  } else {
    $state=$cmd;
  }
  push (@{$hash->{helper}{DOIF_eventas}},"state: $state");
  readingsBulkUpdate($hash, "state", $state); 
  if (defined $hash->{uiState}{table}) {
    readingsEndUpdate ($hash, 0);
  } else {
    readingsEndUpdate ($hash, 1);
  }
}

sub
DOIF_we($) {
  my ($wday)=@_;
  my $we = (($wday==0 || $wday==6) ? 1 : 0);
  if(!$we) {
    my $h2we = $attr{global}{holiday2we};
    if($h2we && Value($h2we)) {
      my ($a, $b) = ReplaceEventMap($h2we, [$h2we, Value($h2we)], 0);
      $we = 1 if($b ne "none");
    }
  }
  return $we;
}

sub
DOIF_CheckCond($$)
{
  my ($hash,$condition) = @_;
  my $err="";
  my ($seconds, $microseconds) = gettimeofday();
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime($seconds);
  $month++;
  $year+=1900;
  my $week=strftime ('%W', localtime($seconds));
  my $hms = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
  my $hm = sprintf("%02d:%02d", $hour, $min);
  my $ymd = sprintf("%02d-%02d-%02d", $year, $month,$mday);
  my $md = sprintf("%02d-%02d",$month,$mday);
  my $dev;
  my $reading;
  my $internal;
  my $we=DOIF_we($wday);
  my $eventa=$hash->{helper}{triggerEvents};
  my $device=$hash->{helper}{triggerDev};
  my $event=$hash->{helper}{event};
  my $events="";
  my $cmd=ReadingsVal($hash->{NAME},"cmd",0);
  if ($eventa) {
    $events=join(",",@{$eventa});
  }
  if (defined ($hash->{readings}{$condition})) {
    foreach my $devReading (split(/ /,$hash->{readings}{$condition})) {
      $devReading=~ s/\$DEVICE/$hash->{helper}{triggerDev}/g if ($devReading);
      #if (!AttrVal($hash->{NAME},'notexist',undef)) {
      #  ($dev,$reading)=(split(":",$devReading));
      #  return (-1,"device does not exist: [$dev:$reading]") if ($devReading and !defined ($defs{$dev}));
      #  return (-1,"reading does not exist: [$dev:$reading]") if ($devReading and !defined($defs{$dev}{READINGS}{$reading}{VAL}));
      #}
    }
  }
  if (defined ($hash->{internals}{$condition})) {
    foreach my $devInternal (split(/ /,$hash->{internals}{$condition})) {
      $devInternal=~ s/\$DEVICE/$hash->{helper}{triggerDev}/g if ($devInternal);
      #if (!AttrVal($hash->{NAME},'notexist',undef)) {
      #  ($dev,$internal)=(split(":",$devInternal));
      #  return (-1,"device does not exist: [$dev:$internal]") if ($devInternal and !defined ($defs{$dev}));
      #  return (-1,"internal does not exist: [$dev:$internal]") if ($devInternal and !defined($defs{$dev}{$internal}));
      #}
    }
  }
  my $command=$hash->{condition}{$condition};
  if ($command) {
    my $eventa=$hash->{helper}{triggerEvents};
    my $events="";
    if ($eventa) {
       $events=join(",",@{$eventa});
    }
    $command =~ s/\$DEVICE/$hash->{helper}{triggerDev}/g;
    $command =~ s/\$EVENTS/$events/g;
    $command =~ s/\$EVENT/$hash->{helper}{event}/g;
    #my $idx = 0;
    #my $evt;
    #foreach my $part (split(" ", $hash->{helper}{event})) {
    #   $evt='\$EVTPART'.$idx;
    #   $command =~ s/$evt/$part/g;
    #   $idx++;
    #}
  }
  $cmdFromAnalyze="$hash->{NAME}: ".sprintf("warning in condition c%02d",($condition+1));
  $lastWarningMsg="";
  my $ret = eval $command;
  if($@){
    $@ =~ s/^(.*) at \(eval.*\)(.*)$/$1,$2/;
    $err = sprintf("condition c%02d",($condition+1)).": $@";
    $ret = 0;
  }
  if ($lastWarningMsg) {
    $lastWarningMsg =~ s/^(.*) at \(eval.*$/$1/;
    readingsSingleUpdate ($hash, "warning", sprintf("condition c%02d",($condition+1)).": $lastWarningMsg",0);
  } else {
    delete ($defs{$hash->{NAME}}{READINGS}{warning});
  }
  $lastWarningMsg="";
  $cmdFromAnalyze = undef;

  return ($ret,$err);
}



sub
DOIF_cmd ($$$$)
{
  my ($hash,$nr,$subnr,$event)=@_;
  my $pn = $hash->{NAME};
  my $ret;
  my $cmd;
  my $err="";
  my $repeatnr;
  my $last_cmd=ReadingsVal($pn,"cmd_nr",0)-1;

  my @cmdpause=SplitDoIf(':',AttrVal($pn,"cmdpause",""));
  my @sleeptimer=SplitDoIf(':',AttrVal($pn,"repeatcmd",""));
  my ($seconds, $microseconds) = gettimeofday();
  my $cmdpauseValue=EvalValueDoIf($hash,"cmdpause",$cmdpause[$nr]);
  if ($cmdpauseValue and $subnr==0) {
    return undef if ($seconds - time_str2num(ReadingsTimestamp($pn, "state", "1970-01-01 01:00:00")) < $cmdpauseValue);
  }
  if (AttrVal($pn,"repeatsame","")) {
   my @repeatsame=SplitDoIf(':',AttrVal($pn,"repeatsame",""));
   my $repeatsameValue=EvalValueDoIf($hash,"repeatsame",$repeatsame[$nr]);
    if ($subnr == 0) {
      if ($repeatsameValue) {
        $repeatnr=ReadingsVal($pn,"cmd_count",0);
        if ($last_cmd == $nr) {
          if ($repeatnr < $repeatsameValue) {
            $repeatnr++;
          } else {
            delete ($defs{$hash->{NAME}}{READINGS}{cmd_count}) if (defined ($sleeptimer[$nr]) and (AttrVal($pn,"do","") eq "always" or AttrVal($pn,"do","") eq "resetwait"));
            return undef;
          }
        } else {
          $repeatnr=1;
        }
        readingsSingleUpdate ($hash, "cmd_count", $repeatnr,1);
      } else {
        return undef if ($last_cmd == $nr and $subnr==0 and (AttrVal($pn,"do","") ne "always" and AttrVal($pn,"do","") ne "resetwait"));
        delete ($defs{$hash->{NAME}}{READINGS}{cmd_count});
      }
    }
  }
  if (AttrVal($pn,"waitsame","")) {
    my @waitsame=SplitDoIf(':',AttrVal($pn,"waitsame",""));
    my $waitsameValue=EvalValueDoIf($hash,"waitsame",$waitsame[$nr]);
    if ($subnr == 0) {
      if ($waitsameValue) {
        my $cmd_nr="cmd_".($nr+1);
        if (ReadingsVal($pn,"waitsame","") eq $cmd_nr) {
          if ($seconds - time_str2num(ReadingsTimestamp($pn, "waitsame", "1970-01-01 01:00:00"))  > $waitsameValue) {
            readingsSingleUpdate ($hash, "waitsame", $cmd_nr,1);
            return undef;
          }
        } else {
          readingsSingleUpdate ($hash, "waitsame", $cmd_nr,1);
          return undef;
        }
      }
      delete ($defs{$hash->{NAME}}{READINGS}{waitsame});
    }
  }
  if ($hash->{do}{$nr}{$subnr}) {
     $cmd=$hash->{do}{$nr}{$subnr};
     my $eventa=$hash->{helper}{triggerEvents};
     my $events="";
     if ($eventa) {
        $events=join(",",@{$eventa});
     }
     $cmd =~ s/\$DEVICE/$hash->{helper}{triggerDev}/g;
     $cmd =~ s/\$EVENTS/$events/g;
     $cmd =~ s/\$EVENT/$hash->{helper}{event}/g;
     #my $idx = 0;
     #my $evt;
     #foreach my $part (split(" ", $hash->{helper}{event})) {
     #  $evt='\$EVTPART'.$idx;
     #  $cmd =~ s/$evt/$part/g;
     #  $idx++;
     #}
     #readingsSingleUpdate ($hash, "Event",$hash->{helper}{event},0);
     ($cmd,$err)=ParseCommandsDoIf($hash,$cmd,1);
  }
  DOIF_SetState ($hash,$nr,$subnr,$event,$err);
  if (defined $hash->{do}{$nr}{++$subnr}) {
    my $last_cond=ReadingsVal($pn,"cmd_nr",0)-1;
    if (DOIF_SetSleepTimer($hash,$last_cond,$nr,$subnr,$event,-1,undef)) {
      DOIF_cmd ($hash,$nr,$subnr,$event);
    }
  } else {
    if (($sleeptimer[$nr])) {
      my $last_cond=ReadingsVal($pn,"cmd_nr",0)-1;
      if (DOIF_SetSleepTimer($hash,$last_cond,$nr,0,$event,-1,$sleeptimer[$nr])) {
        DOIF_cmd ($hash,$nr,$subnr,$event);
      }
    }
  }
  #delete $hash->{helper}{cur_cmd_nr};
  return undef;
}


sub CheckiTimerDoIf($$$)
{
  my ($device,$itimer,$eventa)=@_;
  my $max = int(@{$eventa});
  my $found;
  return 1 if ($itimer =~ /\[$device(\]|,.+\])/);
  for (my $j = 0; $j < $max; $j++) {
    if ($eventa->[$j] =~ "^(.+): ") {
      $found = ($itimer =~ /\[$device:$1(\]|:.+\]|,.+\])/);
      if ($found) {
        return 1;
      }
    }
  }
  return 0;
}



sub CheckReadingDoIf($$)
{
  my ($readings,$eventa)=@_;
  my $max = int(@{$eventa});
  my $s;
  my $found=0;
  my $device;
  my $reading;
 
  if (!defined $readings) {
    return 1;
  }
  foreach my $item (split(/ /,$readings)) {
    ($device,$reading)=(split(":",$item));
    if (defined $reading) {
      for (my $j = 0; $j < $max; $j++) {
        $s = $eventa->[$j];
        $s = "" if(!defined($s));
        $found = ($s =~ m/^$reading: /);
        if ($found) {
          return 1;
        }
      }
    }
  }
  return 0;
}

sub CheckRegexpDoIf
{
  my ($hash,$type,$device,$id,$eventa,$readingupdate)=@_;
  my $nameExp;
  my $notifyExp;
  my $event;
  my @idlist;
  my @devlist;
  
  return undef if (!defined $hash->{Regex}{$type});
  if ($id eq "") {
    if (defined $hash->{Regex}{$type}{$device}) {
      return 1;
    }
    @devlist=("");
  } else {
    @devlist=("$device","");
  }
  
  foreach my $dev (@devlist){
    if (defined $hash->{Regex}{$type}{$dev}) {
      @idlist=($id eq "") ? (keys %{$hash->{Regex}{$type}{$dev}}):($id);
      foreach my $id (@idlist) {
        foreach my $i (keys %{$hash->{Regex}{$type}{$dev}{$id}}) {
          #$event=($type eq "cond") ? "c".($id+1) : $id;
          if ($hash->{Regex}{$type}{$dev}{$id}{$i} =~ /([^\:]*):(.*)/) {
            $nameExp=$1;
            $notifyExp=$2;
          } else {
            $nameExp=$hash->{Regex}{$type}{$dev}{$id}{$i};
          }
          $nameExp="" if (!$nameExp);
          $notifyExp="" if (!$notifyExp);
          if ($nameExp eq "" or $device =~ /$nameExp/) {
            my $events="";
            if ($eventa) {
              $events=join(",",@{$eventa});
            }
            if ($notifyExp eq "") {
              if ($readingupdate==1) {
                #readingsSingleUpdate ($hash, "matched_regex_$id",$events,0);
              } elsif ($readingupdate==2) {
                #readingsBulkUpdate ($hash, "matched_event_$event"."_".($i+1),$events);
              }
              return $i;
            }
            my $max = int(@{$eventa});
            my $s;
            my $found;
            for (my $j = 0; $j < $max; $j++) {
              $s = $eventa->[$j];
              $s = "" if(!defined($s));
              $found = ($s =~ m/$notifyExp/);
              if ($found) {
                if ($readingupdate==1) {
                  #readingsSingleUpdate ($hash, "matched_regex_$id",$s,0);
                } elsif ($readingupdate==2) {
                  #readingsBulkUpdate ($hash, "matched_event_$event"."_".($i+1),$s);
                }
                return $i;
              }
            }
          }
        }
      }
    }
  }
  return undef;
}

sub DOIF_Perl_Trigger 
{
  my ($hash,$device)= @_;
  my $timerNr=-1;
  my $ret;
  my $err;
  my $event="$device";
  my $pn=$hash->{NAME};
  my $max_cond=keys %{$hash->{condition}};
  my $j;
  my @triggerEvents;
  for (my $i=0; $i<$max_cond;$i++) {
    if ($device eq "") {# timer
      my $found=0;
      if (defined ($hash->{timers}{$i})) {
        foreach $j (split(" ",$hash->{timers}{$i})){
          if ($hash->{timer}{$j} == 1) {
            $found=1;
            $timerNr=$j;
            last;
          }
        }
      }
      next if (!$found);
      $event="timer_".($timerNr+1);
      @triggerEvents=($event);
      $hash->{helper}{triggerEvents}=\@triggerEvents;
      $hash->{helper}{triggerDev}="";
      $hash->{helper}{event}=$event;
    } else { #event
      if (!defined CheckRegexpDoIf($hash,"cond", $device,$i,$hash->{helper}{triggerEvents},1)) {
        next if (!defined ($hash->{devices}{$i}));
        next if ($hash->{devices}{$i} !~ / $device /);
        next if (AttrVal($pn, "checkReadingEvent", 0) and !CheckReadingDoIf ($hash->{readings}{$i},$hash->{helper}{triggerEventsState}) and (defined $hash->{internals}{$i} ? $hash->{internals}{$i} !~ / $device:.+ /:1))
      }
      $event="$device";
    }
    if (($ret,$err)=DOIF_CheckCond($hash,$i)) {
      if ($err) {
        Log3 $hash->{Name},4,"$hash->{NAME}: $err in perl block ".($i+1) if ($ret != -1);
        if ($hash->{perlblock}{$i}) {
          readingsSingleUpdate ($hash, "block_$hash->{perlblock}{$i}", $err,0);
        } else {
          readingsSingleUpdate ($hash, sprintf("block_%02d",($i+1)), $err,0);
        }
      } else {
        if ($hash->{perlblock}{$i}) {
          readingsSingleUpdate ($hash, "block_$hash->{perlblock}{$i}", "executed",0);
        } else {
          readingsSingleUpdate ($hash, sprintf("block_%02d",($i+1)), "executed",0);
        }
      }
    }
  }
  return undef;
}

sub DOIF_Trigger 
{
  my ($hash,$device,$checkall)= @_;
  my $timerNr=-1;
  my $ret;
  my $err;
  my $doelse=0;
  my $event="$device";
  my $pn=$hash->{NAME};
  my $max_cond=keys %{$hash->{condition}};
  my $last_cond=ReadingsVal($pn,"cmd_nr",0)-1;
  my $j;
  my @triggerEvents;
  if (AttrVal($pn, "checkall", 0) =~ "1|all|timer" and $device eq "") {
    for ($j=0; $j<$hash->{helper}{last_timer};$j++) {
      if ($hash->{timer}{$j}==1) {
        $timerNr=$j; #first timer
        last;
      }
    }
  }
  for (my $i=0; $i<$max_cond;$i++) {
    if ($device eq "") {# timer
      my $found=0;
      if (defined ($hash->{timers}{$i})) {
        foreach $j (split(" ",$hash->{timers}{$i})) {
          if ($hash->{timer}{$j} == 1) {
            $found=1;
            $timerNr=$j;
            last;
          }
        }
      }
      next if (!$found and AttrVal($pn, "checkall", 0) !~ "1|all|timer");
      $event="timer_".($timerNr+1);
      @triggerEvents=($event);
      $hash->{helper}{triggerEvents}=\@triggerEvents;
      $hash->{helper}{triggerDev}="";
      $hash->{helper}{event}=$event;
    } else { #event
      if (!defined CheckRegexpDoIf($hash,"cond", $device,$i,$hash->{helper}{triggerEvents},1)) {
        if (AttrVal($pn, "checkall", 0) !~ "1|all|event" and !defined $checkall) {
          next if (!defined ($hash->{devices}{$i}));
          next if ($hash->{devices}{$i} !~ / $device /);
          next if (AttrVal($pn, "checkReadingEvent", 0) and !CheckReadingDoIf ($hash->{readings}{$i},$hash->{helper}{triggerEventsState}) and (defined $hash->{internals}{$i} ? $hash->{internals}{$i} !~ / $device:.+ /:1))
        }
      }
      $event="$device";
    }
    if (($ret,$err)=DOIF_CheckCond($hash,$i)) {
      if ($err) {
        Log3 $hash->{Name},4,"$hash->{NAME}: $err" if ($ret != -1);
        readingsSingleUpdate ($hash, "error", $err,0);
        return undef;
      }
      if ($ret) {
        $hash->{helper}{timerevents}=$hash->{helper}{triggerEvents};
        $hash->{helper}{timereventsState}=$hash->{helper}{triggerEventsState};
        $hash->{helper}{timerevent}=$hash->{helper}{event};
        $hash->{helper}{timerdev}=$hash->{helper}{triggerDev};
        if (DOIF_SetSleepTimer($hash,$last_cond,$i,0,$device,$timerNr,undef)) {
          DOIF_cmd ($hash,$i,0,$event);
          return 1;
        } else {
          return undef;
        }
      } else {
        $doelse = 1;
      }
    }
  }
  if ($doelse) {  #DOELSE
    if (defined ($hash->{do}{$max_cond}{0}) or ($max_cond == 1 and !(AttrVal($pn,"do","") or AttrVal($pn,"repeatsame","")))) {  #DOELSE
      $hash->{helper}{timerevents}=$hash->{helper}{triggerEvents};
      $hash->{helper}{timereventsState}=$hash->{helper}{triggerEventsState};
      $hash->{helper}{timerevent}=$hash->{helper}{event};
      $hash->{helper}{timerdev}=$hash->{helper}{triggerDev};
      if (DOIF_SetSleepTimer($hash,$last_cond,$max_cond,0,$device,$timerNr,undef)) {
        DOIF_cmd ($hash,$max_cond,0,$event) ;
        return 1;
      }
    }
  }
  return undef;
}


sub
DOIF_Notify($$)
{
  my ($hash, $dev) = @_;
  my $pn = $hash->{NAME};
  return "" if($attr{$pn} && $attr{$pn}{disable});
  return "" if (!$dev->{NAME});
  my $device;
  my $reading;
  my $internal;
  my $ret;
  my $err;
  my $eventa;
  my $eventas;
  
  $eventa = deviceEvents($dev, AttrVal($pn, "addStateEvent", 0));
  $eventas = deviceEvents($dev, 1);
  
  if ($dev->{NAME} eq "global" and (EventCheckDoif($dev->{NAME},"global",$eventa,'^INITIALIZED$') or EventCheckDoif($dev->{NAME},"global",$eventa,'^REREADCFG$')))
  {
    $hash->{helper}{globalinit}=1;
    # delete old timer-readings
    foreach my $key (keys %{$defs{$hash->{NAME}}{READINGS}}) {
      delete $defs{$hash->{NAME}}{READINGS}{$key} if ($key =~ "^timer_");
    }
    if ($hash->{helper}{last_timer} > 0){
      for (my $j=0; $j<$hash->{helper}{last_timer};$j++)
      {
        DOIF_SetTimer($hash,"DOIF_TimerTrigger",$j);
      }
    }
    
    if (AttrVal($pn,"initialize",0) and !AttrVal($pn,"disable",0)) {
      readingsBeginUpdate($hash);
      readingsBulkUpdate ($hash,"state",AttrVal($pn,"initialize",0));
      readingsBulkUpdate ($hash,"cmd_nr","0");
      readingsBulkUpdate ($hash,"cmd",0);
      readingsEndUpdate($hash, 0);
    }
    
    if (defined $hash->{perlblock}{init}) {
      if (($ret,$err)=DOIF_CheckCond($hash,$hash->{perlblock}{init})) {
        if ($err) {
          Log3 $hash->{Name},4,"$hash->{NAME}: $err in perl block init" if ($ret != -1);
          readingsSingleUpdate ($hash, "block_init", $err,0);
        } else {
          readingsSingleUpdate ($hash, "block_init", "executed",0);
        }
      }
    }

    my $startup=AttrVal($pn, "startup", 0);
    if ($startup  and !AttrVal($pn,"disable",0)) {
      $startup =~ s/\$SELF/$pn/g;
      my ($cmd,$err)=ParseCommandsDoIf($hash,$startup,1);
      Log3 ($pn,3,"$pn: error in startup: $err") if ($err);
    }
    
    my $uiTable=AttrVal($pn, "uiTable", 0);
    if ($uiTable){
      my $err=DOIF_uiTable_def($hash,$uiTable,"uiTable");
      Log3 ($pn,3,"$pn: error in uiTable: $err") if ($err);
    }
    
    my $uiState=AttrVal($pn, "uiState", 0);
    if ($uiState){
      my $err=DOIF_uiTable_def($hash,$uiState,"uiState");
      Log3 ($pn,3,"$pn: error in uiState: $err") if ($err);
    }
  }

  return "" if (!$hash->{helper}{globalinit});
  #return "" if (!$hash->{itimer}{all} and !$hash->{devices}{all} and !keys %{$hash->{Regex}});
  
  if (($hash->{itimer}{all}) and $hash->{itimer}{all} =~ / $dev->{NAME} /) {
  for (my $j=0; $j<$hash->{helper}{last_timer};$j++) {
	  if (CheckiTimerDoIf ($dev->{NAME},$hash->{time}{$j},$eventas)) {
        DOIF_SetTimer($hash,"DOIF_TimerTrigger",$j);
      }
    }
  }

  return "" if (defined $hash->{helper}{cur_cmd_nr});
  return "" if (ReadingsVal($pn,"mode","") eq "disabled");
  
  $ret=0;
  $hash->{helper}{DOIF_eventas} = ();
  
  if ((($hash->{devices}{all}) and $hash->{devices}{all} =~ / $dev->{NAME} /) or defined CheckRegexpDoIf($hash,"cond",$dev->{NAME},"",$eventa,0)){
    $hash->{helper}{cur_cmd_nr}="Trigger  $dev->{NAME}" if (AttrVal($hash->{NAME},"selftrigger","") ne "all");
    $hash->{helper}{triggerEvents}=$eventa;
    $hash->{helper}{triggerEventsState}=$eventas;
    $hash->{helper}{triggerDev}=$dev->{NAME};
    $hash->{helper}{event}=join(",",@{$eventa});

    if ($hash->{readings}{all}) {
      foreach my $item (split(/ /,$hash->{readings}{all})) {
        ($device,$reading)=(split(":",$item));
        if ($item and $device eq $dev->{NAME} and defined ($defs{$device}{READINGS}{$reading})) {
          if (!AttrVal($pn, "checkReadingEvent", 0) or CheckReadingDoIf ("$item",$eventas)) {
            readingsSingleUpdate ($hash, "e_".$dev->{NAME}."_".$reading,$defs{$device}{READINGS}{$reading}{VAL},0);
          }
        }
      }
    }
    if ($hash->{internals}{all}) {
      foreach my $item (split(/ /,$hash->{internals}{all})) {
        ($device,$internal)=(split(":",$item));
        readingsSingleUpdate ($hash, "e_".$dev->{NAME}."_".$internal,$defs{$device}{$internal},0) if ($item and $device eq $dev->{NAME} and defined ($defs{$device}{$internal}));
      }
    }
    if ($hash->{trigger}{all}) {
      if ($hash->{trigger}{all} =~ / $dev->{NAME} /) {
        readingsSingleUpdate ($hash, "e_".$dev->{NAME}."_events",join(",",@{$eventa}),0);
      }
    }
    readingsSingleUpdate ($hash, "Device",$dev->{NAME},0);
    $ret=$hash->{MODEL} eq "Perl" ? DOIF_Perl_Trigger($hash,$dev->{NAME}) : DOIF_Trigger($hash,$dev->{NAME});
  }
  
  if ((defined CheckRegexpDoIf($hash,"STATE",$dev->{NAME},"STATE",$eventa,1)) and !$ret) {
    $hash->{helper}{triggerEvents}=$eventa;
    $hash->{helper}{triggerEventsState}=$eventas;
    $hash->{helper}{triggerDev}=$dev->{NAME};
    $hash->{helper}{event}=join(",",@{$eventa});
    DOIF_SetState($hash,"",0,"","");
  }
  
  delete $hash->{helper}{cur_cmd_nr};
  
  $hash->{helper}{DOIF_Readings_events}= ();
  if (defined $hash->{Regex}{"DOIF_Readings"}) {
    foreach $device ("$dev->{NAME}","") {
      if (defined $hash->{Regex}{"DOIF_Readings"}{$device}) {
        #readingsBeginUpdate($hash);
        foreach my $reading (keys %{$hash->{Regex}{"DOIF_Readings"}{$device}}) {
          my $readingregex=CheckRegexpDoIf($hash,"DOIF_Readings",$dev->{NAME},$reading,$eventas,0);
          setDOIF_Reading($hash,$reading,$readingregex) if (defined($readingregex));
        }
        #readingsEndUpdate($hash, 1);
      }
    }
    if (defined ($hash->{helper}{DOIF_eventas})) { #$SELF events
      foreach my $reading (keys %{$hash->{Regex}{"DOIF_Readings"}{$hash->{NAME}}}) {
        my $readingregex=CheckRegexpDoIf($hash,"DOIF_Readings",$hash->{NAME},$reading,$hash->{helper}{DOIF_eventas},0);
        setDOIF_Reading($hash,$reading,$readingregex) if (defined($readingregex));
      }
    }
  }
  
  foreach my $table ("uiTable","uiState") {
    if (defined $hash->{Regex}{$table}) {
      foreach $device ("$dev->{NAME}","") {
        if (defined $hash->{Regex}{$table}{$device}) {
          foreach my $doifId (keys %{$hash->{Regex}{$table}{$device}}) {
            my $readingregex=CheckRegexpDoIf($hash,$table,$dev->{NAME},$doifId,$eventas,0);
            DOIF_UpdateCell($hash,$doifId,$hash->{NAME},$readingregex) if (defined($readingregex));
          }
        }
      }
      if (defined ($hash->{helper}{DOIF_eventas})) { #$SELF events
        foreach my $doifId (keys %{$hash->{Regex}{$table}{$hash->{NAME}}}) {
          my $readingregex=CheckRegexpDoIf($hash,$table,$hash->{NAME},$doifId,$hash->{helper}{DOIF_eventas},0);
          DOIF_UpdateCell($hash,$doifId,$hash->{NAME},$readingregex) if (defined($readingregex));
        }
      }
    }
  }
 
  if (defined $hash->{helper}{DOIF_Readings_events}) {
    if ($dev->{NAME} ne $hash->{NAME}) {
      @{$hash->{CHANGED}}=@{$hash->{helper}{DOIF_Readings_events}};
      @{$hash->{CHANGEDWITHSTATE}}=@{$hash->{helper}{DOIF_Readings_events}};
      DOIF_Notify($hash,$hash);
    }
  }
  return undef;
}

sub
DOIF_TimerTrigger ($)
{
  my ($timer)=@_;
  my $hash=${$timer}->{hash};
  my $pn = $hash->{NAME};
  my $localtime=${$timer}->{localtime};
  delete $hash->{triggertime}{$localtime};

  my $ret;
  my ($now, $microseconds) = gettimeofday();
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
  $hash->{helper}{cur_cmd_nr}="timer $localtime" if (AttrVal($hash->{NAME},"selftrigger","") ne "all");
  #$hash->{helper}{cur_cmd_nr}="timer $localtime";
  for (my $j=0; $j<$hash->{helper}{last_timer};$j++) {
    if (defined $hash->{localtime}{$j} and $hash->{localtime}{$j} == $localtime) {
      if (defined ($hash->{interval}{$j})) {
        if ($hash->{interval}{$j} != -1) {
          if (defined $hash->{realtime}{$j} eq $hash->{realtime}{$hash->{interval}{$j}}) {
            $hash->{timer}{$hash->{interval}{$j}}=0;
            next;
          }
        }
      }
      $hash->{timer}{$j}=1;
      if (!DOIF_time_once($hash,$j,$wday,$hash->{days}{$j})) {#check days
        $hash->{timer}{$j}=0;
      }
    }
  }
  $ret=($hash->{MODEL} eq "Perl" ? DOIF_Perl_Trigger($hash,"") : DOIF_Trigger($hash,"")) if (ReadingsVal($pn,"mode","") ne "disabled");
  for (my $j=0; $j<$hash->{helper}{last_timer};$j++) {
    $hash->{timer}{$j}=0;
    if (defined $hash->{localtime}{$j} and $hash->{localtime}{$j} == $localtime) {
      if (!AttrVal($hash->{NAME},"disable","")) {
        if (defined ($hash->{interval}{$j})) {
          if ($hash->{interval}{$j} != -1) {
            DOIF_SetTimer($hash,"DOIF_TimerTrigger",$hash->{interval}{$j}) ;
            DOIF_SetTimer($hash,"DOIF_TimerTrigger",$j) ;
          }
        } else {
          DOIF_SetTimer($hash,"DOIF_TimerTrigger",$j) ;
        }
      }
    }
  }
  delete ($hash->{helper}{cur_cmd_nr});
  return undef;
  #return($ret);
}

sub
DOIF_DetTime($$)
{
  my ($hash, $timeStr) = @_;
  my $rel=0;
  my $align;
  my $hr=0;
  my $err;
  my $h=0;
  my $m=0;
  my $s=0;
  my $fn;
  if (substr($timeStr,0,1) eq "+") {
    $timeStr=substr($timeStr,1);
    $rel=1;
  }
  my ($now, $microseconds) = gettimeofday();
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
  if($timeStr =~ m/^\[([0-9]+)\]:([0-5][0-9])$/) {
    $hr=$1;
    $rel=0;
    $align=$2;
  } elsif ($timeStr =~ m/^:([0-5][0-9])$/) {
    $align=$1;
  } elsif ($timeStr =~ m/^(\-?([0-9]+))$/) {
    $s=$1;
  } else {
    ($timeStr,$err)=ReplaceAllReadingsDoIf($hash,$timeStr,-3,1);
     return ($err) if ($err);
    ($err, $h, $m, $s, $fn) = GetTimeSpec($timeStr);
    return $err if ($err);
  }
  if (defined ($align)) {
    if ($rel) {
      if ($align > 0) {
        $m = (int($min/$align)+1)*$align;
        if ($m>=60) {
          $h = $hour+1;
          $m = 0;
        } else {
          $h = $hour;
        }
      }
      $rel=0;
    } else {
      $m=$align;
      if ($hr > 1) {
        $h = (int($hour/$hr)+1)*$hr;
        $h = 0 if ($h >=24);
      } else {
        if ($m <= $min) {
          $h = $hour+1;
        } else {
          $h = $hour;
        }
      }
    }
  }
  my $second = $h*3600+$m*60+$s;
  if ($second == 0 and $rel) {
    $err = "null is not allowed on a relative time";
  }
  return ($err, ($rel and !defined ($align)), $second);
}

sub
DOIF_CalcTime($$)
{
  my ($hash,$block)= @_;
  my $tailBlock;
  my $beginning;
  my $err;
  my $cmd="";
  my $rel="";
  my $relGlobal=0;
  my $reading;
  my $internal;
  my $device;
  my $pos;
  my $ret;
  if ($block=~ m/^\+\[([0-9]+)\]:([0-5][0-9])$/) {
    ($err,$rel,$block)=DOIF_DetTime($hash,$block);
    return ($block,$err,$rel);
  } elsif ($block =~ /^\+\(/ or $block =~ /^\+\[/) {
    $relGlobal=1;
    #$pos=pos($block);
    $block=substr($block,1);
  }
  if ($block =~ /^\(/) {
    ($beginning,$tailBlock,$err,$tailBlock)=GetBlockDoIf($block,'[\(\)]');
    return ($tailBlock,$err) if ($err);
  } else {
    if ($block =~ /^\[/) {
      ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($block,'[\[\]]');
      return ($block,$err) if ($err);
      ($block,$err,$device,$reading,$internal)=ReplaceReadingEvalDoIf($hash,$block,1);
      return ($block,$err) if ($err);
    }
    ($err,$rel,$block)=DOIF_DetTime($hash, $block);
    $rel=1 if ($relGlobal);
    return ($block,$err,$rel);
  }
  $tailBlock=$block;
  while ($tailBlock ne "") {
    ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\{\}]');
    return ($block,$err) if ($err);
    if ($block ne "") {
 #      $ret = eval $block;
 #      return($block." ",$@) if ($@);
 #      $block=$ret;
       ($err,$rel,$block)=DOIF_DetTime($hash,"{".$block."}");
       return ($block,$err) if ($err);
    }
    $cmd.=$beginning.$block;
  }
  $tailBlock=$cmd;
  $cmd="";
  while ($tailBlock ne "") {
    ($beginning,$block,$err,$tailBlock)=GetBlockDoIf($tailBlock,'[\[\]]');
    return ($block,$err) if ($err);
    if ($block ne "") {
      if ($block =~ /^\??[a-z0-9._]*[a-z._]+[a-z0-9._]*($|:.+$)/i) {
        ($block,$err,$device,$reading,$internal)=ReplaceReadingEvalDoIf($hash,$block,1);
        return ($block,$err) if ($err);
      }
      ($err,$rel,$block)=DOIF_DetTime($hash,$block);
      return ($block,$err) if ($err);
    }
    $cmd.=$beginning.$block;
  }
  $ret = eval $cmd;
  return($cmd." ",$@) if ($@);
  return ($ret,"null is not allowed on a relative time",$relGlobal) if ($ret == 0 and $relGlobal);
  return ($ret,"",$relGlobal);
}

sub
DOIF_SetTimer($$$)
{
  my ($hash, $func, $nr) = @_;
  my $timeStr=$hash->{time}{$nr};
  my $cond=$hash->{timeCond}{$nr};
  my $next_time;
  if (defined ($hash->{localtime}{$nr})) {
    my $old_lt=$hash->{localtime}{$nr};
    my $found=0;
    delete ($hash->{localtime}{$nr});
    delete ($hash->{realtime}{$nr});
    foreach my $lt (keys %{$hash->{localtime}}) {
      if ($hash->{localtime}{$lt} == $old_lt) {
        $found=1;
        last;
      }
    }
    if (!$found) {
      RemoveInternalTimer(\$hash->{triggertime}{$old_lt});
      delete ($hash->{triggertime}{$old_lt});
    }
  }
  my ($second,$err, $rel)=DOIF_CalcTime($hash,$timeStr);
  my $timernr=sprintf("timer_%02d_c%02d",($nr+1),($cond+1));
  if ($err)
  {
      readingsSingleUpdate ($hash,$timernr,"error: ".$err,AttrVal($hash->{NAME},"timerevent","")?1:0);
      Log3 $hash->{NAME},4 , "$hash->{NAME} ".$timernr." error: ".$err;
      #RemoveInternalTimer($timer);
      #$hash->{realtime}{$nr} = "00:00:00" if (!defined $hash->{realtime}{$nr});
      return $err;
  }

  if ($second < 0) {
    if ($rel) {
      readingsSingleUpdate ($hash,$timernr,"time offset: $second, negativ offset is not allowed",AttrVal($hash->{NAME},"timerevent","")?1:0);
      return($timernr,"time offset: $second, negativ offset is not allowed");
    } else {
      readingsSingleUpdate ($hash,$timernr,"time in seconds: $second, negative times are not allowed",AttrVal($hash->{NAME},"timerevent","")?1:0);
      return($timernr,"time in seconds: $second, negative times are not allowed");
    }
  }

  my ($now, $microseconds) = gettimeofday();
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
  my $isdst_now=$isdst;

  my $sec_today = $hour*3600+$min*60+$sec;
  my $midnight = $now-$sec_today;
  if ($rel) {
    $next_time =$now+$second;
  } else {
    $next_time = $midnight+$second;
  }

  if ($second <= $sec_today and !$rel) {
    $next_time+=86400;
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($next_time);
    if ($isdst_now != $isdst) {
      if ($isdst_now == 1) {
        $next_time+=3600 if ($isdst == 0);
      } else {
        $next_time-=3600 if ($second>=3*3600 or $second <= $sec_today and $second<2*3600);
      }
    }
  }

  my $next_time_str=strftime("%d.%m.%Y %H:%M:%S",localtime($next_time));
  $next_time_str.="\|".$hash->{days}{$nr} if (defined ($hash->{days}{$nr}));
  readingsSingleUpdate ($hash,$timernr,$next_time_str,AttrVal($hash->{NAME},"timerevent","")?1:0);
  $hash->{realtime}{$nr}=strftime("%H:%M:%S",localtime($next_time));
  $hash->{localtime}{$nr}=$next_time;
  if (!defined ($hash->{triggertime}{$next_time})) {
    $hash->{triggertime}{$next_time}{hash}=$hash;
    $hash->{triggertime}{$next_time}{localtime}=$next_time;
	InternalTimer($next_time, $func, \$hash->{triggertime}{$next_time}, 0);
  }
  return undef;
}

sub
DOIF_SetSleepTimer($$$$$$$)
{
  my ($hash,$last_cond,$nr,$subnr,$device,$timerNr,$repeatcmd)=@_;
  my $pn = $hash->{NAME};
  my $sleeptimer=$hash->{helper}{sleeptimer};
  my @waitdel=SplitDoIf(':',AttrVal($pn,"waitdel",""));
  my @waitdelsubnr=SplitDoIf(',',defined $waitdel[$sleeptimer] ? $waitdel[$sleeptimer] : "");
  my $err;

  if ($sleeptimer != -1 and (($sleeptimer != $nr or AttrVal($pn,"do","") eq "resetwait") or ($sleeptimer == $nr and $waitdelsubnr[$subnr]))) {
    RemoveInternalTimer($hash);
    #delete ($defs{$hash->{NAME}}{READINGS}{wait_timer});
    readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
    $hash->{helper}{sleeptimer}=-1;
    $subnr=$hash->{helper}{sleepsubtimer} if ($hash->{helper}{sleepsubtimer}!=-1 and $sleeptimer == $nr);
    return 0 if ($sleeptimer == $nr and $waitdelsubnr[$subnr]);
  }

  if ($timerNr >= 0 and !AttrVal($pn,"timerWithWait","")) {#Timer
    if ($last_cond != $nr or AttrVal($pn,"do","") eq "always" or AttrVal($pn,"do","") eq "resetwait" or AttrVal($pn,"repeatsame","")) {
      return 1;
    } else {
      return 0;
    }
  }
  if ($hash->{helper}{sleeptimer} == -1 and ($last_cond != $nr or $subnr > 0
      or AttrVal($pn,"do","") eq "always"
      or AttrVal($pn,"do","") eq "resetwait"
      or AttrVal($pn,"repeatsame","")
      or $repeatcmd)) {
    my $sleeptime=0;
    if ($repeatcmd) {
      $sleeptime=$repeatcmd;
    } else {
      my @sleeptimer=SplitDoIf(':',AttrVal($pn,"wait",""));
      if ($waitdelsubnr[$subnr]) {
        $sleeptime = $waitdelsubnr[$subnr];
      } else {
        my @sleepsubtimer=SplitDoIf(',',defined $sleeptimer[$nr]? $sleeptimer[$nr]: "");
        if ($sleepsubtimer[$subnr]) {
          $sleeptime=$sleepsubtimer[$subnr];
        }
      }
    }
    $sleeptime=EvalValueDoIf($hash,"wait",$sleeptime);
    if ($sleeptime) {
      my $seconds = gettimeofday();
      my $next_time = $seconds+$sleeptime;
      $hash->{helper}{sleeptimer}=$nr;
      $hash->{helper}{sleepsubtimer}=$subnr;
      $device="timer_".($timerNr+1) if ($timerNr >= 0);
      $hash->{helper}{sleepdevice}=$device;
      my $cmd_nr=$nr+1;
      if (defined $hash->{do}{$nr}{1}) {
        my $cmd_subnr=$subnr+1;
        readingsSingleUpdate ($hash,"wait_timer",strftime("%d.%m.%Y %H:%M:%S cmd_$cmd_nr"."_$cmd_subnr $device",localtime($next_time)),1);
      } else {
        readingsSingleUpdate ($hash,"wait_timer",strftime("%d.%m.%Y %H:%M:%S cmd_$cmd_nr $device",localtime($next_time)),1);
      }
      InternalTimer($next_time, "DOIF_SleepTrigger",$hash, 0);
      return 0;
    } elsif ($repeatcmd){
      return 0;
    } else {
      return 1;
    }
  } else {
    return 0;
  }
}

sub
DOIF_SleepTrigger ($)
{
  my ($hash)=@_;
  my $sleeptimer=$hash->{helper}{sleeptimer};
  my $sleepsubtimer=$hash->{helper}{sleepsubtimer};
  my $pn = $hash->{NAME};
  $hash->{helper}{cur_cmd_nr}="wait_timer" if (!AttrVal($hash->{NAME},"selftrigger",""));
  $hash->{helper}{triggerEvents}=$hash->{helper}{timerevents};
  $hash->{helper}{triggerEventsState}=$hash->{helper}{timereventsState};
  $hash->{helper}{event}=$hash->{helper}{timerevent};
  $hash->{helper}{triggerDev}=$hash->{helper}{timerdev};
  readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
  $hash->{helper}{sleeptimer}=-1;
  $hash->{helper}{sleepsubtimer}=-1;
  if (ReadingsVal($pn,"mode","") ne "disabled") {
    DOIF_cmd ($hash,$sleeptimer,$sleepsubtimer,$hash->{helper}{sleepdevice});
  }
  delete $hash->{helper}{cur_cmd_nr};
  return undef;
}

sub DOIF_set_Timer
{
  my ($hash,$event,$seconds)=@_;
  my $name=$hash->{NAME};
  my $timername="$name:$event";
  my $current = gettimeofday();
  my $next_time = $current+$seconds;
  RemoveInternalTimer($timername);
  $hash->{ptimer}{$timername}=$next_time;
  if ($seconds > 0) {
    $event =~ s/\W/_/g;
    readingsSingleUpdate ($hash,"timer_$event",strftime("%d.%m.%Y %H:%M:%S",localtime($next_time)),0);
  }
  InternalTimer($next_time, "DOIF_PerlTimer", $timername, 0);
}

sub DOIF_get_Timer
{
  my ($hash,$event)=@_;
  my $name=$hash->{NAME};
  my $timername="$name:$event";
  my $current = gettimeofday();
  if (defined $hash->{ptimer}{$timername}) {
    my $sec=$hash->{ptimer}{$timername}-$current;
    if ($sec > 0) {
      return ($sec);
    } else {
      delete ($hash->{ptimer}{$timername});
      return (0);
    }
  } else {
    return (0);
  }
}

sub DOIF_PerlTimer
{
  my ($timername)=@_;
  my ($name,$event)=split(":",$timername);
  DoTrigger($name, $event);
  $event =~ s/\W/_/g;
  delete ($defs{$name}{READINGS}{"timer_$event"});
}

sub DOIF_del_Timer
{
  my ($hash,$event)=@_;
  my $name=$hash->{NAME};
  my $timername="$name:$event";
  delete $hash->{ptimer}{$timername};
  $event =~ s/\W/_/g;
  delete ($defs{$hash->{NAME}}{READINGS}{"timer_$event"});
  RemoveInternalTimer($timername);
}

sub DOIF_set_Event
{
  my ($hash,$event)=@_;
  DOIF_set_Timer($hash,$event,0);
}

sub
CmdDoIfPerl($$)
{
  my ($hash, $tail) = @_;
  my $perlblock="";
  my $beginning;
  my $ret;
  my $err="";
  my $i=0;

#def modify
  if ($init_done)
  {
    DOIF_delTimer($hash);
    DOIF_delAll ($hash);
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"state","initialized");
    readingsBulkUpdate ($hash,"mode","enabled");
    readingsEndUpdate($hash, 1);
    $hash->{helper}{globalinit}=1;
  }
  
  $hash->{helper}{last_timer}=0;
  $hash->{helper}{sleeptimer}=-1;

  return("","") if ($tail =~ /^ *$/);

  $tail =~ s/set_Timer[ \t]*\(/DOIF_set_Timer\(\$hash,/g;  
  $tail =~ s/get_Timer[ \t]*\(/DOIF_get_Timer\(\$hash,/g;
  $tail =~ s/del_Timer[ \t]*\(/DOIF_del_Timer\(\$hash,/g;
  $tail =~ s/set_Event[ \t]*\(/DOIF_set_Event\(\$hash,/g;
  $tail =~ s/set_Reading[ \t]*\(/readingsSingleUpdate\(\$hash,/g;
  $tail =~ s/\$_(\w+)/\$hash->\{var\}\{$1\}/g;
  
  while ($tail ne "") {
    ($beginning,$perlblock,$err,$tail)=GetBlockDoIf($tail,'[\{\}]');
    return ($perlblock,$err) if ($err);
    ($perlblock,$err)=ReplaceAllReadingsDoIf($hash,$perlblock,$i,0);
    return ($perlblock,$err) if ($err);
    $hash->{condition}{$i}=$perlblock;
    if ($beginning =~ /(\w*)[\s]*$/) {
      $hash->{perlblock}{$i}=$1;
      if ($1 eq "init") {
        $hash->{perlblock}{init}=$i;
        if ($init_done) {
          if (($ret,$err)=DOIF_CheckCond($hash,$hash->{perlblock}{init})) {
            if ($err) {
              Log3 $hash->{Name},4,"$hash->{NAME}: $err in perl block init" if ($ret != -1);
              readingsSingleUpdate ($hash, "block_init", $err,0);
            } else {
              readingsSingleUpdate ($hash, "block_init", "executed",0);
            }
          }
        }
      }
    }
    $i++;
  }
  return("","")
}


#############################
sub
CmdDoIf($$)
{
  my ($hash, $tail) = @_;
  my $cond="";
  my $err="";
  my $if_cmd="";
  my $if_cmd_ori="";
  my $else_cmd="";
  my $else_cmd_ori="";
  my $tailBlock;
  my $eval="";
  my $beginning;
  my $i=0;
  my $j=0;
  my $last_do;

#def modify
  if ($init_done)
  {
    DOIF_delTimer($hash);
    DOIF_delAll ($hash);
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"cmd",0);
    readingsBulkUpdate($hash,"state","initialized");
    readingsBulkUpdate ($hash,"mode","enabled");
    readingsEndUpdate($hash, 1);
    $hash->{helper}{globalinit}=1;
  }

  $hash->{helper}{last_timer}=0;
  $hash->{helper}{sleeptimer}=-1;

  return("","") if ($tail =~ /^ *$/);
  
  $tail =~ s/\n/ /g;
  
  while ($tail ne "") {
    return($tail, "no left bracket of condition") if ($tail !~ /^ *\(/);
    #condition
    ($beginning,$cond,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
    return ($cond,$err) if ($err);
    ($cond,$err)=ReplaceAllReadingsDoIf($hash,$cond,$i,0);
    return ($cond,$err) if ($err);
    return ($tail,"no condition") if ($cond eq "");
    $hash->{condition}{$i}=$cond;
    #DOIF
    $if_cmd_ori="";
    $j=0;
    while ($tail =~ /^\s*(\(|\{)/) {
	  if ($tail =~ /^\s*\(/) {
        ($beginning,$if_cmd_ori,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
        return ($if_cmd_ori,$err) if ($err);
	  } elsif ($tail =~ /^\s*\{/) {
	    ($beginning,$if_cmd_ori,$err,$tail)=GetBlockDoIf($tail,'[\{\}]');
        return ($if_cmd_ori,$err) if ($err);
		$if_cmd_ori="{".$if_cmd_ori."}";
	  }
      ($if_cmd,$err)=ParseCommandsDoIf($hash,$if_cmd_ori,0);
      return ($if_cmd,$err) if ($err);
      #return ($tail,"no commands") if ($if_cmd eq "");
      $hash->{do}{$i}{$j++}=$if_cmd_ori;
    }
    $hash->{do}{$i}{0}=$if_cmd_ori if ($j==0); #do without brackets
    $last_do=$i;
    $tail =~ s/^\s*$//g;
    if (length($tail)) {
      $tail =~ /^\s*DOELSEIF/g;
      if (pos($tail)) {
        $tail=substr($tail,pos($tail));
        if (!length($tail)) {
          return ($tail,"no DOELSEIF block");
        }
      } else {
        last if ($tail =~ /^\s*DOELSE/);
        return ($tail,"expected DOELSEIF or DOELSE");
      }
    }
    $i++;
  }
  #DOELSE
  if (length($tail)) {
    $tail =~ /^\s*DOELSE/g;
    if (pos($tail)) {
      $tail=substr($tail,pos($tail));
    } else {
      return ($tail,"expected DOELSE");
    }
    $j=0;
    while ($tail =~ /^\s*\(/) {
      ($beginning,$else_cmd_ori,$err,$tail)=GetBlockDoIf($tail,'[\(\)]');
       return ($else_cmd_ori,$err) if ($err);
       ($else_cmd,$err)=ParseCommandsDoIf($hash,$else_cmd_ori,0);
       return ($else_cmd,$err) if ($err);
       $hash->{do}{$last_do+1}{$j++}=$else_cmd_ori;
    }
    $hash->{do}{$last_do+1}{0}=$else_cmd_ori if ($j==0); #doelse without brackets
  }
  return("","")
}

sub
DOIF_Define($$$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $cmd) = split(/[\s]+/, $def, 3);
  return undef if (AttrVal($hash->{NAME},"disable",""));
  my $err;
  my $msg;
  
  if (!$cmd) {
    $cmd="";
  } else {
    $cmd =~ s/(##.*\n)|(##.*$)/ /g;
    $cmd =~ s/\$SELF/$hash->{NAME}/g;
  }
  
  if ($cmd eq "" or $cmd =~ /^\s*\(/) {
    $hash->{MODEL}="FHEM";  
    ($msg,$err)=CmdDoIf($hash,$cmd);
    #delete $defs{$hash->{NAME}}{".AttrList"};
    setDevAttrList($hash->{NAME});
  } else {
    $hash->{MODEL}="Perl";
    #$defs{$hash->{NAME}}{".AttrList"}  = "disable:0,1 loglevel:0,1,2,3,4,5,6 startup state initialize notexist checkReadingEvent:1,0 addStateEvent:1,0 weekdays setList:textField-long readingList DOIF_Readings:textField-long uiTable:textField-long ".$readingFnAttributes;
    setDevAttrList($hash->{NAME},"disable:0,1 loglevel:0,1,2,3,4,5,6 startup state initialize notexist checkReadingEvent:1,0 addStateEvent:1,0 weekdays setList:textField-long readingList DOIF_Readings:textField-long uiTable:textField-long ".$readingFnAttributes);
    ($msg,$err)=CmdDoIfPerl($hash,$cmd);
  }  
  if ($err ne "") {
    $msg=$cmd if (!$msg);
    my $errmsg="$name $type: $err: $msg";
    return $errmsg;
  } else {
    return undef;
  }
}

#################################

sub
DOIF_Attr(@)
{
  my @a = @_;
  my $hash = $defs{$a[1]};
  my $ret="";
  if (($a[0] eq "set" and $a[2] eq "disable" and ($a[3] eq "0")) or (($a[0] eq "del" and $a[2] eq "disable")))
  {
    my $cmd = $defs{$hash->{NAME}}{DEF};
    my $msg;
    my $err;
    
    if (!$cmd) {
      $cmd="";
    } else {
      $cmd =~ s/(##.*\n)|(##.*$)/ /g;
      $cmd =~ s/\$SELF/$hash->{NAME}/g;
    }
    
    if ($cmd eq "" or $cmd =~ /^ *\(/) {
      $hash->{MODEL}="FHEM";  
      ($msg,$err)=CmdDoIf($hash,$cmd);
    } else {
      $hash->{MODEL}="Perl";
      ($msg,$err)=CmdDoIfPerl($hash,$cmd);
    }  

    if ($err ne "") {
      $msg=$cmd if (!$msg);
      return ("$err: $msg");
    }
  } elsif($a[0] eq "set" and $a[2] eq "disable" and $a[3] eq "1") {
    DOIF_delTimer($hash);
    DOIF_delAll ($hash);
    readingsBeginUpdate($hash);
    readingsBulkUpdate ($hash, "state", "deactivated");
    readingsBulkUpdate ($hash, "mode", "deactivated");
    readingsEndUpdate  ($hash, 1);
  } elsif($a[0] eq "set" && $a[2] eq "state") {
      delete $hash->{Regex}{"STATE"};
      my ($block,$err)=ReplaceAllReadingsDoIf($hash,$a[3],-2,0);
      return $err if ($err);
  } elsif($a[0] eq "del" && $a[2] eq "state") {
      delete $hash->{Regex}{"STATE"};
  } elsif($a[0] eq "set" && $a[2] eq "wait") {
      RemoveInternalTimer($hash);
      readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
      $hash->{helper}{sleeptimer}=-1;
  } elsif($a[0] eq "del" && $a[2] eq "repeatsame") {
    delete ($defs{$hash->{NAME}}{READINGS}{cmd_count});
  } elsif($a[0] eq "del" && $a[2] eq "waitsame") {
    delete ($defs{$hash->{NAME}}{READINGS}{waitsame});
  } elsif($a[0] eq "set" && $a[2] eq "DOIF_Readings") {
    my ($def,$err)=addDOIF_Readings($hash,$a[3]);
    if ($err) {
       return ("error in DOIF_Readings $def, $err");
    }
  } elsif($a[0] eq "del" && ($a[2] eq "DOIF_Readings")) {
    delete ($hash->{DOIF_Readings});
    delete $hash->{Regex}{"DOIF_Readings"}
  } elsif($a[0] eq "set" && ($a[2] eq "uiTable" || $a[2] eq "uiState")) {
    if ($init_done) {
      my $err=DOIF_uiTable_def($hash,$a[3],$a[2]);
      return $err if ($err);
      DOIF_reloadFW;
    }
  } elsif($a[0] eq "del" && ($a[2] eq "uiTable" || $a[2] eq "uiState")) {
    delete ($hash->{Regex}{$a[2]});
    delete ($hash->{$a[2]});
  } elsif($a[0] eq "set" && $a[2] eq "startup") {
    my ($cmd,$err)=ParseCommandsDoIf($hash,$a[3],0);
    if ($err) {
     return ("error in startup $a[3], $err");
    }
  }
  return undef;
}

sub
DOIF_Undef
{
  my ($hash, $name) = @_;
  $hash->{DELETED} = 1;
  DOIF_delTimer($hash);
  return undef;
}

sub
DOIF_Set($@)
{
  my ($hash, @a) = @_;
  my $pn = $hash->{NAME};
  my $arg = $a[1];
  my $value = (defined $a[2]) ? $a[2] : "";
  my $ret="";

  if ($arg eq "disable" or  $arg eq "initialize" or  $arg eq "enable") {
    if (AttrVal($hash->{NAME},"disable","")) {
      return ("modul ist deactivated by disable attribut, delete disable attribut first");
    }
  }
  if ($arg eq "disable") {
      readingsBeginUpdate  ($hash);
      readingsBulkUpdate($hash,"last_cmd",ReadingsVal($pn,"state",""));
      readingsBulkUpdate($hash, "state", "disabled");
      readingsBulkUpdate($hash, "mode", "disabled");
      readingsEndUpdate    ($hash, 1);
  } elsif ($arg eq "initialize" ) {
      readingsSingleUpdate ($hash,"mode","enabled",1);
      delete ($defs{$hash->{NAME}}{READINGS}{cmd_nr});
	  delete ($defs{$hash->{NAME}}{READINGS}{cmd});
	  delete ($defs{$hash->{NAME}}{READINGS}{cmd_seqnr});
      delete ($defs{$hash->{NAME}}{READINGS}{cmd_event});
      readingsSingleUpdate($hash, "state","initialize",1);
  } elsif ($arg eq "enable" ) {
      #delete ($defs{$hash->{NAME}}{READINGS}{mode});
      readingsSingleUpdate ($hash,"state",ReadingsVal($pn,"last_cmd",""),0) if (ReadingsVal($pn,"last_cmd","") ne "");
      delete ($defs{$hash->{NAME}}{READINGS}{last_cmd});
      readingsSingleUpdate ($hash,"mode","enabled",1)
  } elsif ($arg eq "checkall" ) {
    $hash->{helper}{triggerDev}="";
    DOIF_Trigger ($hash,$pn,1);
  } elsif ($arg =~ /^cmd_(.*)/ ) {
    if (ReadingsVal($pn,"mode","") ne "disabled") {
	  if ($hash->{helper}{sleeptimer} != -1) {
         RemoveInternalTimer($hash);
	     readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
	     $hash->{helper}{sleeptimer}=-1;
      }
      DOIF_cmd ($hash,$1-1,0,"set_cmd_".$1);
	}
  } elsif ($arg eq "?") {
      my $setList = AttrVal($pn, "setList", " ");
      $setList =~ s/\n/ /g;
	  my $cmdList="";
    my $checkall="";
    if ($hash->{MODEL} ne "Perl") {
      $checkall="checkall:noArg";
      my $max_cond=keys %{$hash->{condition}};
      $max_cond++ if (defined ($hash->{do}{$max_cond}{0}) or ($max_cond == 1 and !(AttrVal($pn,"do","") or AttrVal($pn,"repeatsame",""))));
      for (my $i=0; $i <$max_cond;$i++) {
       $cmdList.="cmd_".($i+1).":noArg ";
	    }
    }
	  return "unknown argument ? for $pn, choose one of disable:noArg initialize:noArg enable:noArg $checkall $cmdList $setList";
   } else {
      my @rl = split(" ", AttrVal($pn, "readingList", ""));
      my $doRet;
      eval {
        if(@rl && grep /\b$arg\b/, @rl) {
          my $v = shift @a;
          $v = shift @a;
          readingsSingleUpdate($hash, $v, join(" ",@a), 1);
          $doRet = 1;
        }
      };
      return if($doRet);
	  if (ReadingsVal($pn,"mode","") ne "disabled") {
		  my @cmdState=SplitDoIf('|',AttrVal($hash->{NAME},"cmdState",""));
		  my @cmdSubState;
		  for (my $i=0; $i < @cmdState;$i++) {
		    @cmdSubState=SplitDoIf(',',$cmdState[$i]);
		    if ($arg eq EvalCmdStateDoIf($hash,$cmdSubState[0])) {
			  if ($hash->{helper}{sleeptimer} != -1) {
				RemoveInternalTimer($hash);
				readingsSingleUpdate ($hash, "wait_timer", "no timer",1);
				$hash->{helper}{sleeptimer}=-1;
			  }
			  DOIF_cmd ($hash,$i,0,"set_".$arg."_cmd_".($i+1));
			  last;
			}
		  }
		}
      #return "unknown argument $arg for $pn, choose one of disable:noArg initialize:noArg enable:noArg cmd $setList";
    }
  return $ret;
}

sub
DOIF_Get($@)
{
  my ($hash, @a) = @_;
  my $pn = $a[0];
  return "$pn: get needs at least one parameter" if(@a < 2);
  my $arg= $a[1];
  if( $arg eq "html" ) {
    return DOIF_RegisterEvalAll($hash,$pn,"uiTable");
  }

  return undef;
}


1;

=pod
=item helper
=item summary    universal module, it works event- and time-controlled
=item summary_DE universelles Modul, welches ereignis- und zeitgesteuert Anweisungen ausführt
=begin html

<a name="DOIF"></a>
<h3>DOIF</h3>
<ul>
DOIF is a universal module. It works event- and time-controlled.<br>
<br>
It combines the functionality of a notify, at-, watchdog command with logical queries.<br>
<br>
Complex problems can be solved with this module, which would otherwise be solved only with several modules at different locations in FHEM. This leads to clear solutions and simplifies their maintenance.<br>
<br>
Logical queries are created in conditions using Perl operators.
These are combined with information from states, readings, internals of devices or times in square brackets.
Arbitrary Perl functions can also be specified that are defined in FHEM.
The module is triggered by time or by events information through the Devices specified in the condition.
If a condition is true, the associated FHEM- or Perl commands are executed.<br>
<br>
Syntax FHEM-Mode:<br>
<br>
<ol><code>define &lt;name&gt; DOIF (&lt;condition&gt;) (&lt;commands&gt;) DOELSEIF (&lt;condition&gt;) (&lt;commands&gt;) DOELSEIF ... DOELSE (&lt;commands&gt;)</code></ol>
<br>
Syntax Perl-Mode:<br>
<br>
<ol><code>define &lt;name&gt; DOIF &lt;Blockname&gt; {&lt;Perl with DOIF-Syntax&gt;} &lt;Blockname&gt; {&lt;Perl with DOIF-Syntax&gt;} ...</code></ol>
<br>
The commands are always processed from left to right. There is only one command executed, namely the first, for which the corresponding condition in the processed sequence is true. In addition, only the conditions are checked, which include a matching device of the trigger (in square brackets).<br>
<br>
<b>Features</b><br>
<ol><br>
+ intuitive syntax, as used in branches (if - elseif-....elseif - else) in higher-level languages<br>
+ in the condition of any logical queries can be made as well as perl functions are used (full perl support)<br>
+ it can be any FHEM commands and perl commands are executed<br>
+ syntax checking at the time of definition are identified missing brackets<br>
+ status is specified with <code>[&lt;devicename&gt;]</code>, readings with <code>[&lt;devicename&gt;:&lt;readingname&gt;]</code> or internals with <code>[&lt;devicename&gt;:&&lt;internal&gt;]</code><br>
+ time information on the condition: <code>[HH:MM:SS]</code> or <code>[HH:MM]</code> or <code>[&lt;seconds&gt;]</code><br>
+ indirect time on the condition: <code>[[&lt;devicename&gt;]]</code> or <code>[[&lt;devicename&gt;:&lt;readingname&gt;]]</code> or <code>[{&lt;perl-function&gt;}]</code><br>
+ time calculation on the condition: <code>[(&lt;time calculation in Perl with time syntax specified above&gt;)]</code><br>
+ time intervals: <code>[&lt;begin&gt;-&lt;end&gt;]</code> for <code>&lt;begin&gt;</code> and <code>&lt;end&gt;</code>, the above time format can be selected.<br>
+ relative times preceded by a plus sign <code>[+&lt;time&gt;]</code> or <code>[+&lt;begin&gt;-+&lt;end&gt;]</code> combined with Perl functions<br>
+ weekday control: <code>[&lt;time&gt;|012345678]</code> or <code>[&lt;begin&gt;-&lt;end&gt;|012345678]</code> (0-6 corresponds to Sunday through Saturday) such as 7 for $we and 8 for !$we<br>
+ statuses, readings, internals und time intervals for only queries without trigger with [?...]<br>
+ DOELSEIF cases and DOELSE at the end are optional<br>
+ delay specification with resetting is possible (watchdog function)<br>
+ the execution part can be left out in each case. So that the module can be used for pure status display.<br>
+ definition of the status display with use of any readings or statuses<br>
</ol><br>
<br>
Many examples with english identifiers - see <a href="http://fhem.de/commandref_DE.html#DOIF">german section</a>.
<br>
</ul>
=end html
=begin html_DE

<a name="DOIF"></a>
<h3>DOIF</h3>
<ul>
DOIF (ausgeprochen: du if, übersetzt: tue wenn) ist ein universelles Modul mit UI, welches ereignis- und zeitgesteuert in Abhängigkeit definierter Bedingungen Anweisungen ausführt.<br>
<br>
Mit diesem Modul ist es möglich, einfache wie auch komplexere Automatisierungsvorgänge zu definieren oder in Perl zu programmieren.
Ereignisse, Zeittrigger, Readings oder Status werden durch DOIF-spezifische Angaben in eckigen Klammern angegeben. Sie führen zur Triggerung des Moduls und damit zur Auswertung und Ausführung der definierten Anweisungen.<br>
<br>
Das Modul verfügt über zwei Modi: FHEM-Modus und <a href="#DOIF_Perl_Modus"><b>[NEU]</b> Perl-Modus</a>. Der Modus eines definierten DOIF-Devices wird automatisch aufgrund der Definition vom Modul erkannt
(FHEM-Modus beginnt mit einer runden Klammer auf).
Beide Modi sind innerhalb eines DOIF-Devices nicht miteinander kombinierbar. Im Folgendem wird der FHEM-Modus beschrieben.<br> 
<br>
Syntax FHEM-Modus:<br>
<br>
<ol><code>define &lt;name&gt; DOIF (&lt;Bedingung&gt;) (&lt;Befehle&gt;) DOELSEIF (&lt;Bedingung&gt;) (&lt;Befehle&gt;) DOELSEIF ... DOELSE (&lt;Befehle&gt;)</code></ol>
<br>
Im FHEM-Modus lassen sich Automatisierungsabläufe ohne Perlkenntnisse definieren. 
Die Angaben werden immer von links nach rechts abgearbeitet. Logische Abfragen werden in DOIF/DOELSEIF-Bedingungen vornehmlich mit Hilfe von and/or-Operatoren erstellt. 
Zu beachten ist, dass nur die Bedingungen überprüft werden,
die zum ausgelösten Event das dazughörige Device bzw. die dazugehörige Triggerzeit beinhalten.
Kommt ein Device in mehreren Bedingungen vor, so wird immer nur ein Kommando ausgeführt, und zwar das erste,
für das die dazugehörige Bedingung in der abgearbeiteten Reihenfolge wahr ist.<br><br>
Das DOIF-Modul arbeitet mit Zuständen. Jeder Ausführungszweig DOIF/DOELSEIF..DOELSEIF/DOELSE stellt einen eigenen Zustand dar (cmd_1, cmd_2, usw.).
Das Modul merkt sich den zuletzt ausgeführten Ausführungszweig und wiederholt diesen standardmäßig nicht.
Ein Ausführungszweig wird erst dann wieder ausgeführt, wenn zwischenzeitlich ein anderer Ausführungszweig ausgeführt wurde, also ein Zustandswechsel stattgefunden hat.
Dieses Verhalten ist sinnvoll, um zu verhindern, dass zyklisch sendende Sensoren (Temperatur, Feuchtigkeit, Helligkeit, usw.) zu ständiger Wiederholung des selben Befehls oder Befehlsabfolge führen.<br>
Das Verhalten des Moduls im FHEM-Modus kann durch diverse Attribute verändert werden. Im FHEM-Modus wird maximal nur ein Zweig pro Ereignis- oder Zeit-Trigger ausgeführt, es gibt nur einen Wait-Timer.<br>

<br>
<a name="DOIF_Einfache_Anwendungsbeispiele"></a>
<u>Einfache Anwendungsbeispiele (vgl. <a href="#DOIF_Einfache_Anwendungsbeispiele_Perl">Anwendungsbeispiele im Perl-Modus</a>):</u><ol>
<br>
Fernbedienung (Ereignissteuerung)<br>
<br>
<code>define di_rc_tv DOIF ([remotecontol:"on"]) (set tv on) DOELSE (set tv off)</code><br>
<br>
Zeitschaltuhr (Zeitsteuerung)<br>
<br>
<code>define di_clock_radio DOIF ([06:30|Mo Di Mi] or [08:30|Do Fr Sa So]) (set radio on) DOELSEIF ([08:00|Mo Di Mi] or [09:30|Do Fr Sa So]) (set radio off)</code><br>
<br>
Kombinierte Ereignis- und Zeitsteuerung<br>
<br>
<code>define di_lamp DOIF ([06:00-09:00] and [sensor:brightness] &lt; 40) (set lamp on) DOELSE (set lamp off)</code><br>
</ol><br>
Eine ausführliche Erläuterung der obigen Anwendungsbeispiele kann hier nachgelesen werden:
<a href="https://wiki.fhem.de/wiki/DOIF/Einsteigerleitfaden,_Grundfunktionen_und_Erl%C3%A4uterungen#Erste_Schritte_mit_DOIF:_Zeit-_und_Ereignissteuerung">Erste Schritte mit DOIF</a><br><br>
<br>
<a name="DOIF_Inhaltsuebersicht"></a>
<b>Inhaltsübersicht</b><br>
<ul><br>
  <a href="#DOIF_Lesbarkeit_der_Definitionen">Lesbarkeit der Definitionen</a><br>
  <a href="#DOIF_Ereignissteuerung">Ereignissteuerung</a><br>
  <a href="#DOIF_Teilausdruecke_abfragen">Teilausdrücke abfragen</a><br>
  <a href="#DOIF_Ereignissteuerung_ueber_Auswertung_von_Events">Ereignissteuerung über Auswertung von Events</a><br>
  <a href="#DOIF_Angaben_im_Ausfuehrungsteil">Angaben im Ausführungsteil</a><br>
  <a href="#DOIF_Filtern_nach_Zahlen">Filtern nach Ausdrücken mit Ausgabeformatierung</a><br>
  <a href="#DOIF_aggregation">Aggregieren von Werten</a><br>
  <a href="#DOIF_Zeitsteuerung">Zeitsteuerung</a><br>
  <a href="#DOIF_Relative_Zeitangaben">Relative Zeitangaben</a><br>
  <a href="#DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet">Zeitangaben nach Zeitraster ausgerichtet</a><br>
  <a href="#DOIF_Relative_Zeitangaben_nach_Zeitraster_ausgerichtet">Relative Zeitangaben nach Zeitraster ausgerichtet</a><br>
  <a href="#DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet_alle_X_Stunden">Zeitangaben nach Zeitraster ausgerichtet alle X Stunden</a><br>
  <a href="#DOIF_Wochentagsteuerung">Wochentagsteuerung</a><br>
  <a href="#DOIF_Zeitsteuerung_mit_Zeitintervallen">Zeitsteuerung mit Zeitintervallen</a><br>
  <a href="#DOIF_Indirekten_Zeitangaben">Indirekten Zeitangaben</a><br>
  <a href="#DOIF_Zeitsteuerung_mit_Zeitberechnung">Zeitsteuerung mit Zeitberechnung</a><br>
  <a href="#DOIF_Kombination_von_Ereignis_und_Zeitsteuerung_mit_logischen_Abfragen">Kombination von Ereignis- und Zeitsteuerung mit logischen Abfragen</a><br>
  <a href="#DOIF_Zeitintervalle_Readings_und_Status_ohne_Trigger">Zeitintervalle, Readings und Status ohne Trigger</a><br>
  <a href="#DOIF_Nutzung_von_Readings_Status_oder_Internals_im_Ausfuehrungsteil">Nutzung von Readings, Status oder Internals im Ausführungsteil</a><br>
  <a href="#DOIF_Berechnungen_im_Ausfuehrungsteil">Berechnungen im Ausführungsteil</a><br>
  <a href="#DOIF_notexist">Ersatzwert für nicht existierende Readings oder Status</a><br>
  <a href="#DOIF_wait">Verzögerungen</a><br>
  <a href="#DOIF_timerWithWait">Verzögerungen von Timern</a><br>
  <a href="#DOIF_do_resetwait">Zurücksetzen des Waittimers für das gleiche Kommando</a><br>
  <a href="#DOIF_repeatcmd">Wiederholung von Befehlsausführung</a><br>
  <a href="#DOIF_cmdpause">Zwangspause für das Ausführen eines Kommandos seit der letzten Zustandsänderung</a><br>
  <a href="#DOIF_repeatsame">Begrenzung von Wiederholungen eines Kommandos</a><br>
  <a href="#DOIF_waitsame">Ausführung eines Kommandos nach einer Wiederholung einer Bedingung</a><br>
  <a href="#DOIF_waitdel">Löschen des Waittimers nach einer Wiederholung einer Bedingung</a><br>
  <a href="#DOIF_checkReadingEvent">Readingauswertung nur beim Event des jeweiligen Readings</a><br>
  <a href="#DOIF_addStateEvent">Eindeutige Statuserkennung</a><br>
  <a href="#DOIF_selftrigger">Triggerung durch selbst ausgelöste Events</a><br>
  <a href="#DOIF_timerevent">Setzen der Timer mit Event</a><br>
  <a href="#DOIF_Zeitspanne_eines_Readings_seit_der_letzten_Aenderung">Zeitspanne eines Readings seit der letzten Änderung</a><br>
  <a href="#DOIF_setList__readingList">Darstellungselement mit Eingabemöglichkeit im Frontend und Schaltfunktion</a><br>
  <a href="#DOIF_cmdState">Status des Moduls</a><br>
  <a href="#DOIF_uiTable">uiTable, das User Interface</a><br>
  <a href="#DOIF_Reine_Statusanzeige_ohne_Ausfuehrung_von_Befehlen">Reine Statusanzeige ohne Ausführung von Befehlen</a><br>
  <a href="#DOIF_state">Anpassung des Status mit Hilfe des Attributes <code>state</code></a><br>
  <a href="#DOIF_Readings">Erzeugen berechneter Readings<br>
  <a href="#DOIF_initialize">Vorbelegung des Status mit Initialisierung nach dem Neustart mit dem Attribut <code>initialize</code></a><br>
  <a href="#DOIF_disable">Deaktivieren des Moduls</a><br>
  <a href="#DOIF_setcmd">Bedingungslose Ausführen von Befehlszweigen</a><br>
  <a href="#DOIF_Initialisieren_des_Moduls">Initialisieren des Moduls</a><br>
  <a href="#DOIF_Weitere_Anwendungsbeispiele">Weitere Anwendungsbeispiele</a><br>
  <a href="#DOIF_Zu_beachten">Zu beachten</a><br>
  <a href="https://wiki.fhem.de/wiki/DOIF">DOIF im FHEM-Wiki</a><br>
  <a href="https://forum.fhem.de/index.php/board,73.0.html">DOIF im FHEM-Forum</a><br>
  <a href="#DOIF_Kurzreferenz">Kurzreferenz</a><br>
  <a href="#DOIF_PerlFunktionen_kurz">Perl-Funktionen</a><br>
  <a href="#DOIF_Perl_Modus">DOIF Perl-Modus</a><br>
  <a href="#DOIF_Einfache_Anwendungsbeispiele_Perl">Anwendungsbeispiele im Perl-Modus</a><br>
<!-- Vorlage Inhaltsübersicht und Sprungmarke-->
  <a href="#DOIF_"></a><br>
<a name="DOIF_"></a>
<!-- Vorlage Rücksprung zur Inhaltsübersicht-->
<!--&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>-->
</ul>
  <a name="DOIF_Attribute"></a>
  <a href="#DOIF_Attribute_kurz"><b>Attribute</b></a><br>
  <ul>
  <a href="#DOIF_addStateEvent">addStateEvent</a> &nbsp;
  <a href="#DOIF_checkall">checkall</a> &nbsp;
  <a href="#DOIF_checkReadingEvent">checkReadingEvent</a> &nbsp;
  <a href="#DOIF_cmdpause">cmdpause</a> &nbsp;
  <a href="#DOIF_cmdState">cmdState</a> &nbsp;
  <a href="#DOIF_Readings">DOIF_Readings</a> &nbsp;
  <a href="#DOIF_disable">disable</a> &nbsp;
  <a href="#DOIF_do_always">do always</a> &nbsp;
  <a href="#DOIF_do_resetwait">do resetwait</a> &nbsp;
  <a href="#DOIF_initialize">initialize</a> &nbsp;
  <a href="#DOIF_notexist">notexist</a> &nbsp;
  <a href="#DOIF_repeatcmd">repeatcmd</a> &nbsp;
  <a href="#DOIF_repeatsame">repeatsame</a> &nbsp;
  <a href="#DOIF_selftrigger">selftrigger</a> &nbsp;
  <a href="#DOIF_setList__readingList">readingList</a> &nbsp;
  <a href="#DOIF_setList__readingList">setList</a> &nbsp;
  <a href="#DOIF_startup">startup</a> &nbsp;
  <a href="#DOIF_state">state</a> &nbsp;
  <a href="#DOIF_timerevent">timerevent</a> &nbsp;
  <a href="#DOIF_timerWithWait">timerWithWait</a> &nbsp;
  <a href="#DOIF_uiTable">uiTable</a> &nbsp;
  <a href="#DOIF_wait">wait</a> &nbsp;
  <a href="#DOIF_waitdel">waitdel</a> &nbsp;
  <a href="#DOIF_waitsame">waitsame</a> &nbsp;
  <a href="#DOIF_weekdays">weekdays</a> &nbsp;
  <br><a href="#readingFnAttributes">readingFnAttributes</a> &nbsp;
  </ul>
<br>
  <a href="#DOIF_setBefehle"><b>Set Befehle</b></a><br>
  <ul>
  <a href="#DOIF_setcheckall">checkall</a> &nbsp;
  <a href="#DOIF_setdisable">disable</a> &nbsp;
  <a href="#DOIF_setenable">enable</a> &nbsp;
  <a href="#DOIF_Initialisieren_des_Moduls">initialize</a> &nbsp;
  <a href="#DOIF_setcmd">cmd</a> &nbsp;
  </ul>
<br>
  <a href="#DOIF_getBefehle"><b>Get Befehle</b></a><br>
  <ul>
  <a href="#HTML-Code von uiTable">html</a> 
  </ul>
<br>
<a name="DOIF_Lesbarkeit_der_Definitionen"></a>
<b>Lesbarkeit der Definitionen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Da die Definitionen im Laufe der Zeit recht umfangreich werden können, sollten die gleichen Regeln, wie auch beim Programmieren in höheren Programmiersprachen, beachtet werden.
Dazu zählen: das Einrücken von Befehlen, Zeilenumbrüche sowie das Kommentieren seiner Definition, damit man auch später noch die Funktionalität seines Moduls nachvollziehen kann.<br>
<br>
Das Modul unterstützt dazu Einrückungen, Zeilenumbrüche an beliebiger Stelle und Kommentierungen beginnend mit ## bis zum Ende der Zeile.
Die Formatierungen lassen sich im DEF-Editor der Web-Oberfläche vornehmen.<br>
<br>
So könnte eine Definition aussehen:<br>
<br>
<code>define di_Modul DOIF ([Switch1] eq "on" and [Switch2] eq "on")  ## wenn Schalter 1 und Schalter 2 on ist<br>
<br>
<ol>(set lamp on) ## wird Lampe eingeschaltet</ol>
<br>
DOELSE ## im sonst-Fall, also wenn einer der Schalter off ist<br>
<br>
<ol>(set lamp off) ## wird die Lampe ausgeschaltet</ol></code>
<br>
Im Folgenden wird die Funktionalität des Moduls im Einzelnen an vielen praktischen Beispielen erklärt.<br>
<br>
<a name="DOIF_Ereignissteuerung"></a>
<b>Ereignissteuerung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Vergleichende Abfragen werden, wie in Perl gewohnt, mit Operatoren <code>==, !=, <, <=, >, >=</code> bei Zahlen und mit <code>eq, ne, lt, le, gt, ge, =~, !~</code> bei Zeichenketten angegeben.
Logische Verknüpfungen sollten zwecks Übersichtlichkeit mit <code>and</code> bzw. <code>or</code> vorgenommen werden.
Selbstverständlich lassen sich auch alle anderen Perl-Operatoren verwenden, da die Auswertung der Bedingung vom Perl-Interpreter vorgenommen wird.
Die Reihenfolge der Auswertung wird, wie in höheren Sprachen üblich, durch runde Klammern beeinflusst.
Status werden mit <code>[&lt;devicename&gt;]</code>, Readings mit <code>[&lt;devicename&gt;:&lt;readingname&gt;]</code>,
Internals mit <code>[&lt;devicename&gt;:&&lt;internal&gt;]</code> angegeben.<br>
<br>
<u>Anwendungsbeispiel</u>: Einfache Ereignissteuerung mit einmaliger Ausführung beim Zustandswechsel, "remotecontrol" ist hier ein Device, es wird in eckigen Klammern angegeben. Ausgewertet wird der Status des Devices - nicht das Event.<br>
<br>
<code>define di_garage DOIF ([remotecontrol] eq "on") (set garage on) DOELSEIF ([remotecontrol] eq "off") (set garage off)</code><br>
<br>
Das Modul wird getriggert, sobald das angegebene Device hier "remotecontrol" ein Event erzeugt. Das geschieht, wenn irgendein Reading oder der Status von "remotecontrol" aktualisiert wird.
Ausgewertet wird hier der Zustand des Status von remotecontrol nicht das Event selbst. Die Ausführung erfolgt standardmäßig einmalig nur nach Zustandswechsel des Moduls.
Das bedeutet, dass ein mehrmaliges Drücken der Fernbedienung auf "on" nur einmal "set garage on" ausführt. Die nächste mögliche Ausführung ist "set garage off", wenn Fernbedienung "off" liefert.
<a name="DOIF_do_always"></a>
Wünscht man eine Ausführung des gleichen Befehls mehrfach nacheinander bei jedem Trigger, unabhängig davon welchen Zustand das DOIF-Modul hat,
weil z. B. Garage nicht nur über die Fernbedienung geschaltet wird, dann muss man das per "do always"-Attribut angeben:<br>
<br>
<code>attr di_garage do always</code><br>
<br>
Bei der Angabe von zyklisch sendenden Sensoren (Temperatur, Feuchtigkeit, Helligkeit usw.) wie z. B.:<br>
<br>
<code>define di_heating DOIF ([sens:temperature] < 20) (set heating on)</code><br>
<br>
ist die Nutzung des Attributes <code>do always</code> nicht sinnvoll, da das entsprechende Kommando hier: "set heating on" jedes mal ausgeführt wird,
wenn der Temperatursensor in regelmäßigen Abständen eine Temperatur unter 20 Grad sendet.
Ohne <code>do always</code> wird hier dagegen erst wieder "set heating on" ausgeführt, wenn der Zustand des Moduls auf "cmd_2" gewechselt hat, also die Temperatur zwischendurch größer oder gleich 20 Grad war.<br>
<br>
Soll bei Nicht-Erfüllung aller Bedingungen ein Zustandswechsel erfolgen, so muss man ein DOELSE am Ende der Definition anhängen. Ausnahme ist eine einzige Bedingung ohne do always, wie im obigen Beispiel,
 hierbei wird intern ein virtuelles DOELSE angenommen, um bei Nicht-Erfüllung der Bedingung einen Zustandswechsel in cmd_2 zu provozieren, da sonst nur ein einziges Mal geschaltet werden könnte, da das Modul aus dem cmd_1-Zustand nicht mehr herauskäme.<br>
<br>
<a name="DOIF_Teilausdruecke_abfragen"></a>
<b>Teilausdrücke abfragen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Abfragen nach Vorkommen eines Wortes innerhalb einer Zeichenkette können mit Hilfe des Perl-Operators <code>=~</code> vorgenommen werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Garage soll beim langen Tastendruck öffnen, hier: wenn das Wort "Long" im Status vorkommt (bei HM-Komponenten stehen im Status noch weitere Informationen).<br>
<br>
<code>define di_garage DOIF ([remotecontrol] =~ "Long") (set garage on)<br>
attr di_garage do always</code><br>
<br>
Weitere Möglichkeiten bei der Nutzung des Perl-Operators: <code>=~</code>, insbesondere in Verbindung mit regulären Ausdrücken, können in der Perl-Dokumentation nachgeschlagen werden.<br>
<br>
<a name="DOIF_Ereignissteuerung_ueber_Auswertung_von_Events"></a>
<b>Ereignissteuerung über Auswertung von Events</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Eine Alternative zur Auswertung von Status oder Readings ist das Auswerten von Ereignissen (Events) mit Hilfe von regulären Ausdrücken. Der Suchstring wird als regulärer Ausdruck in Anführungszeichen angegeben.
Die Syntax lautet: <code>[&lt;devicename&gt;:"&lt;regex&gt;"]</code><br>
<br>
<u>Anwendungsbeispiel</u>: wie oben, jedoch wird hier nur das Ereignis (welches im Eventmonitor erscheint) ausgewertet und nicht der Status von "remotecontrol" wie im vorherigen Beispiel<br>
<br>
<code>define di_garage DOIF ([remotecontrol:"on"]) (set garage on) DOELSEIF ([remotecontrol:"off"]) (set garage off)</code><br>
<br>
In diesem Beispiel wird nach dem Vorkommen von "on" innerhalb des Events gesucht.
Falls "on" gefunden wird, wird der Ausdruck wahr und der DOIF-Fall wird ausgeführt, ansonsten wird der DOELSEIF-Fall entsprechend ausgewertet.
Die Auswertung von reinen Ereignissen bietet sich dann an, wenn ein Modul keinen Status oder Readings benutzt, die man abfragen kann, wie z. B. beim Modul "sequence".
Die Angabe von regulären Ausdrücken kann recht komplex werden und würde die Aufzählung aller Möglichkeiten an dieser Stelle den Rahmen sprengen.
Weitere Informationen zu regulären Ausdrücken sollten in der Perl-Dokumentation nachgeschlagen werden.
Die logische Verknüpfung "and" mehrerer Ereignisse ist nicht sinnvoll, da zu einem Zeitpunkt immer nur ein Ereignis zutreffen kann.<br>
<br>
Die alte Syntax <code>[&lt;devicename&gt;:?&lt;regex&gt;]</code> wird aus Kompatibilitätsgründen noch unterstützt, sollte aber nicht mehr benutzt werden.<br>
<br>
Sollen Events verschiedener Devices ausgewertet werden, so lässt sich folgende Syntax anwenden: <code>["&lt;device regex&gt;:&lt;event regex&gt;"]</code><br>
<br>
Im Gegensatz zum notify werden vom DOIF-Modul selbst keine Regex-Sonderzeichen hinzugefügt. Insb. wird kein ^ für Anfang vorangestellt, bzw. kein $ für Ende angehängt.<br>
<br>
Beispiele für Regex-Angaben: <br>
<br>
["FS"] triggert auf alle Devices, die "FS" im Namen beinhalten <br>
["^FS"] triggert auf alle Devices, die mit "FS" im Namen anfangen <br>
["FS:temp"] triggert auf alle Devices, die "FS" im Namen und "temp" im Event beinhalten <br>
([":^temp"]) triggert auf beliebige Devices, die im Event mit "temp" beginnen <br>
(["^FS$:^temp$"] triggert auf Devices, die genau "FS" heißen und im Event genau "temp" vorkommt <br>
[""] triggert auf alles<br>
<br>
In der Bedingung und im Ausführungsteil werden die Schlüsselwörter $SELF durch den eigenen Namen des DOIF-Moduls, $DEVICE durch das aktuelle Device, $EVENT durch die passende Eventzeile, $EVENTS kommagetrennt durch alle Eventzeilen des Triggers ersetzt.<br>
<br>
Entsprechend können Perl-Variablen in der DOIF-Bedingung ausgewertet werden, sie werden in Kleinbuchstaben geschrieben. Sie lauten: $device, $event, $events<br>
<br>
<u>Anwendungsbeispiele</u>:<br>
<br>
Loggen aller Ereignisse in FHEM<br>
<br>
<code>define di_all_events DOIF ([""]) ({Log 3,"Events from device $DEVICE:$EVENTS"})<br>
<br>
attr di_all_events do always<br></code>
<br>
"Fenster offen"-Meldung<br>
<br>
<code>define di_window_open (["^window_:open"]) (set Pushover msg 'alarm' 'open windows $DEVICE' '' 2 'persistent' 30 3600)<br>
<br>
attr di_window_open do always</code><br>
<br>
Hier werden alle Fenster, die mit dem Device-Namen "window_" beginnen auf "open" im Event überwacht.<br>
<br>
Rollladen auf Lüften stellen<br>
<br>
<code>define di_air DOIF (["^window_contact_:open|tilted"]) (set {("$DEVICE"=~/^window_contact_(.*)/;"shutters_$1")} 10)<br>
<br>
attr di_air do always</code><br>
<br>
Hier werden alle Fensterkontakte, die mit dem Device-Namen "window_contact_" beginnen auf "open" oder "tilted" im Event überwacht
und der entsprechende Rollladen mit der gleichen Endung auf Lüften per <code>set shutters_&lt;postfix&gt; 10</code> gestellt.
In diesem Beispiel wird die Möglichkeit genutzt bei FHEM-Befehlen Perlcode innerhalb der Klammern {(...)} einzufügen. Siehe <a href="#DOIF_Berechnungen_im_Ausfuehrungsteil">Berechnungen im Ausführungsteil</a><br>
<br>
<a href="#DOIF_Fenster_offen_Meldung">Verzögerte "Fenster offen"-Meldung im Perl-Modus für mehrere Fenster</a><br>
<br>
Batteriewarnung per E-Mail verschicken<br>
<br>
<code>define di_battery DOIF ([":battery: low"] and [?$SELF:B_$DEVICE] ne "low")<br>
  <ol>({DebianMail('yourname@gmail.com', 'FHEM - battery warning from device: $DEVICE')}, setreading $SELF B_$DEVICE low)</ol>
DOELSEIF ([":battery: ok"] and [?$SELF:B_$DEVICE] ne "ok")<br>
  <ol>(setreading $SELF B_$DEVICE ok)</ol>
<br>
attr di_battery do always</code><br>
<br>
Eine aktuelle Übersicht aller Batterie-Status entsteht gleichzeitig in den Readings des di_battery-DOIF-Moduls.<br>
<br>
<br>
Allgemeine Ereignistrigger können ebenfalls so definiert werden, dass sie nicht nur wahr zum Triggerzeitpunkt und sonst nicht wahr sind,
 sondern Inhalte des Ereignisses zurückliefern. Initiiert wird dieses Verhalten durch die Angabe eines Default-Wertes.<br>
<br>
Syntax:<br>
<br>
<code>["regex for trigger",&lt;default value&gt;]</code><br>
<br>
Anwendungsbeispiel:<br>
<br>
<code>define di_warning DOIF ([":^temperature",0]< 0 and [06:00-09:00] ) (set pushmsg danger of frost)</code><br>
<br>
Damit wird auf alle Devices getriggert, die mit "temperature" im Event beginnen. Zurückgeliefert wird der Wert, der im Event hinter "temperature: " steht.
Wenn kein Event stattfindet, wird der Defaultwert, hier 0,  zurückgeliefert.
<br>
Ebenfalls kann ein Ereignisfilter mit Ausgabeformatierung angegeben werden.<br>
<br>
Syntax:<br>
<br>
<code>["regex for trigger":"&lt;regex filter&gt;":&lt;output&gt;,&lt;default value&gt;]</code><br>
<br>
Regex-Filter- und Output-Parameter sind optional. Der Default-Wert ist verpflichtend.<br>
<br>
Die Angaben zum Filter und Output funktionieren, wie die beim Reading-Filter. Siehe: <a href="#DOIF_Filtern_nach_Zahlen">Filtern nach Ausdrücken mit Ausgabeformatierung</a><br>
<br>
Wenn kein Filter, wie obigen Beispiel, angegeben wird, so wird intern folgende Regex vorbelegt: "[^\:]*: (.*)"  Damit wird der Wert hinter der Readingangabe genommen.
Durch eigene Regex-Filter-Angaben kann man beliebige Teile des Events herausfiltern, ggf. über Output formatieren und in der Bedingung entsprechend auswerten,
 ohne auf Readings zurückgreifen zu müssen.<br>
<br>
<a name="DOIF_Filtern_nach_Zahlen"></a>
<b>Filtern nach Ausdrücken mit Ausgabeformatierung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Syntax: <code>[&lt;device&gt;:&lt;reading&gt;|&lt;internal&gt;:d&lt;number&gt|"&lt;regex&gt;":&lt;output&gt;]</code><br>
<br>
d - Der Buchstabe "d" ist ein Synonym für das Filtern nach Dezimalzahlen, es entspricht intern dem regulären Ausdruck "(-?\d+(\.\d+)?)". Ebenfalls lässt sich eine Dezimalzahl auf eine bestimmte Anzahl von Nachkommastellen runden. Dazu wird an das "d" eine Ziffer angehängt. Mit der Angabe d0 wird die Zahl auf ganze Zahlen gerundet.<br>
&lt;Regex&gt;- Der reguläre Ausdruck muss in Anführungszeichen angegeben werden. Dabei werden Perl-Mechanismen zu regulären Ausdrücken mit Speicherung der Ergebnisse in Variablen $1, $2 usw. genutzt.<br>
&lt;Output&gt; - ist ein optionaler Parameter, hier können die in den Variablen $1, $2, usw. aus der Regex-Suche gespeicherten Informationen für die Aufbereitung genutzt werden. Sie werden in Anführungszeichen bei Texten oder in Perlfunktionen angegeben. Wird kein Output-Parameter angegeben, so wird automatisch $1 genutzt.<br>
<br>
Beispiele:<br>
<br>
Es soll aus einem Reading, das z. B. ein Prozentzeichen beinhaltet, nur der Zahlenwert für den Vergleich genutzt werden:<br>
<br>
<code>define di_heating DOIF ([adjusting:actuator:d] &lt; 10) (set heating off) DOELSE (set heating on)</code><br>
<br>
Alternativen für die Nutzung der Syntax am Beispiel des Filterns nach Zahlen:<br>
<br>
<code>[mydevice:myreading:d]</code><br>
entspricht:<br>
<code>[mydevice:myreading:"(-?\d+(\.\d+)?)"]</code><br>
entspricht:<br>
<code>[mydevice:myreading:"(-?\d+(\.\d+)?)":$1]</code><br>
entspricht:<br>
<code>[mydevice:myreading:"(-?\d+(\.\d+)?)":"$1"]</code><br>
entspricht:<br>
<code>[mydevice:myreading:"(-?\d+(\.\d+)?)":sprintf("%s":$1)]</code><br>
<br>
Es soll die Zahl aus einem Reading auf 3 Nachkommastellen formatiert werden:<br>
<br>
<code>[mydevice:myreading:d3]</code><br>
<br>
Es soll aus einem Text eine Zahl herausgefiltert werden und anschließend gerundet auf zwei Nachkommastellen mit der Einheit °C ausgeben werden:<br>
<br>
<code>... (set mydummy [mydevice:myreading:d2:"$1 °C"])</code><br>
<br>
Es sollen aus einem Reading der Form "HH:MM:SS" die Stunden, Minuten und Sekunden separieret werden:<br>
<br>
<code>[mydevice:myreading:"(\d\d):(\d\d):(\d\d)":"hours: $1, minutes $2, seconds: $3"]</code><br>
<br>
Der Inhalt des Dummys Alarm soll in einem Text eingebunden werden:<br>
<br>
<code>[alarm:state:"(.*)":"state of alarm is $1"]</code><br>
<br>
Die Definition von regulären Ausdrücken mit Nutzung der Perl-Variablen $1, $2 usw. kann in der Perldokumentation nachgeschlagen werden.<br>
<br>
<a name="DOIF_Angaben_im_Ausfuehrungsteil"></a>
<b>Angaben im Ausführungsteil</b>:&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Der Ausführungsteil wird durch runde Klammern eingeleitet. Es werden standardmäßig FHEM-Befehle angegeben, wie z. B.: <code>...(set lamp on)</code><br>
<br>
Sollen mehrere FHEM-Befehle ausgeführt werden, so werden sie mit Komma statt mit Semikolon angegeben <code>... (set lamp1 on, set lamp2 off)</code><br>
<br>
Falls ein Komma nicht als Trennzeichen zwischen FHEM-Befehlen gelten soll, so muss der FHEM-Ausdruck zusätzlich in runde Klammern gesetzt werden: <code>...((set lamp1,lamp2 on),set switch on)</code><br>
<br>
Perlbefehle werden in geschweifte Klammern gesetzt: <code>... {system ("wmail Peter is at home")}</code>. In diesem Fall können die runden Klammern des Ausführungsteils weggelassen werden.<br>
<br>
Perlcode kann im DEF-Editor wie gewohnt programmiert werden: <code>...{my $name="Peter"; system ("wmail $name is at home");}</code><br>
<br>
FHEM-Befehle lassen sich mit Perl-Befehlen kombinieren: <code>... ({system ("wmail Peter is at home")}, set lamp on)</code><br>
<br>
<a name="DOIF_aggregation"></a><br>
<b>Aggregieren von Werten</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit Hilfe der Aggregationsfunktion können mehrere gleichnamige Readings im System ausgewertet werden, die einem bestimmten Kriterium entsprechen. Sie wird in eckigen Klammern durch ein # (aggregierter Wert) oder @ (Liste der passeden Devices) eingeleitet.
Es kann bestimmt werden: die Anzahl der Readings bzw. Devices, Durchschnittswert, Summe, höchster Wert, niedrigster Wert oder eine Liste der dazugehörigen Devices.
Die Aggregationsfunktion kann in einer DOIF-Bedingungen, im Ausführungsteil oder mit Hilfe des state-Attributs im Status angegeben werden. In der Bedingung und im Status reagiert sie auf Ereignistrigger. Das lässt sich durch ein vorangestelltes Fragezeichen unterbinden.
Die Angabe des Readings kann weggelassen werden, dann wird lediglich nach entsprechenden Devices gesucht.<br>
<br>
Syntax:<br>
<br>
<code>[&lt;function&gt;:&lt;format&gt;:"&lt;regex device&gt;:&lt;regex event&gt;":&lt;reading&gt;|"&lt;regex reading&gt;":&lt;condition&gt;,&lt;default&gt;]</code><br>
<br>
&lt;function&gt;:<br>
<br>
<b>#</b>  Anzahl der betroffenen Devices, der folgende Doppelpunkt kann weggelassen werden<br>
<b>@</b>  kommagetrennte Liste Devices, der folgende Doppelpunkt kann weggelassen werden<br>
<b>#sum</b> Summe <br>
<b>#max</b>  höchster Wert<br>
<b>#min</b>  niedrigster Wert<br>
<b>#average</b>  Durchschnitt<br>
<b>@max</b>  Device des höchsten Wertes<br>
<b>@min</b>  Device de niedrigsten Wertes<br>
<br>
&lt;format&gt; <code>d&lt;number&gt</code> zum Runden des Wertes mit Nachkommastellen, <code>a</code> für Aliasnamen bei Devicelisten, <code>s(&lt;splittoken&gt)</code> &lt;splittoken&gt sind Trennzeichen in der Device-Liste<br> 
<br> 
"&lt;regex Device&gt;:&lt;regex Event&gt;" spezifiziert sowohl die betroffenen Devices, als auch den Ereignistrigger, die Syntax entspricht der DOIF-Syntax für Ereignistrigger.<br>
Die Angabe &lt;regex Event&gt; ist im Ausführungsteil nicht sinnvoll und sollte weggelassen werden.<br>
<br>
&lt;reading&gt; Reading, welches überprüft werden soll<br>
<br>
"&lt;regex reading&gt"; Regex für Readings, die überprüft werden sollen<br>
<br>
&lt;condition&gt;  Aggregations-Bedingung, $_ ist der Platzhalter für den aktuellen Wert des internen Schleifendurchlaufs, Angaben in Anführungszeichen der Art "&lt;value&gt;" entsprechen $_ =~ "&lt;value&gt;" , hier sind alle Perloperatoren möglich.<br>
<br>
&lt;default&gt; Default-Wert, falls kein Device gefunden wird, entspricht der Syntax des Default-Wertes bei Readingangaben<br>
<br>
&lt;format&gt;, &lt;reading&gt;, &lt;condition&gt;,  &lt;default&gt; sind optional<br>
<br>
<u>Syntax-Beispiele im Ausführungteil</u><br>
<br>
Anzahl der Devices, die mit "window" beginnen:<br>
<br>
<code>[#"^window"]</code><br>
<br>
Liste der Devices, die mit "window" beginnen, es werden Aliasnamen ausgegeben, falls definiert:<br>
<br>
<code>[@:a"^window"]</code><br>
<br>
Liste der Devices, die mit "windows" beginnen und ein Reading "myreading" beinhalten:<br>
<br>
<code>[@"^window":myreading]</code><br>
<br>
Liste der Devices, die mit "windows" beginnen und im Status das Wort "open" vorkommt:<br>
<br>
<code>[@"^window":state:"open"]</code><br>
<br>
entspricht:<br>
<br>
<code>[@"^window":state:$_ =~ "open"]</code> siehe Aggregationsbedingung.<br>
<br>
Kleinster Wert der Readings des Devices "abfall", in deren Namen "Gruenschnitt" vorkommt und die mit "_days" enden:<br>
<br>
<code>[#min:"^abfall$":"Gruenschnitt.*_days$"]</code><br>
<br>
Durchschnitt von Readings aller Devices, die mit "T_" beginnen, in deren Reading-Namen "temp" vorkommt:<br>
<br>
<code>[#average:"^T_":"temp"]</code><br>
<br>
In der Aggregationsbedingung <condition> können alle in FHEM definierten Perlfunktionen genutzt werden. Folgende Variablen sind vorbelegt und können ebenfalls benutzt werden:<br>
<br>
<b>$_</b> Inhalt des angegebenen Readings (s.o.)<br>
<b>$number</b>  Nach Zahl gefilteres Reading<br>
<b>$name</b>  Name des Devices<br>
<b>$TYPE</b>  Devices-Typ<br>
<b>$STATE</b>  Status des Devices (nicht das Reading state)<br>
<b>$room</b>  Raum des Devices<br>
<b>$group</b>  Gruppe des Devices<br>
<br>
<u>Beispiele für Definition der Aggregationsbedingung &lt;condition&gt;:</u><br>
<br>
Liste der Devices, die mit "rooms" enden und im Reading "temperature" einen Wert größer 20 haben:<br>
<br>
<code>[@"rooms$":temperature:$_ > 20]</code><br>
<br>
Liste der Devices im Raum "livingroom", die mit "rooms" enden und im Reading "temperature" einen Wert größer 20 haben:<br>
<br>
<code>[@"rooms$":temperature:$_ > 20 and $room eq "livingroom"]</code><br>
<br>
Liste der Devices in der Gruppe "windows", die mit "rooms" enden, deren Status (nicht state-Reading) "on" ist:<br>
<br>
<code>[@"rooms$"::$STATE eq "on" and $group eq "windows"]</code><br>
<br>
Liste der Devices, deren state-Reading "on" ist und das Attribut disable nicht auf "1" gesetzt ist:<br>
<br>
<code>[@"":state:$_ eq "on" and AttrVal($name,"disable","") ne "1"]</code><br>
<br>
<br>
Aggregationsangaben in der DOIF-Bedingung reagieren zusätzlich auf Ereignistrigger, hier sollte die regex-Angabe für das Device um eine regex-Angabe für das zu triggernde Event erweitert werden.<br>
<br>
Anzahl der Devices, die mit "window" beginnen. Getriggert wird, wenn eine Eventzeile beginnend mit "window" und dem Wort "open" vorkommt:<br>
<br>
<code>[#"^window:open"]</code><br>
<br>
<u>Anwendungsbeispiele</u><br>
<br>
Statusanzeige: Offene Fenster:<br>
<br>
<code>define di_window DOIF<br>
<br>
attr di_window state Offene Fenster: [@"^window:open":state:"open","keine"]</code><br>
<br>
Statusanzeige: Alle Devices, deren Batterie nicht ok ist:<br>
<br>
<code>define di_battery DOIF<br>
<br>
attr di_battery state [@":battery":battery:$_ ne "ok","alle OK"]</code><br>
<br>
Statusanzeige: Durchschnittstemperatur aller Temperatursensoren in der Gruppe "rooms":<br>
<br>
<code>define di_average_temp DOIF<br>
<br>
attr di_average_temp state [#average:d2:":temperature":temperature:$group eq "rooms"]</code><br>
<br>
Fenster Status/Meldung:<br>
<br>
<code>define di_Fenster DOIF (["^Window:open"]) <br>
(push "Fenster $DEVICE wurde geöffnet. Es sind folgende Fenster offen: [@"^Window":state:"open"]")<br>
DOELSEIF ([#"^Window:closed":state:"open"] == 0)<br>
(push "alle Fenster geschlossen")</code><br>
<br>
attr di_Fenster do always<br>
attr di_Fenster cmdState $DEVICE zuletzt geöffnet|alle geschlossen</code><br>
<br>
Raumtemperatur-Überwachung:<br>
<br>
<code>define di_temp DOIF (([08:00] or [20:00]) and [?#"^Rooms":temperature: $_ < 20] != 0)<br>
  (push "In folgenden Zimmern ist zu kalt [@"^Rooms":temperature:$_ < 20,"keine"]")<br>
DOELSE<br>
  (push "alle Zimmmer sind warm")<br>  
<br>
attr di_temp do always<br>
attr di_Raumtemp state In folgenden Zimmern ist zu kalt: [@"^Rooms":temperature:$_ < 20,"keine"])</code><br>
<br>
Es soll beim Öffnen eines Fensters eine Meldung über alle geöffneten Fenster erfolgen:<br>
<br>
<code>define di_Fenster DOIF (["^Window:open"]) (push "Folgende Fenster: [@"^Window:state:"open"] sind geöffnet")</code><br>
<br>
attr di_Fenster do always<br>
<br>
Wenn im Wohnzimmer eine Lampe ausgeschaltet wird, sollen alle anderen Lampen im Wohnzimmer ebenfalls ausgeschaltet werden, die noch an sind:<br>
<br>
<code>define di_lamp DOIF (["^lamp_livingroom: off"]) (set [@"^lamp_livingroom":state:"on","defaultdummy"] off)<br>
<br>
attr di_lamp DOIF do always</code><br>
<br>
Mit der Angabe des Default-Wertes "defaultdummy", wird verhindert, dass der set-Befehl eine Fehlermeldung liefert, wenn die Device-Liste leer ist. Der angegebene Default-Dummy muss zuvor definiert werden.<br>
<br>
Für reine Perlangaben gibt es eine entsprechende Perlfunktion namens <code>AggrDoIf(&lt;function&gt;,&lt;regex Device&gt;,&lt;reading&gt;,&lt;condition&gt;,&lt;default&gt;)</code> diese liefert bei der Angabe @ ein Array statt einer Stringliste,  dadurch lässt sie sich gut bei foreach-Schleifen verwenden.<br>
<br>
<u>Beispiele</u><br>
<br>
<code>define di_Fenster DOIF (["^Window:open"]) {foreach (AggrDoIf('@','^windows','state','"open"')) {Log3 "di_Fenster",3,"Das Fenster $_ ist noch offen"}}</code><br>
<br>
<code>define di_Temperature DOIF (["^room:temperature"]) {foreach (AggrDoIf('@','^room','temperature','$_ < 15')) {Log3 "di_Temperatur",3,"im Zimmer $_ ist zu kalt"}}</code><br>
<br>
<a name="DOIF_Zeitsteuerung"></a>
<b>Zeitsteuerung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Zeitangaben in der Bedingung im Format: <code>[HH:MM:SS]</code> oder <code>[HH:MM]</code> oder <code>[Zahl]</code><br>
<br>
<u>Anwendungsbeispiele</u>:<br>
<br>
Einschalten um 8:00 Uhr, ausschalten um 10:00 Uhr.<br>
<br>
<code>define di_light DOIF ([08:00]) (set switch on) DOELSEIF ([10:00]) (set switch off)</code><br>
<br>
Zeitsteuerung mit mehreren Zeitschaltpunkten:<br>
<br>
<code>define di_light DOIF ([08:00] or [10:00] or [20:00]) (set switch on) DOELSEIF ([09:00] or [11:00] or [00:00]) (set switch off)</code><br>
<br>
Zeitangaben können ebenfalls in Sekunden angegeben werden. Es handelt sich dann um Sekundenangaben nach Mitternacht, hier also um 01:00 Uhr:<br>
<br>
<code>define di_light DOIF ([3600]) (set lamp on)</code><br>
<br>
<a name="DOIF_Relative_Zeitangaben"></a>
<b>Relative Zeitangaben</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Zeitangaben, die mit Pluszeichen beginnen, werden relativ behandelt, d. h. die angegebene Zeit wird zum aktuellen Zeitpunkt hinzuaddiert.<br>
<br>
<u>Anwendungsbeispiel</u>: Automatisches Speichern der Konfiguration im Stundentakt:<br>
<br>
<code>define di_save DOIF ([+01:00]) (save)<br>
attr di_save do always</code><br>
<br>
Ebenfalls lassen sich relative Angaben in Sekunden angeben. Das obige Beispiel entspricht:<br>
<br>
<code>define di_save DOIF ([+3600]) (save)</code><br>
<br>
<a name="DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet"></a>
<b>Zeitangaben nach Zeitraster ausgerichtet</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Das Format lautet: [:MM] MM sind Minutenangaben zwischen 00 und 59.<br>
<br>
<u>Anwendungsbeispiel</u>: Viertelstunden-Gong<br>
<br>
<code>define di_gong DOIF ([:00])<br>
  <ol>({system ("mplayer /opt/fhem/Sound/BigBen_00.mp3 -volume 90 −really−quiet &")})</ol>
DOELSEIF ([:15])<br>
  <ol>({system ("mplayer /opt/fhem/Sound/BigBen_15.mp3 -volume 90 −really−quiet &")})</ol>
DOELSEIF ([:30])<br>
  <ol>({system ("mplayer /opt/fhem/Sound/BigBen_30.mp3 -volume 90 −really−quiet &")})</ol>
DOELSEIF ([:45])<br>
  <ol>({system ("mplayer /opt/fhem/Sound/BigBen_45.mp3 -volume 90 −really−quiet &")})</ol></code>
<br>
<a name="DOIF_Relative_Zeitangaben_nach_Zeitraster_ausgerichtet"></a>
<b>Relative Zeitangaben nach Zeitraster ausgerichtet</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Das Format lautet: [+:MM] MM sind Minutenangaben zwischen 1 und 59.<br>
<br>
<u>Anwendungsbeispiel</u>: Gong alle fünfzehn Minuten um XX:00 XX:15 XX:30 XX:45<br>
<br>
<code>define di_gong DOIF ([+:15]) (set Gong_mp3 playTone 1)<br>
attr di_gong do always</code><br>
<br>
<a name="DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet_alle_X_Stunden"></a>
<b>Zeitangaben nach Zeitraster ausgerichtet alle X Stunden</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Format: [+[h]:MM] mit: h sind Stundenangaben zwischen 2 und 23 und MM Minuten zwischen 00 und 59<br>
<br>
<u>Anwendungsbeispiel</u>: Es soll immer fünf Minuten nach einer vollen Stunde alle 2 Stunden eine Pumpe eingeschaltet werden, die Schaltzeiten sind 00:05, 02:05, 04:05 usw.<br>
<br>
<code>define di_gong DOIF ([+[2]:05]) (set pump on-for-timer 300)<br>
attr di_gong do always</code><br>
<br>
<a name="DOIF_Wochentagsteuerung"></a>
<b>Wochentagsteuerung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Hinter der Zeitangabe kann ein oder mehrere Wochentage getrennt mit einem Pipezeichen | angegeben werden. Die Syntax lautet:<br>
<br>
<code>[&lt;time&gt;|012345678]</code> 0-8 entspricht: 0-Sonntag, 1-Montag, ... bis 6-Samstag sowie 7 für Wochenende und Feiertage (entspricht $we) und 8 für Arbeitstage (entspricht !$we)<br>
<br>
alternativ mit Buchstaben-Kürzeln:<br>
<br>
<code>[&lt;time&gt;|So Mo Di Mi Do Fr Sa WE AT]</code> WE entspricht der Ziffer 7 und AT der Ziffer 8<br>
<br>
<a name="DOIF_weekdays"></a>
Mit Hilfe des Attributes <code>weekdays</code> können beliebige Wochentagbezeichnungen definiert werden. Die Syntax lautet:<br>
<br>
<code>weekdays &lt;Bezeichnung für Sonntag&gt;,&lt;Bezeichnung für Montag&gt;,...,&lt;Bezeichnung für Wochenende&gt;,&lt;Bezeichnung für Arbeitstage&gt;</code><br>
<br>
Beispiel: <code>di_mydoif attr weekdays Son,Mon,Die,Mit,Don,Fre,Sam,Wochenende,Arbeitstag</code><br>
<br>
<u>Anwendungsbeispiel</u>: Radio soll am Wochenende und an Feiertagen um 08:30 Uhr eingeschaltet und um 09:30 Uhr ausgeschaltet werden. Am Montag und Mittwoch soll das Radio um 06:30 Uhr eingeschaltet und um 07:30 Uhr ausgeschaltet werden. Hier mit englischen Bezeichnern:<br>
<br>
<code>define di_radio DOIF ([06:30|Mo We] or [08:30|WE]) (set radio on) DOELSEIF ([07:30|Mo We] or [09:30|WE]) (set radio off)</code><br>
<br>
<code>attr di_radio weekdays Su,Mo,Tu,We,Th,Fr,Sa,WE,WD</code><br>
<br>
Bemerkung: Es ist unerheblich wie die definierten Wochenttagbezeichner beim Timer angegeben werden. Sie können mit beliebigen Trennzeichen oder ohne Trennzeichen direkt aneinander angegeben werden.<br>
<br>
Anstatt einer direkten Wochentagangabe, kann ein Status oder Reading in eckigen Klammern angegeben werden. Dieser muss zum Triggerzeitpunkt mit der gewünschten Angabe für Wochentage, wie oben definiert, belegt sein.<br>
<br>
<u>Anwendungsbeispiel</u>: Der Wochentag soll über einen Dummy bestimmt werden.<br>
<br>
<code>define dummy myweekday<br>
set myweekday monday wednesday thursday weekend<br>
<br>
define di_radio DOIF ([06:30|[myweekday]]) (set radio on) DOELSEIF ([07:30|[myweekday]]) (set radio off)<br>
<br>
attr di_radio weekdays sunday,monday,thuesday,wednesday,thursday,friday,saturday,weekend,workdays</code><br>
<br>
<a name="DOIF_Zeitsteuerung_mit_Zeitintervallen"></a>
<b>Zeitsteuerung mit Zeitintervallen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Zeitintervalle werden im Format angegeben: <code>[&lt;begin&gt;-&lt;end&gt;]</code>,
für <code>&lt;begin&gt;</code> bzw. <code>&lt;end&gt;</code> wird das gleiche Zeitformat verwendet,
wie bei einzelnen Zeitangaben. Getriggert wird das Modul zum Zeitpunkt <code>&lt;begin&gt;</code> und zum Zeitpunkt <code>&lt;end&gt;</code>.
Soll ein Zeitintervall ohne Zeittrigger lediglich zur Abfrage dienen, so muss hinter der eckigen Klammer ein Fragezeichen angegeben werden (siehe Beispiele weiter unten).
Das Zeitintervall ist als logischer Ausdruck ab dem Zeitpunkt <code>&lt;begin&gt;</code> wahr und ab dem Zeitpunkt <code>&lt;end&gt;</code> nicht mehr wahr.<br>
<br>
<u>Anwendungsbeispiele</u>:<br>
<br>
Radio soll zwischen 8:00 und 10:00 Uhr an sein:<br>
<br>
<code>define di_radio DOIF ([08:00-10:00]) (set radio on) DOELSE (set radio off) </code><br>
<br>
mit mehreren Zeitintervallen:<br>
<br>
<code>define di_radio DOIF ([08:00-10:00] or [20:00-22:00]) (set radio on) DOELSE (set radio off) </code><br>
<br>
Radio soll nur sonntags (0) eingeschaltet werden:<br>
<br>
<code>define di_radio DOIF ([08:00-10:00|0]) (set radio on) DOELSE (set radio off) </code><br>
<br>
Nur montags, mittwochs und freitags:<br>
<br>
<code>define di_radio DOIF ([08:00-10:00|135]) (set radio on) DOELSE (set radio off) </code><br>
<br>
Nur am Wochenende bzw. an Feiertagen lt. holiday-Datei (7 entspricht $we):<br>
<br>
<code>define di_radio DOIF ([08:00-10:00|7]) (set radio on) DOELSE (set radio off) </code><br>
<br>
Zeitintervalle über Mitternacht:<br>
<br>
<code>define di_light DOIF ([22:00-07:00]) (set light on) DOELSE (set light off) </code><br>
<br>
in Verbindung mit Wochentagen (einschalten am Freitag ausschalten am Folgetag):<br>
<br>
<code>define di_light DOIF ([22:00-07:00|5]) (set light on) DOELSE (set light off) </code><br>
<br>
Zeitintervalle über mehrere Tage müssen als Zeitpunkte angegeben werden.<br>
<br>
Einschalten am Freitag ausschalten am Montag:<br>
<br>
<code>define di_light DOIF ([22:00|5]) (set light on) DOELSEIF ([10:00|1]) (set light off) </code><br>
<br>
Schalten mit Zeitfunktionen, hier: bei Sonnenaufgang und Sonnenuntergang:<br>
<br>
<code>define di_light DOIF ([+{sunrise_rel(900,"06:00","08:00")}]) (set outdoorlight off) DOELSEIF ([+{sunset_rel(900,"17:00","21:00")}]) (set outdoorlight on)</code><br>
<br>
<a name="DOIF_Indirekten_Zeitangaben"></a>
<b>Indirekten Zeitangaben</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Oft möchte man keine festen Zeiten im Modul angeben, sondern Zeiten, die man z. B. über Dummys über die Weboberfläche verändern kann.
Statt fester Zeitangaben können Status, Readings oder Internals angegeben werden. Diese müssen eine Zeitangabe im Format HH:MM oder HH:MM:SS oder eine Zahl beinhalten.<br>
<br>
<u>Anwendungsbeispiel</u>: Lampe soll zu einer bestimmten Zeit eingeschaltet werden. Die Zeit soll über den Dummy <code>time</code> einstellbar sein:<br>
<br>
<code>define time dummy<br>
set time 08:00<br>
define di_time DOIF ([[time]])(set lamp on)<br>
attr di_time do always</code><br>
<br>
Die indirekte Angabe kann ebenfalls mit einer Zeitfunktion belegt werden. Z. B. <br>
<br>
<code>set time {sunset()}</code><br>
<br>
Das Dummy kann auch mit einer Sekundenzahl belegt werden, oder als relative Zeit angegeben werden, hier z. B. schalten alle 300 Sekunden:<br>
<br>
<code>define time dummy<br>
set time 300<br>
define di_time DOIF ([+[time]])(save)</code><br>
<br>
Ebenfalls funktionieren indirekte Zeitangaben mit Zeitintervallen. Hier wird die Ein- und Ausschaltzeit jeweils über einen Dummy bestimmt:<br>
<br>
<code>define begin dummy<br>
set begin 08:00<br>
<br>
define end dummy<br>
set end 10:00<br>
<br>
define di_time DOIF ([[begin]-[end]]) (set radio on) DOELSE (set radio off)</code><br>
<br>
Indirekte Zeitangaben können auch als Übergabeparameter für Zeitfunktionen, wie z. B. sunset oder sunrise übergeben werden:<br>
<br>
<code>define di_time DOIF ([{sunrise(0,"[begin]","09:00")}-{sunset(0,"18:00","[end]")}]) (set lamp off) DOELSE (set lamp on) </code><br>
<br>
Bei einer Änderung des angegebenen Status oder Readings wird die geänderte Zeit sofort im Modul aktualisiert.<br>
<br>
Angabe eines Readings als Zeitangabe. Beispiel: Schalten anhand eines Twilight-Readings:<br>
<br>
<code>define di_time DOIF ([[myTwilight:ss_weather]])(set lamp on)</code><br>
<br>


Dynamische Änderung einer Zeitangabe.<br>
<br>
<u>Anwendungsbeispiel</u>: Die Endzeit soll abhängig von der Beginnzeit mit Hilfe einer eigenen Perl-Funktion, hier: <code>OffTime()</code>, bestimmt werden. <code>begin</code> und <code>end</code> sind Dummys, wie oben definiert:<br>
<br>
<code>define di_time DOIF ([[begin]-[end]]) (set lamp on, set end {(OffTime("[begin]"))}) DOELSE (set lamp off)</code><br>
<br>
Indirekte Zeitangaben lassen sich mit Wochentagangaben kombinieren, z. B.:<br>
<br>
<code>define di_time DOIF ([[begin]-[end]|7]) (set radio on) DOELSE (set radio off)</code><br>
<br>
<a name="DOIF_Zeitsteuerung_mit_Zeitberechnung"></a>
<b>Zeitsteuerung mit Zeitberechnung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Zeitberechnungen werden innerhalb der eckigen Klammern zusätzlich in runde Klammern gesetzt. Die berechneten Triggerzeiten können absolut oder relativ mit einem Pluszeichen vor den runden Klammern angegeben werden.
Es können beliebige Ausdrücke der Form HH:MM und Angaben in Sekunden als ganze Zahl in Perl-Rechenoperationen kombiniert werden.
Perlfunktionen, wie z. B. sunset(), die eine Zeitangabe in HH:MM liefern, werden in geschweifte Klammern gesetzt.
Zeiten im Format HH:MM bzw. Status oder Readings, die Zeitangaben in dieser Form beinhalten werden in eckige Klammern gesetzt.<br>
<br>
<u>Anwendungsbeispiele</u>:<br>
<br>
Lampe wird nach Sonnenuntergang zwischen 900 und 1500 (900+600) Sekunden zufällig zeitverzögert eingeschaltet. Ausgeschaltet wird die Lampe nach 23:00 Uhr um bis zu 600 Sekunden zufällig verzögert:<br>
<br>
<code>define di_light DOIF ([({sunset()}+900+int(rand(600)))])<br>
   <ol>(set lamp on)</ol>
DOELSEIF ([([23:00]+int(rand(600)))])<br>
   <ol>(set lamp off) </ol></code>
<br>
Zeitberechnung können ebenfalls in Zeitintervallen genutzt werden.<br>
<br>
Licht soll eine Stunde vor gegebener Zeit eingeschaltet werden und eine Stunde danach wieder ausgehen:<br>
<br>
<code>define Fixtime dummy<br>
set Fixtime 20:00<br>
<br>
define di_light DOIF ([([Fixtime]-[01:00]) - ([Fixtime]+[01:00])])<br>
 <ol>(set lampe on)</ol>
DOELSE<br>
 <ol>(set lampe off)</ol>
 </code>
<br>
Hier das Gleiche wie oben, zusätzlich mit Zufallsverzögerung von 300 Sekunden und nur an Wochenenden:<br>
<br>
<code>define di_light DOIF ([([Fixtime]-[01:00]-int(rand(300))) - ([Fixtime]+[01:00]+int(rand(300)))]|7])<br>
 <ol>(set lampe on)</ol>
DOELSE<br>
 <ol>(set lampe off)</ol>
 </code>
<br>
Ein Änderung des Dummys Fixtime z. B. durch "set Fixtime ...", führt zur sofortiger Neuberechnung der Timer im DOIF-Modul.<br>
<br>
Für die Zeitberechnung wird der Perlinterpreter benutzt, daher sind für die Berechnung der Zeit keine Grenzen gesetzt.<br>
<br>
<a name="DOIF_Kombination_von_Ereignis_und_Zeitsteuerung_mit_logischen_Abfragen"></a>
<b>Kombination von Ereignis- und Zeitsteuerung mit logischen Abfragen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<u>Anwendungsbeispiel</u>: Lampe soll ab 6:00 Uhr angehen, wenn es dunkel ist und wieder ausgehen, wenn es hell wird, spätestens aber um 9:00 Uhr:<br>
<br>
<code>define di_lamp DOIF ([06:00-09:00] and [sensor:brightness] &lt; 40) (set lamp on) DOELSE (set lamp off)</code><br>
<br>
<u>Anwendungsbeispiel</u>: Rollläden sollen an Arbeitstagen nach 6:25 Uhr hochfahren, wenn es hell wird, am Wochenende erst um 9:00 Uhr, herunter sollen sie wieder, wenn es dunkel wird:<br>
<br>
<code>define di_shutters DOIF ([sensor:brightness]&gt;100 and [06:25-09:00|8] or [09:00|7]) (set shutters up) DOELSEIF ([sensor:brightness]&lt;50) (set shutters down)</code><br>
<br>
<a name="DOIF_Zeitintervalle_Readings_und_Status_ohne_Trigger"></a>
<b>Zeitintervalle, Readings und Status ohne Trigger</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Angaben in eckigen Klammern, die mit einem Fragezeichen beginnen, führen zu keiner Triggerung des Moduls, sie dienen lediglich der Abfrage.<br>
<br>
<u>Anwendungsbeispiel</u>: Licht soll zwischen 06:00 und 10:00 angehen, getriggert wird nur durch den Taster nicht um 06:00 bzw. 10:00 Uhr und nicht durch das Device Home<br>
<br>
<code>define di_motion DOIF ([?06:00-10:00] and [button] and [?Home] eq "present")(set lamp on-for-timer 600)<br>
attr di_motion do always</code><br>
<br>
<a name="DOIF_Nutzung_von_Readings_Status_oder_Internals_im_Ausfuehrungsteil"></a>
<b>Nutzung von Readings, Status oder Internals im Ausführungsteil</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<u>Anwendungsbeispiel</u>: Wenn ein Taster betätigt wird, soll Lampe1 mit dem aktuellen Zustand der Lampe2 geschaltet werden:<br>
<br>
<code>define di_button DOIF ([button]) (set lamp1 [lamp2])<br>
attr di_button do always</code><br>
<br>
<u>Anwendungsbeispiel</u>: Benachrichtigung beim Auslösen eines Alarms durch Öffnen eines Fensters:<br>
<br>
<code>define di_pushmsg DOIF ([window] eq "open" and [alarm] eq "armed") (set Pushover msg 'alarm' 'open windows [window:LastDevice]' '' 2 'persistent' 30 3600)</code><br>
<br>
<a name="DOIF_Berechnungen_im_Ausfuehrungsteil"></a>
<b>Berechnungen im Ausführungsteil</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Berechnungen können in geschweiften Klammern erfolgen. Aus Kompatibilitätsgründen, muss die Berechnung unmittelbar mit einer runden Klammer beginnen.
Innerhalb der Perlberechnung können Readings, Status oder Internals wie gewohnt in eckigen Klammern angegeben werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Es soll ein Vorgabewert aus zwei verschiedenen Readings ermittelt werden und an das set Kommando übergeben werden:<br>
<br>
<code>define di_average DOIF ([08:00]) (set TH_Modul desired {([default:temperature]+[outdoor:temperature])/2})<br>
attr di_average do always</code><br>
<br>
<a name="DOIF_notexist"></a>
<b>Ersatzwert für nicht existierende Readings oder Status</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Es kommt immer wieder vor, dass in der Definition des DOIF-Moduls angegebene Readings oder Status zur Laufzeit nicht existieren. Der Wert ist dann leer.
Bei der Definition von Status oder Readings kann für diesen Fall ein Vorgabewert oder sogar eine Perlberechnung am Ende des Ausdrucks kommagetrennt angegeben werden.<br>
<br>
Syntax:<br>
<br>
<code>[&lt;device&gt,&lt;default value&gt;]</code><br>
oder <br>
<code>[&lt;device&gt:&lt;reading&gt,&lt;default value&gt;]</code><br>
<br>
Beispiele:<br>
<br>
<code>
[lamp,"off"]<br>
[room:temperatur,20]<br>
[brightness,3*[myvalue]+2]<br>
[heating,AttrVal("mydevice","myattr","")]<br>
[[mytime,"10:00"]]<br>
</code><br>
Möchte man stattdessen einen bestimmten Wert global für das gesamte Modul definieren,
so lässt sich das über das Attribut <code>notexist</code> bewerkstelligen. Ein angegebener Default-Wert beim Status oder beim Reading übersteuert das "notexist"-Attribut.<br>
<br>
Syntax: <code>attr &lt;DOIF-module&gt; notexist "&lt;default value&gt;"</code> <br>
<br>
<a name="DOIF_wait"></a>
<b>Verzögerungen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Verzögerungen für die Ausführung von Kommandos werden pro Befehlsfolge über das Attribut "wait" definiert. Syntax:<br>
<br>
<code>attr &lt;DOIF-module&gt; wait &lt;Sekunden für Befehlsfolge des ersten DO-Falls&gt;:&lt;Sekunden für Befehlsfolge des zweiten DO-Falls&gt;:...<br></code>
<br>

Sollen Verzögerungen innerhalb von Befehlsfolgen stattfinden, so müssen diese Kommandos in eigene Klammern gesetzt werden, das Modul arbeitet dann mit Zwischenzuständen.<br>
<br>
Beispiel: Bei einer Befehlssequenz, hier: <code>(set lamp1 on, set lamp2 on)</code>, soll vor dem Schalten von <code>lamp2</code> eine Verzögerung von einer Sekunde stattfinden.
Die Befehlsfolge muss zunächst mit Hilfe von Klammerblöcke in eine Befehlssequenz aufgespalten werden: <code>(set lamp1 on)(set lamp2 on)</code>.
Nun kann mit dem wait-Attribut nicht nur für den Beginn der Sequenz, sondern für jeden Klammerblock eine Verzögerung, getrennt mit Komma, definieren werden,
 hier also: <code>wait 0,1</code>. Damit wird <code>lamp1</code> sofort, <code>lamp2</code> eine Sekunde danach geschaltet. Die Verzögerungszeit bezieht sich immer auf den vorherigen Befehl.<br>
<br>
Beispieldefinition bei mehreren DO-Blöcken mit Befehlssequenzen:<br>
<br>
<code>DOIF (Bedingung1)<br>
(set ...) ## erster Befehl der ersten Sequenz soll um eine Sekunde verzögert werden<br>
(set ...) ## zweiter Befehl der ersten Sequenz soll um 2 Sekunden nach dem ersten Befehl verzögert werden<br>
DOELSEIF (Bedingung2)<br>
(set ...) ## erster Befehl der zweiten Sequenz soll um 3 Sekunden verzögert werden<br>
(set ...) ## zweiter Befehl der zweiten Sequenz soll um 0,5 Sekunden nach dem ersten Befehl verzögert werden<br>
<br>
attr &lt;DOIF-module&gt; wait 1,2:3,0.5</code><br>
<br>
Das Aufspalten einer kommagetrennten Befehlskette in eine Befehlssequenz, wie im obigen Beispiel, sollte nicht vorgenommen werden, wenn keine Verzögerungen zwischen den Befehlen benötigt werden.
Denn bei einer Befehlssequenz werden Zwischenzustände cmd1_1, cmd1_2 usw. generiert, die Events erzeugen und damit unnötig FHEM-Zeit kosten.<br>
<br>
Für Kommandos, die nicht verzögert werden sollen, werden Sekundenangaben ausgelassen oder auf Null gesetzt. Die Verzögerungen werden nur auf Events angewandt und nicht auf Zeitsteuerung. Eine bereits ausgelöste Verzögerung wird zurückgesetzt, wenn während der Wartezeit ein Kommando eines anderen DO-Falls, ausgelöst durch ein neues Ereignis, ausgeführt werden soll.<br>
<br>
Statt Sekundenangaben können ebenfalls Status, Readings in eckigen Klammern, Perl-Funktionen sowie Perl-Berechnung angegeben werden. Dabei werden die Trennzeichen Komma und Doppelpunkt in Klammern geschützt und gelten dort nicht als Trennzeichen.
Diese Angaben können ebenfalls bei folgenden Attributen gemacht werden: cmdpause, repeatcmd, repeatsame, waitsame, waitdel<br>
<br>
Beispiel:<br>
<br>
<code>attr my_doif wait 1:[mydummy:state]*3:rand(600)+100,Attr("mydevice","myattr","")</code><br>
<br>
<a name="DOIF_timerWithWait"></a>
<br>
<b>Verzögerungen von Timern</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Verzögerungen können mit Hilfe des Attributs <code>timerWithWait</code> auf Timer ausgeweitet werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Lampe soll zufällig nach Sonnenuntergang verzögert werden.<br>
<br>
<code>define di_rand_sunset DOIF ([{sunset()}])(set lamp on)<br>
attr di_rand_sunset wait rand(1200)<br>
attr di_rand_sunset timerWithWait 1<br>
attr di_rand_sunset do always</code><br>
<br>
<u>Anwendungsbeispiel</u>: Benachrichtigung "Waschmaschine fertig", wenn Verbrauch mindestens 5 Minuten unter 2 Watt (Perl-Code wird in geschweifte Klammern gesetzt):<br>
<br>
<code>define di_washer DOIF ([power:watt]&lt;2) ({system("wmail washer finished")})<br>
attr di_washer wait 300</code><br>
<br>
Eine erneute Benachrichtigung wird erst wieder ausgelöst, wenn zwischendurch der Verbrauch über 2 Watt angestiegen war.<br>
<br>
<u>Anwendungsbeispiel</u>: Rollladen um 20 Minuten zeitverzögert bei Sonne runter- bzw. hochfahren (wenn der Zustand der Sonne wechselt, wird die Verzögerungszeit zurückgesetzt):<br>
<br>
<code>define di_shutters DOIF ([Sun] eq "on") (set shutters down) DOELSE (set shutters up) <br>
attr di_shutters wait 1200:1200</code><br>
<br>
<u>Anwendungsbeispiel</u>: Beschattungssteuerung abhängig von der Temperatur. Der Rollladen soll runter von 11:00 Uhr bis Sonnenuntergang, wenn die Temperatur über 26 Grad ist. Temperaturschwankungen um 26 Grad werden mit Hilfe des wait-Attributes durch eine 15 minutige Verzögerung ausgeglichen. <br>
<br>
<code>define di_shutters DOIF ([sensor:temperature] &gt; 26 and [11:00-{sunset_abs()}] (set shutters down) DOELSE (set shutters up)<br>
attr di_shutters wait 900:900 </code><br>
<br>
<u>Anwendungsbeispiel</u>: Belüftung in Kombination mit einem Lichtschalter mit Nachlaufsteuerung. Der Lüfter soll angehen, wenn das Licht mindestens 2 Minuten lang brennt oder die Luftfeuchtigkeit 65 % überschreitet, der Lüfter soll ausgehen, drei Minuten nachdem die Luftfeuchtigkeit unter 60 % fällt und das Licht aus ist bzw. das Licht ausgeht und die Luftfeuchtigkeit unter 60% ist. Definitionen lassen sich über die Weboberfläche (DEF-Eingabebereich) übersichtlich gestalten:<br>
<br>
<code>define di_fan DOIF ([light] eq "on")<br>
   <ol>
  (set fan on)<br>
  </ol>
DOELSEIF ([sensor:humidity]&gt;65)<br>
  <ol>
  (set fan on)<br>
  </ol>
DOELSEIF ([light] eq "off" and [sensor:humidity]&lt;60)<br>  <ol>
  (set fan off)<br>
  </ol>
<br>
attr di_fan wait 120:0:180</code><br>
<br>
<a name="DOIF_do_resetwait"></a>
<b>Zurücksetzen des Waittimers für das gleiche Kommando</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Im Gegensatz zu <code>do always</code> wird ein Waittimer mit dem Attribut <code>do resetwait</code> auch dann zurückgesetzt, wenn die gleiche Bedingung wiederholt wahr wird.<br>
Damit können Ereignisse ausgelöst werden, wenn etwas innerhalb einer Zeitspanne nicht passiert.<br>
Das Attribut <code>do resetwait</code> impliziert eine beliebige Wiederholung wie <code>do always</code>. Diese lässt sich allerdings mit dem Attribut <code>repeatsame</code> einschränken s. u.<br>
<br>
<u>Anwendungsbeispiel</u>: Meldung beim Ausbleiben eines Events<br>
<br>
<code>define di_push DOIF ([Tempsensor])(set pushmsg "sensor failed again")<br>
attr di_push wait 1800<br>
attr di_push do resetwait</code><br>
<br>
<a name="DOIF_repeatcmd"></a>
<b>Wiederholung von Befehlsausführung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Wiederholungen der Ausführung von Kommandos werden pro Befehlsfolge über das Attribut "repeatcmd" definiert. Syntax:<br>
<br>
<code>attr &lt;DOIF-modul&gt; repeatcmd &lt;Sekunden für Befehlsfolge des ersten DO-Falls&gt;:&lt;Sekunden für Befehlsfolge des zweiten DO-Falls&gt;:...<br></code>
<br>
Statt Sekundenangaben können ebenfalls Status in eckigen Klammen oder Perlbefehle angegeben werden.<br>
<br>
Die Wiederholung findet so lange statt, bis der Zustand des Moduls in einen anderen DO-Fall wechselt.<br>
<br>
<u>Anwendungsbeispiel</u>: Nach dem Eintreffen des Ereignisses wird die push-Meldung stündlich wiederholt, bis Frost ungleich "on" ist.<br>
<br>
<code>define di_push DOIF ([frost] eq "on")(set pushmsg "danger of frost")<br>
attr di_push repeatcmd 3600</code><br>
<br>
Eine Begrenzung der Wiederholungen kann mit dem Attribut repeatsame vorgenommen werden<br>
<code>attr di_push repeatsame 3</code><br>
<br>
Ebenso lässt sich das repeatcmd-Attribut mit Zeitangaben kombinieren.<br>
<br>
<u>Anwendungsbeispiel</u>: Wiederholung ab einem Zeitpunkt<br>
<br>
<code>define di_alarm_clock DOIF ([08:00])(set alarm_clock on)<br>
attr di_alarm_clock repeatcmd 300<br>
attr di_alarm_clock repeatsame 3<br>
attr di_alarm_clock do always</code><br>
<br>
Ab 8:00 Uhr wird 3 mal der Weckton jeweils nach 5 Minuten wiederholt.<br>
<br>
<u>Anwendungsbeispiel</u>: Warmwasserzirkulation<br>
<br>
<code>define di_pump_circ DOIF ([05:00-22:00])(set pump on)(set pump off) DOELSE (set pump off)<br>
attr di_pump_circ wait 0,300<br>
attr di_pump_circ repeatcmd 3600</code><br>
<br>
Zwischen 5:00 und 22:00 Uhr läuft die Zirkulationspumpe alle 60 Minuten jeweils 5 Minuten lang.<br>
<br>
<u>Anwendungsbeispiel</u>: Anwesenheitssimulation<br>
<br>
<code>define di_presence_simulation DOIF ([19:00-00:00])(set lamp on-for-timer {(int(rand(1800)+300))}) DOELSE (set lamp off)<br>
attr di_presence_simulation repeatcmd rand(3600)+2200</code><br>
<br>
<br>
<a name="DOIF_cmdpause"></a>
<b>Zwangspause für das Ausführen eines Kommandos seit der letzten Zustandsänderung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit dem Attribut <code>cmdpause &lt;Sekunden für cmd_1&gt;:&lt;Sekunden für cmd_2&gt;:...</code> wird die Zeitspanne in Sekunden angegeben für eine Zwangspause seit der letzten Zustandsänderung.
In der angegebenen Zeitspanne wird ein Kommando nicht ausgeführt, auch wenn die dazugehörige Bedingung wahr wird.<br>
<br>
<u>Anwendungsbeispiel</u>: Meldung über Frostgefahr alle 60 Minuten<br>
<br>
<code>define di_frost DOIF ([outdoor:temperature] < 0) (set pushmsg "danger of frost")<br>
attr di_frost cmdpause 3600<br>
attr di_frost do always</code><br>
<br>
<a name="DOIF_repeatsame"></a>
<b>Begrenzung von Wiederholungen eines Kommandos</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit dem Attribut <code>repeatsame &lt;maximale Anzahl von cmd_1&gt;:&lt;maximale Anzahl von cmd_2&gt;:...</code> wird die maximale Anzahl hintereinander folgenden Ausführungen festgelegt.<br>
<br>
<u>Anwendungsbeispiel</u>: Die Meldung soll maximal dreimal erfolgen mit einer Pause von mindestens 10 Minuten <br>
<br>
<code>define di_washer DOIF ([Watt]<2) (set pushmeldung "washer finished")<br>
attr di_washer repeatsame 3<br>
attr di_washer cmdpause 600 </code><br>
<br>
Das Attribut <code>repeatsame</code> lässt sich mit <code>do always</code> oder <code>do resetwait</code> kombinieren.
Wenn die maximale Anzahl für ein Kommando ausgelassen oder auf Null gesetzt wird, so gilt für dieses Kommando der Defaultwert "einmalige Wiederholung";
in Kombination mit <code>do always</code> bzw. <code>do resetwait</code> gilt für dieses Kommando "beliebige Wiederholung".<br>
<br>
<u>Anwendungsbeispiel</u>: cmd_1 soll beliebig oft wiederholt werden, cmd_2 maximal zweimal<br>
<br>
<code>attr di_repeat repeatsame 0:2<br>
attr di_repeat do always</code><br>
<br>
<a name="DOIF_waitsame"></a>
<b>Ausführung eines Kommandos nach einer Wiederholung einer Bedingung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit dem Attribut <code>waitsame &lt;Zeitspanne in Sekunden für cmd_1&gt;:&lt;Zeitspanne in Sekunden für das cmd_2&gt;:...</code> wird ein Kommando erst dann ausgeführt, wenn innerhalb einer definierten Zeitspanne die entsprechende Bedingung zweimal hintereinander wahr wird.<br>
Für Kommandos, für die <code>waitsame</code> nicht gelten soll, werden die entsprechenden Sekundenangaben ausgelassen oder auf Null gesetzt.<br>
<br>
<u>Anwendungsbeispiel</u>: Rollladen soll hoch, wenn innerhalb einer Zeitspanne von 2 Sekunden ein Taster betätigt wird<br>
<br>
<code>define di_shuttersup DOIF ([Button])(set shutters up)<br>
attr di_shuttersup waitsame 2<br>
attr di_shuttersup do always</code><br>
<br>
<a name="DOIF_waitdel"></a>
<b>Löschen des Waittimers nach einer Wiederholung einer Bedingung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Das Gegenstück zum <code>repeatsame</code>-Attribut ist das Attribut <code>waitdel</code>. Die Syntax mit Sekundenangaben pro Kommando entspricht der, des wait-Attributs. Im Gegensatz zum wait-Attribut, wird ein laufender Timer gelöscht, falls eine Bedingung wiederholt wahr wird.
Sekundenangaben können pro Kommando ausgelassen oder auf Null gesetzt werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Rollladen soll herunter, wenn ein Taster innerhalb von zwei Sekunden nicht wiederholt wird<br>
<br>
<code>define di_shuttersdown DOIF ([Button])(set shutters down)<br>
attr di_shuttersdown waitdel 2<br>
attr di_shuttersdown do always</code><br>
<br>
"di_shuttersdown" kann nicht mit dem vorherigen Anwendungsbeispiel "di_shuttersup" innerhalb eines DOIF-Moduls kombiniert werden, da in beiden Fällen die gleiche Bedingung vorkommt.<br>
<a href="#DOIF_Einknopf_Fernbedienung">siehe auch Einknopf-Fernbedienung im Perl-Modus</a><br>
<br>
Die Attribute <code>wait</code> und <code>waitdel</code> lassen sich für verschiedene Kommandos kombinieren. Falls das Attribut für ein Kommando nicht gesetzt werden soll, kann die entsprechende Sekundenzahl ausgelassen oder eine Null angegeben werden.<br>
<br>
<u>Beispiel</u>: Für cmd_1 soll <code>wait</code> gelten, für cmd_2 <code>waitdel</code><br>
<br>
<code>attr di_cmd wait 2:0<br>
attr di_cmd waitdel 0:2</code><br>
<a name="DOIF_checkReadingEvent"></a>
<br>
<b>Readingauswertung nur beim Event des jeweiligen Readings</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Standardmäßig werden angegebene Readings ausgewertet, wenn irgendein Event des angegebenen Devices triggert.
Möchte man gezielt nur dann ein angegebenes Reading auswerten, wenn sich nur dieses ändert, so lässt sich das mit dem Attribut <code>checkReadingEvent</code> einschränken.
Das ist insb. dann interessant, wenn ein Modul verschiedene Readings zu unterschiedlichen Zeitpunkten aktualisiert.<br>
<br>
<u>Beispiel</u>:<br>
<br>
<code>define di_lamp DOIF ([mytwilight:light] < 3) (set lamp on) DOELSEIF ([mytwilight:light] > 3) (set lamp off)<br>
attr di_lamp checkReadingEvent 1</code><br>
<br>
Bei der Angabe von indirekten Timern wird grundsätzlich intern <code>checkReadingEvent</code> benutzt:<br>
<br>
<code>define di_lamp ([[mytwilight:ss_weather]]) (set lamp on)<br>
attr di_lamp do always</code><br>
<br>
Hier braucht das Attribut <code>checkReadingEvent</code> nicht explizit gesetzt werden.
Die Zeit wird nur dann neu gesetzt, wenn sich tatsächlich das Reading ss_weather ändert.<br>
<br>
<a name="DOIF_addStateEvent"></a>
<b>Eindeutige Statuserkennung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Bei Änderungen des Readings state wird in FHEM standardmäßig, im Gegensatz zu allen anderen Readings, der Readingname hier: "state: " im Event nicht vorangestellt.
Möchte man eindeutig eine Statusänderung eines Moduls erkennen, so lässt sich das mit dem Attribut <code>addStateEvent</code> bewerksteligen.
Bei Statusänderungen eines Devices wird bei der Angabe des Attributes <code>addStateEvent</code> im Event "state: " vorangestellt, darauf kann man dann gezielt im DOIF-Modul triggern.<br>
<br>
<u>Beispiel</u>:<br>
<br>
<code>define di_lamp ([FB:"^state: on$"]) (set lamp on)<br>
attr di_lamp do always<br>
attr di_lamp addStateEvent</code><br>
<br>
<a name="DOIF_selftrigger"></a>
<b>Triggerung durch selbst ausgelöste Events</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Standardmäßig unterbindet das DOIF-Modul Selbsttriggerung. D. h. das Modul reagiert nicht auf Events, die es selbst direkt oder indirekt auslöst. Dadurch werden Endlosschleifen verhindert.
Wenn das Attribut <code>selftrigger wait</code> gesetzt ist, kann das DOIF-Modul auf selbst ausgelöste Events reagieren. Dazu müssen die entsprchenden Kommandos mit wait verzögert werden.
Bei der Angabe  <code>selftrigger all</code> reagiert das Modul grundsätzlich alle selbst ausgelösten Trigger.<br>
<br>
Zu beachten ist, dass der Zustand des Moduls erst nach der Ausführung des Befehls gesetzt wird, dadurch wird die Zustandsverwaltung (ohne do always) ausgehebelt.
Die Auswertung des eigenen Zustands z. B. über [$SELF:cmd] funktioniert dagegen korrekt, weil dieser immer bei der eigenen Triggerung bereits gesetzt ist.
Bei der Verwendung des Attributes <code>selftrigger all</code> sollte beachtet werden, dass bereits in der zweiten Rekursion,
 wenn ein Befehl nicht durch wait verzögert wird, FHEM eine weitere Triggerung unterbindet, um Endlosschleifen zu verhindern.<br>
<br>
<a name="DOIF_timerevent"></a>
<b>Setzen der Timer mit Event</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Wenn das Attribut <code>timerevent</code> ungleich Null gesetzt ist, wird beim Setzen der Timer im DOIF-Modul ein Event erzeugt. Das kann z. B. bei FHEM2FHEM nützlich sein, um die Timer-Readings zeitnah zu aktualisieren.<br>
<br>
<a name="DOIF_Zeitspanne_eines_Readings_seit_der_letzten_Aenderung"></a>
<b>Zeitspanne eines Readings seit der letzten Änderung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Bei Readingangaben kann die Zeitspanne mit <code>[&lt;Device&gt;:&lt;Reading&gt;:sec]</code> in Sekunden seit der letzten Änderung bestimmt werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Licht soll angehen, wenn der Status des Bewegungsmelders in den letzten fünf Sekunden upgedatet wurde.<br>
<br>
<code>define di_lamp DOIF ([BM:state:sec] < 5) (set lamp on-for-timer 300)<br>
attr di_lamp do always</code><br>
<br>
Bei HM-Bewegungsmelder werden periodisch Readings aktualisiert, dadurch wird das Modul getrigger, auch wenn keine Bewegung stattgefunden hat.
Der Status bleibt dabei auf "motion". Mit der obigen Abfrage lässt sich feststellen, ob der Status aufgrund einer Bewegung tatsächlich upgedatet wurde.<br>
<br>
<a name="DOIF_checkall"></a>
<b>Alle Bedingungen prüfen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Bei der Abarbeitung der Bedingungen, werden nur die Bedingungen überprüft,
die zum ausgelösten Event das dazughörige Device bzw. die dazugehörige Triggerzeit beinhalten. Mit dem Attribut <b>checkall</b> lässt sich das Verhalten so verändern,
dass bei einem Event-Trigger auch Bedingungen geprüft werden, die das triggernde Device nicht beinhalten.
Folgende Parameter können angegeben werden:<br>
<br>
<code>checkall event</code> Es werden alle Bedingungen geprüft, wenn ein Event-Trigger auslöst.<br>
<code>checkall timer</code> Es werden alle Bedingungen geprüft, wenn ein Timer-Trigger auslöst.<br>
<code>checkall all&nbsp;&nbsp;</code> Es werden grundsätzlich alle Bedingungen geprüft.<br>
<br>
Zu beachten ist, dass bei einer wahren Bedingung die dazugehörigen Befehle ausgeführt werden und die Abarbeitung immer beendet wird -
 es wird also grundsätzlich immer nur ein Befehlszweig ausgeführt und niemals mehrere.<br>
<br>
<a name="DOIF_setList__readingList"></a>
<b>Darstellungselement mit Eingabemöglichkeit im Frontend und Schaltfunktion</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Die unter <a href="#dummy">Dummy</a> beschriebenen Attribute <a href="#readingList">readingList</a> und <a href="#setList">setList</a> stehen auch im DOIF zur Verf&uuml;gung. Damit wird erreicht, dass DOIF im WEB-Frontend als Eingabeelement mit Schaltfunktion dienen kann. Zus&auml;tzliche Dummys sind nicht mehr erforderlich. Es k&ouml;nnen im Attribut <a href="#setList">setList</a>, die in <a href="#FHEMWEB">FHEMWEB</a> angegebenen Modifier des Attributs <a href="#widgetOverride">widgetOverride</a> verwendet werden. Siehe auch das <a href="http://www.fhemwiki.de/wiki/DOIF/Ein-_und_Ausgabe_in_FHEMWEB_und_Tablet-UI_am_Beispiel_einer_Schaltuhr">weiterf&uuml;hrende Beispiel für Tablet-UI</a>. Für die Verwendung moduleigener Readings ist die Funktionalität nicht gew&auml;hrleistet, siehe <a href="#DOIF_Benutzerreadings">benutzerdefinierte Readings</a>.<br>
<br>
<u>Anwendungsbeispiel</u>: Eine Schaltuhr mit time-Widget f&uuml;r die Ein- u. Ausschaltzeiten und der M&ouml;glichkeit &uuml;ber eine Auswahlliste manuell ein und aus zu schalten.<br>
<br>
<code>
define time_switch DOIF (["$SELF:mybutton: on"] or [[$SELF:mybegin,"00:00"]])
<ol>(set lamp on)</ol>
DOELSEIF (["$SELF:mybutton: off"] or [[$SELF:myend,"00:00"]])
<ol>(set lamp off)</ol>
<br>
attr time_switch cmdState on|off<br>
attr time_switch readingList mybutton mybegin myend<br>
attr time_switch setList mybutton:on,off mybegin:time myend:time<br>
attr time_switch webCmd mybutton:mybegin:myend
</code><br>
<br>
<u>Anwendungsbeispiel</u>: Ausführung von Befehlen abhängig einer Auswahl ohne Zusatzreading<br>
<br>
<code>define di_web DOIF ([$SELF:"myInput first"]) (do something) DOELSEIF ([$SELF:"myInput second"]) (do something else)<br>
<br>
attr di_web setList myInput:first,second</code><br>
<br>
<a name="DOIF_uiTable"></a>
<b>uiTable, das User Interface</a></b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit dem Attribut uiTable kann innerhalb eines DOIF-Moduls ein User Interface in Form einer Tabelle erstellt werden. Die Definition der Tabelle wird mit Hilfe von Perl sowie FHEM-Widgets kombiniert mit DOIF-Syntax vorgenommen.<br> 
<br>
Features:<br>
<br>
- pro DOIF eine beliebige UI-Tabelle definierbar<br>
- alle FHEM-Widgets nutzbar<br>
- alle FHEM-Icons nutzbar<br>
- DOIF-Syntax verwendbar<br>
- alle Devices und Readings in FHEM direkt darstellbar und ansprechbar<br>
- dynamische Styles (z. B. Temperaturfarbe abhängig vom Temperaturwert)<br> 
- es brauchen keine eigenen CSS- oder js-Dateien definiert werden<br>
- Nutzung vordefinierter Templates aus Template-Dateien<br>
<br>
<b>Aufbau des uiTable-Attributs<br></b>
<br>
<code>{<br>
 &lt;Perlblock für Definition von Template-Attributen, Zellenformatierungen, eigenen Perlfunktionen&gt;<br>
}<br>
<br>
&lt;Template-Methoden&gt;<br>
<br>
&lt;Tabellendefinition&gt;<br>
<br></code>
<br>
Der Perlblock ist optional. Er wird in geschweiften Klammern mit wenigen Ausnahmen in Perl definiert. Hier können Template-Attribute für Zeichenketten, das Layout der Tabelle über HMTL-Zellenformatierungen sowie eigene Perlfunktionen definiert werden.
Im Anschluß an den Perlblock können optional Template-Methoden definiert werden, um komplexere wiederverwendbare Widget-Definitionen zu formulieren. Diese werden in der Tabellendefinition benutzt.
Die eigentliche Tabellendefinition wird über die Definition von Zellen vorgenommen. Zellen werden mit | voneinander abgegrenzt. Kommentare können an beliebiger Stelle beginnend mit ## bis zum Zeilenende eingefügt werden.<br>
<br>
<b>Die Tabellendefinition</b><br>
<br><code>
&lt;Zellendefinition erste Zeile erste Spalte&gt;  | &lt;Zellendefinition erste Zeile zweite Spalte  | ... # Definition der ersten Tabellenzeile<br>
&lt;Zellendefinition zweite Zeile erste Spalte&gt; | &lt;Zellendefinition zweite Zeile zweite Spalte | ... # Definition der zweiten Tabellenzeile<br>
usw.<br></code>
<br>
Endet eine Zeile mit |, so wird deren Definition in der nächsten Zeile fortgesetzt. Dadurch können längere Zeilendefinition einer Tabelle auf mehrerer Zeilen aufgeteilt werden.<br>
<br>
Eine Zellendefinition kann sein:<br>
<br>
1) <code>&lt;Perlausdruck mit [DOIF-Syntax]&gt;<br></code>
<br>
2) <code>STY(&lt;Perlausdruck mit [DOIF-Syntax]&gt;,&lt;css-Style-Definition mit [DOIF-Syntax]&gt;)<br></code>
<br>
3) <code>WID([&lt;DEVICE&gt;:&lt;READING&gt;],&lt;FHEM-Widget-Definition mit [DOIF-Syntax]&gt;,"&lt;set-/setreading-Kommando optional&gt;")<br></code>
<br>
Die oberen Definitionen können innerhalb einer Zelle mit Punkt bzw. Komma beliebig kombiniert werden. Beim Punkt werden die Ausdrücke aneinandergereiht, bei Komma werden die Ausdrücke mit Zeilenumbruch untereinander innerhalb einer Zelle angeordnet.<br>
<br>
Zu 1)<br>
<br>
Diese Definition wird verwendet für: Texte, Inhalte von Readings oder Rechenausdrücke. Angaben, die die Zelle aktualisieren sollen, müssen in gewohnte DOIF-Syntax angegeben werden.
<br>
Beispiele:<br>
<br>
Einfacher Text: <br>
<br>
<code>"Status"<br></code>
<br>
Reading:<br>
<br>
<code>[outdoor:temperature]<br></code>
<br>
Berechnung:<br>
<br>
<code>([livingroom:temperature]+[kitchen:temperature])/2<br></code>
<br>
Perlfunktion:<br>
<br>
<code>min([livingroom:temperature],[ktichen:temperature])<br></code>
<br>
Mehrere Angaben einer Zelle können mit einem Punkt, wie auch in Perl bei Zeichenketten üblich, konkateniert werden:<br>
<br>
<code>"Temperature: ".[outdoor:temperatur]<br></code>
<br>
<code>"Die maximale Temperatur der Kinderzimmer beträgt: ".max([child1:temperature],[child2:temperature])<br></code>
<br>
Zu 2)<br>
<br>
Über die Funktion STY werden Angaben mit Formatierungen über das CSS-Style-Attribut vorgenommen.<br>
<br>
Beispiele:<br>
<br>
Formatierter Text:<br>
<br>
<code>STY("diningroom","font-weight:bold;font-size:16pt;color:#0000FF")<br></code>
<br>
Formatiertes Reading:<br>
<br>
<code>STY([fridge:temperature],"color:#0000FF")<br></code>
<br>
Formatiertes Reading mit dynamischer Farbgebung abhängig von der Temperatur<br>
<br>
<code>STY([basement:humidity],"color:".DOIF_hsv([basement:humidity],50,75,40,264,60,90))<br></code>
<br>
DOIF_hsv ist eine DOIF-Funktion, bei der man den Farbverlauf definieren kann.<br>
<br>
Syntax für die  DOIF_hsv Funktion:<br>
<br>
<code>DOIF_hsv(&lt;value&gt;,&lt;min_value&gt;,&lt;max_value&gt;,&lt;min_hsv&gt;,&lt;max_hsv&gt;,&lt;saturation&gt;,&lt;lightness&gt;)<br></code>
<br>
Es wird durch eine feste Vorgabe von saturation und lightness, linear ein Farbton (Hue) für value errechnet, dabei entspricht min_value min_hsv und max_value max_hsv.<br>
<br>
Die gewünschten Werte für &lt;min_hsv&gt;,&lt;max_hsv&gt;,&lt;saturation&gt;,&lt;lightness&gt; können mit Hilfe eines Color-Pickers bestimmt werden.<br>
<br>
Weiterhin lässt sich ebenfalls jede andere Perlfunktion verwenden, die eine beliebige css-Style-Formatierung vornimmt.<br>
<br>
Zu 3)<br>
<br>
Über die Funktion WID werden FHEM-Widgets definiert. Es können alle in FHEM vorhanden FHEM-Widgets verwendet werden.<br>
<br>
Beispiele:<br>
<br>
Brennericon<br>
<br>
<code>WID([burner:state],"iconLabel,closed,sani_boiler_temp\@DarkOrange,open,sani_boiler_temp")<br></code>
<br>
Die Widget-Definition entspricht der FHEM-Widget-Syntax, siehe: <a href="https://wiki.fhem.de/wiki/FHEMWEB/Widgets">FHEMWEB-Widgets</a><br>
<br>
Thermostatdefinition mit Hilfe des knob-Widgets:<br>
<br>
<code>WID([TH_Bathroom_HM:desired-temp],"knob,min:17,max:25,width:45,height:40,step:0.5,fgColor:DarkOrange,bgcolor:grey,anglearc:270,angleOffset:225,cursor:10,thickness:.3","set")<br></code>
<br>
<b>Der Perlblock: Definition von Template-Attributen, Zellenformatierungen und Perl-Funktionen<br></b>
<br>
Im ersten Bereich werden sog. Template-Attribute als Variablen definiert, um wiederholende Zeichenketten in Kurzform anzugeben. Template-Attribute werden intern als hash-Variablen abgelegt. Die Syntax entspricht weitgehend der Perl-Syntax.<br>
<br>
Die Syntax lautet:<br>
<br>
<code>$TPL{&lt;name&gt;}=&lt;Perlsyntax für Zeichenketten&gt;<br></code>
<br>
<code>&lt;name&gt;</code> ist beliebig wählbar. <br>
<br>
Bsp.<br>
<code>$TPL{HKnob}="knob,min:17,max:25,width:45,height:40,step:0.5,fgColor:DarkOrange,bgcolor:grey,anglearc:270,angleOffset:225,cursor:10,thickness:.3";<br></code>
<br>
Damit würde die obige Beispiel-Definition des Thermostat-Widgets wie folgt aussehen:<br>
<br>
<code>WID([TH_Bad_HM:desired-temp],$TPL{HKnob},"set")<br></code>
<br>
Weiterhin können die Tabelle, einzelne Zellen-, Zeilen- oder Spaltenformatierungen definiert werden, dazu werden folgende Bezeichner benutzt:<br>
<br>
<code>$TABLE="&lt;CSS-Attribute&gt;"<br>
$TD{&lt;Zellenbereich für Zeilen&gt;}{&lt;Zellenbereich für Spalten&gt;}="&lt;CSS-Attribute der Zellen&gt;"<br>
$TC{&lt;Zellenbereich für Spalten&gt;}="&lt;CSS-Attribute der Spalten&gt;"<br>
$TR{Zeilenbereich}="&lt;CSS-Attribute der Zeilen&gt;"<br></code>
<br>
mit <br>
<br>
<code>&lt;Zellen/Spalten/Zeilen-Bereich&gt;: Zahl|kommagetrennte Aufzählung|Bereich von..bis<br></code>
<br>
Beispiele:<br>
<code>
$TABLE = "width:300px; height:300px; background-image:url(/fhem/www/pgm2/images/Grundriss.png); background-size: 300px 300px;";<br>
$TD{0}{0} = "style='border-right-style:solid; border-right-width:10px'";<br>
$TR{0} = "class='odd' style='font-weight:bold'";<br>
$TC{1..5} = "align='center'";<br>
$TC{1,3,5} = "align='center'";<br>
$TC{last} = "style='font-weight:bold'";<br></code>
<br>
Es können ebenfalls beliebige Perl-Funktionen definiert werden, die innerhalb der Tabellendefinition genutzt werden können. Sie sollten mit FUNC_ beginnen. Damit wird sichergestellt, dass die Funktionen systemweit eindeutig sind.<br>
<br>
Bsp.<br>
<br>
Funktion für temperaturabhängige Farbgebung<br>
<br>
<code>
sub FUNC_temp<br>
 {<br>
  my ($temp)=@_<br>
    return ("font-weight:bold;font-size:12pt;color:".DOIF_hsv ($temp,15,35,210,360,60,90));<br>
 }<br>
<br></code>
<b>Steuerungsattribute<br></b>
<br>
Ausblenden des Status in der Devicezeile:<br>
<br>
<code>$SHOWNOSTATE=1;</code><br>
<br>
Standardmäßig werden Texte innerhalb der Tabelle, die einem vorhandenen FHEM-Device entsprechen als Link zur Details-Ansicht dargestellt. Soll diese Funktionalität unterbunden werden, so kann man dies über folgendes Attribut unterbinden:<br> 
<br>
<code>$SHOWNODEVICELINK=1;</code><br>
<br>
Die Gerätezeile wird ausgeblendet, wenn der "Reguläre Ausdruck" &lt;regex room&gt; zum Raumnamen passt, gilt nicht für den Raum <i>Everything</i>.<br>
<br>
<code>$SHOWNODEVICELINE = "&lt;regex room&gt;";</code><br>
<br>
Die Detailansicht wird umorganisiert, hilfreich beim Editieren längerer uiTable-Definitionen.<br>
<br>
<code>$ATTRIBUTESFIRST = 1;</code><br>
<br>
<b>Template-Methoden<br></b>
<br>
Bei Widgetdefinition, die mehrfach verwendet werden sollen, können Template-Methoden definiert werden. Die Definition beginnt mit dem Schlüsselwort <code>DEF</code>. Die Template_Methode muss mit <code>TPL_</code> beginnen.<br>
<br>
Syntax<br>
<br>
<code>DEF TPL_&lt;name&gt;(&lt;Definition mit Platzhaltern $1,$2 usw.&gt;)<br></code>
<br>
<code>&lt;name&gt;</code> ist beliebig wählbar.<br>
<br>
In der Tabellendefinition können die zuvor definierten Template-Methoden genutzt werden. Die Übergabeparameter werden an Stelle der Platzhalter $1, $2 usw. eingesetzt.<br>
<br>
Beispiel<br>
<br>
Template-Methoden-Definition:<br>
<br>
<code>DEF TPL_Thermostat(WID($1,$TPL{HKnob},"set"))<br></code>
<br>
Nutzung der Template-Methode in der Tabellendefinition:<br>
<br>
<code>
"Bathroom" | TPL_Thermostat([TH_Bathroom_HM:desired-temp])<br>
"Kitchen" | TPL_Thermostat([TH_Kitchen_HM:desired-temp])<br>
"Livingroom" | TPL_Thermostat([TH_Livingroom_HM:desired-temp])<br></code>
<br>
<b>Import von Templates und Funktionen<br></b>
<br>
Mit Hilfe des Befehls IMPORT können Definitionen aus Dateien importiert werden. Damit kann der Perlblock sowie Template-Methoden in eine Datei ausgelagert werden. Der Aufbau der Datei entspricht dem des uiTable-Attributes. Tabellendefinitionen selbst können nicht importiert werden.
Der IMPORT-Befehl kann vor dem Perlblock oder vor dem Tabellendefintionsbereich angegeben werden. Ebenso können mehrere IMPORT-Befehle angegeben werden. Gleiche Definitionen von Funktionen, Templates usw. aus einer IMPORT-Datei überlagern die zuvor definierten.
Der IMPORT-Befehl kann ebenfalls innerhalb einer Import-Datei angegeben werden.<br>
<br>
Syntax<br>
<br>
<code>IMPORT &lt;Pfad mit Dateinamen&gt<br></code>
<br>
Bespiel:<br>
<br>
in uiTable<br> 
<br>
<code>IMPORT /fhem/contrib/DOIF/mytemplates.tpl<br>
<br>
## table definition<br>
<br>
"outdoor" | TPL_temp([outdoor:temperature])<br>
<br></code>
in mytemplates.tpl<br>
<br>
<code>## templates and functions<br>
{<br>
 $TPL{unit}="°C";<br>
 sub FUNC_temp<br>
 {
     my ($temp)=@_;<br>
     return ("height:6px;font-weight:bold;font-size:16pt;color:".DOIF_hsv ($temp,-10,30,210,360,60,90));<br>
 }<br>
}<br>
<br>
## template methode<br>
DEF TPL_temp(STY($1.$TPL{unit},FUNC_temp($1)))<br></code>
<br>
<br>
<a name="DOIF_cmdState"></a>
<b>Status des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Der Status des Moduls wird standardmäßig mit cmd_1, cmd_2, usw., bzw. cmd1_1 cmd1_2 usw. für Befehlssequenzen belegt. Dieser lässt sich über das Attribut "cmdState" mit Komma bzw. | getrennt umdefinieren:<br>
<br>
attr &lt;DOIF-modul&gt; cmdState  &lt;Status für cmd1_1&gt;,&lt;Status für cmd1_2&gt;,...| &lt;Status für cmd2_1&gt;,&lt;Status für cmd2_2&gt;,...|...<br>
<br>
Beispiele:<br>
<br>
<code>attr di_lamp cmdState on|off</code><br>
<br>
Pro Status können ebenfalls Status oder Readings in eckigen Klammern oder Perlfunktionen sowie Berechnungen in Klammern der Form {(...)} angegeben werden.<br>
Die Trennzeichen Komma und | sind in Klammern und Anführungszeichen geschützt und gelten dort nicht als Trennzeichen.<br>
<br>
Zustände cmd1_1, cmd1 und cmd2 sollen wie folgt umdefiniert werden:<br>
<br>
<code>attr di_mytwilight cmdState [mytwilight:ss_astro], {([mytwilight:twilight_weather]*2+10)}|My attribut is: {(Attr("mydevice","myattr",""))}</code><br>
<br>
<a name="DOIF_Reine_Statusanzeige_ohne_Ausfuehrung_von_Befehlen"></a>
<b>Reine Statusanzeige ohne Ausführung von Befehlen</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Der Ausführungsteil kann jeweils ausgelassen werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Aktuelle Außenfeuchtigkeit im Status<br>
<br>
<code>define di_hum DOIF ([outdoor:humidity]&gt;70) DOELSEIF ([outdoor:humidity]&gt;50) DOELSE<br>
attr di_hum cmdState wet|normal|dry</code><br>
<br>
<a name="DOIF_state"></a>
<b>Anpassung des Status mit Hilfe des Attributes <code>state</code></b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Es können beliebige Reading und Status oder Internals angegeben werden.<br>
<br>
<u>Anwendungsbeispiel</u>: Aktuelle Außenfeuchtigkeit inkl. Klimazustand (Status des Moduls wurde mit cmdState definiert s. o.)<br>
<br>
<code>attr di_hum state The current humidity is [outdoor:humidity], it is [di_hum]</code><br>
<br>
Es können beim Attribut state ebenfalls Berechnungen in geschweiften Klammern durchgeführt werden. Aus Kompatibilitätsgründen, muss die Berechnung mit einer runden Klammer beginnen.<br>
<br>
<u>Anwendungsbeispiel</u>: Berechnung des Mittelwertes zweier Readings:<br>
<br>
<code>define di_average DOIF <br>
attr di_average state Average of the two rooms is {([room1:temperature]+[room2:temperature])/2}</code><br>
<br>
Der Status wird automatisch aktualisiert, sobald sich eine der Temperaturen ändert<br>
<br>
Da man beliebige Perl-Ausdrücke verwenden kann, lässt sich z. B. der Mittelwert auf eine Stelle mit der Perlfunktion sprintf formatieren:<br>
<br>
<code>attr di_average state Average of the two rooms is {(sprintf("%.1f",([room1:temperature]+[room2:temperature])/2))}</code><br>
<br>
<a name="DOIF_Readings"></a>
<b>Erzeugen berechneter Readings</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit Hilfe des Attributes DOIF_Readings können eigene Readings innerhalb des DOIF definiert werden, auf die man im selben DOIF-Moduls zugreifen kann.
Die Nutzung ist insbesondere dann sinnvoll, wenn mehrfach die gleichen Berechnungen innerhalb eines DOIF-Modus vorgenommen werden sollen.
DOIF_Readings-Berechnungen funktionieren ressourcenschonend ohne Erzeugung FHEM-Events nach außen. Änderungen dieser Readings triggern allerdings das eigene DOIF-Modul, wenn sich deren Inhalt ändert.<br>
<br>
Syntax<br>
<br>
<code>attr &lt;DOIF-Modul&gt; DOIF_Readings &lt;readingname1&gt;:&lt;definiton&gt;, &lt;readingname2&gt;:&lt;definition&gt;,...</code><br>
<br>
<code>&lt;definition&gt;</code>: Beliebiger Perlausdruck ergänzt um DOIF-Syntax in eckigen Klammern. Angaben in eckigen Klammern wirken triggernd und aktualisieren das definierte Reading.<br>
<br>
Beispiel: Push-Mitteilung über die durchschnittliche Temperatur aller Zimmer<br>
<br>
<code>define di_temp DOIF ([$SELF:temperature]&gt;20) (push "Die Durchschnittstemperatur ist höher als 20 Grad, sie beträgt [$SELF:temperature]")<br>
DOELSE<br>
<br>
attr di_temp DOIF_Readings temperature:[#average:d2:":temperature":temperature]<br></code>
<br>
Hierbei wird der aufwändig berechnete Durchschnittswert nur einmal berechnet, statt zwei mal, wenn man die Aggregationsfunktion direkt in der Bedingung und im Ausführungsteil angeben würde.<br>
<br>
Mit DOIF_Readings ist es ebenfalls möglich eine Wiederholung des Schaltens eines DOIF-Moduls mit do always zu provozieren und gleichzeitig zyklisch sendende Sensoren abzufragen.<br>
<br>
Beispiel<br>
<br>
<code>define heating DOIF ([switch] eq "on" and [$SELF:frost] eq "on") (set heating on) DOELSE (set heating off)<br>
attr heating do always<br>
attr heating DOIF_Readings frost:([outdoor:temperature] < 0 ? "on" : "off")</code><br>
<br>
Das Attribut do always ist in diesem Beispiel unkritisch, obwohl Temperatur zyklisch gesendet wird, da das Reading "frost" nur dann die Bedingung triggert, wenn sich dessen Inhalt ändert<br>
<br>
<a name="DOIF_initialize"></a>
<b>Vorbelegung des Status mit Initialisierung nach dem Neustart mit dem Attribut <code>initialize</code></b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
<u>Anwendungsbeispiel</u>: Nach dem Neustart soll der Zustand von <code>di_lamp</code> mit "initialized" vorbelegt werden. Das Reading <code>cmd_nr</code> wird auf 0 gesetzt, damit wird ein Zustandswechsel provoziert, das Modul wird initialisiert - der nächste Trigger führt zum Ausführen eines Kommandos.<br>
<br>
<code>attr di_lamp intialize initialized</code><br>
<br>
Das ist insb. dann sinnvoll, wenn das System ohne Sicherung der Konfiguration (unvorhergesehen) beendet wurde und nach dem Neustart die zuletzt gespeicherten Zustände des Moduls nicht mit den tatsächlichen übereinstimmen.<br>
<br>
<a name="DOIF_startup"></a>
<b>Ausführen von Befehlsketten beim Starten von FHEM</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Beim Hochfahren von FHEM lässt sich eine bestimme Aktion ausführen. Es kann dazu genutzt werden, um sofort nach dem Hochfahren des Systems einen definierten Zustand des Moduls zu erreichen.
Dabei wird sichergestellt, dass die angegebenen Befehle erst dann ausgeführt werden, wenn FHEM komplett hochgefahren ist.<br>
<br>
Symtax:<br>
<br>
<code>attr &lt;DOIF-Modul&gt; startup &lt;FHEM-Befehl oder Perl-Befehl in geschweiften Klammern mit DOIF-Syntax&gt;</code><br>
<br>
Die Syntax entspricht der eines DOIF-Ausführungsteils (runde Klammern brauchen nicht angegeben werden).<br>
<br>
Beispiele:<br>
<br>
<code>attr di_test startup set $SELF cmd_1</code><br>
<code>attr di_test startup set $SELF checkall</code><br>
<code>attr di_test startup sleep 60;set lamp1 off;set lamp2 off</code><br>
<code>attr di_test startup {myfunction()},set lamp1 on,set lamp2 on</code><br>
<br>
<a name="DOIF_disable"></a>
<b>Deaktivieren des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Ein DOIF-Modul kann mit Hilfe des Attributes disable, deaktiviert werden. Dabei werden alle Timer und Readings des Moduls gelöscht.
Soll das Modul nur vorübergehend deaktiviert werden, so kann das durch <code>set &lt;DOIF-modul&gt; disable</code> geschehen.
<br>
<br>
<a name="DOIF_setBefehle"></a>
<b>Set-Befehle</b><br>
<br>
<a name="DOIF_setcheckall"></a>
<b>Überprüfung aller DOIF-Bedingungen mit Ausführung eines DOIF-Zweiges</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
mit dem set-Befehl <code>checkall</code> werden wie beim gleichnamigen Attribut alle DOIF-Bedingung überprüft, sobald eine Bedingung als wahr geprüft ist, wird das dazugehörige Kommando ausgeführt.
Zu beachten ist, dass nur der erste wahre DOIF-Zweig ausgeführt wird und dass nur Zustandsabfragen sowie Zeitintervalle sinnvoll überprüft werden können.
Ereignisabfragen sowie Zeitpunkt-Definitionen, sind zum Zeitpunkt der checkall-Abfrage normalerweise nicht wahr.<br>
<br>
Beispiel:<br>
<br>
<code>attr di_test startup set $SELF checkall</code><br>
<br>
<a name="DOIF_setdisable"></a>
<b>Inaktivieren des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
mit dem set-Befehl <code>disable</code> wird ein DOIF-Modul inaktiviert. Hierbei bleiben alle Timer aktiv, sie werden aktualisiert - das Modul bleibt im Takt, allerdings werden keine Befehle ausgeführt.
Das Modul braucht mehr Rechenzeit, als wenn es komplett über das Attribut <code>disable</code> deaktiviert wird. Ein inaktiver Zustand bleibt nach dem Neustart erhalten.
Ein inaktives Modul kann über set-Befehle <code>enable</code> bzw. <code>initialize</code> wieder aktiviert werden.<br>
<br>
<a name="DOIF_setenable"></a>
<b>Aktivieren des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
mit dem set-Befehl <code>enable</code> wird ein inaktives DOIF-Modul wieder aktiviert. Im Gegensatz zum set-Befehl <code>initialize</code> wird der letzte Zustand vor der Inaktivierung des Moduls wieder hergestellt.<br>
<br>
<a name="DOIF_Initialisieren_des_Moduls"></a>
<b>Initialisieren des Moduls</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
mit dem set-Befehl <code>initialize</code> wird ein DOIF-Modul initialisiert. Ein inaktives DOIF-Modul wieder aktiviert.
Im Gegensatz zum set-Befehl <code>enable</code> wird der letzte Zustand des Moduls gelöscht, damit wird ein Zustandswechsel herbeigeführt, der nächste Trigger führt zur Ausführung eines wahren DOIF-Zweiges.
Diese Eigenschaft kann auch dazu genutzt werden, ein bereits aktives Modul zu initialisieren.<br>
<br>
<a name="DOIF_setcmd"></a>
<b>Auführen von Befehlszweigen ohne Auswertung der Bedingung</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Mit <code>set &lt;DOIF-modul&gt; cmd_&lt;nr&gt</code> lässt sich ein Befehlszweig (cmd_1, cmd_2, usw.) bedingunglos ausführen.<br>
<br>
Der Befehl hat folgende Eigenschaften:<br>
<br>
1) der set-Befehl übersteuert alle Attribute wie z. B. wait, do, usw.<br>
2) ein laufender Wait-Timer wird unterbrochen<br>
3) beim deaktivierten oder im Modus disable befindlichen Modul wird der set Befehl ignoriert<br>
<br>
<u>Anwendungsbeispiel</u>: Schaltbare Lampe über Fernbedienung und Webinterface<br>
<br>
<code>
define di_lamp DOIF ([FB:"on"]) (set lamp on) DOELSEIF ([FB:"off"]) (set lamp off)<br>
<br>
attr di_lamp devStateIcon cmd_1:on:cmd_2 initialized|cmd_2:off:cmd_1<br>
</code><br>
Mit der Definition des Attributes <code>devStateIcon</code> führt das Anklicken des on/off-Lampensymbol zum Ausführen von <code>set di_lamp cmd_1</code> bzw. <code>set di_lamp cmd_2</code> und damit zum Schalten der Lampe.<br>
<br>
Wenn mit <code>cmdState</code> eigene Zuständsbezeichnungen definiert werden, so können diese ebenfalls per set-Befehl angegeben werden.<br>
<br>
<code>
define di_lamp DOIF ([FB:"on"]) (set lamp on) DOELSEIF ([FB:"off"]) (set lamp off)<br>
<br>
attr di_lamp cmdState on|off<br>
attr di_lamp setList on off<br>
</code>
<br>
<code>set di_lamp on</code> entspricht hier <code>set di_lamp cmd_1</code> und <code>set di_lamp off set di_lamp cmd_2</code><br>
Zusätzlich führt die Definition von <code>setList</code> zur Ausführung von <code>set di_lamp on/off</code> durch das Anlicken des Lampensymbols wie im vorherigen Beispiel.<br>
<br>
<br>
<a name="DOIF_Weitere_Anwendungsbeispiele"></a>
<b>Weitere Anwendungsbeispiele</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
Zweipunktregler a la THRESHOLD<br>
<br>
<code>define di_threshold DOIF ([sensor:temperature]<([$SELF:desired]-1))<br>
  (set heating on)<br>
DOELSEIF ([sensor:temperature]>[$SELF:desired])<br>
  (set heating off)<br>
<br>
attr di_threshold cmdState on|off<br>
attr di_threshold readingList desired<br>
attr di_threshold setList desired:17,18,19,20,21,22<br>
attr di_threshold webCmd desired<br>
</code><br>
Die Hysterese ist hier mit einem Grad vorgegeben. Die Vorwahltemperatur wird per Dropdown-Auswahl eingestellt.<br>
<br>
on-for-timer<br>
<br>
Die Nachbildung eines on-for-timers lässt sich wie folgt realisieren:<br>
<br>
<code>define di_on_for_timer ([detector:"motion"])<br>
  (set light on)<br>
  (set light off)<br>
attr di_on_for_timer do resetwait<br>
attr di_on_for_timer wait 0,30</code><br>
<br>
Hiermit wird das Licht bei Bewegung eingeschaltet. Dabei wird, solange es brennt, bei jeder Bewegung die Ausschaltzeit neu auf 30 Sekunden gesetzt, "set light on" wird dabei nicht unnötig wiederholt.<br>
<a href="#DOIF_Treppenhauslicht mit Bewegungsmelder">siehe auch Treppenhauslicht mit Bewegungsmelder im Perl-Modus</a><br>
<br>
Die Beispiele stellen nur eine kleine Auswahl von möglichen Problemlösungen dar. Da sowohl in der Bedingung (hier ist die komplette Perl-Syntax möglich), als auch im Ausführungsteil, keine Einschränkungen gegeben sind, sind die Möglichkeiten zur Lösung eigener Probleme mit Hilfe des Moduls sehr vielfältig.<br>
<br>
<a name="DOIF_Zu_beachten"></a>
<b>Zu beachten</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a><br>
<br>
In jeder Bedingung muss mindestens ein Trigger angegeben sein (Angaben in eckigen Klammern). Die entsprechenden DO-Fälle werden nur dann ausgewertet, wenn auch das entsprechende Event oder Zeit-Trigger ausgelöst wird.<br>
<br>
Zeitangaben der Art: <br>
<br>
<code>define di_light DOIF ([08:00] and [10:00]) (set switch on)</code><br>
<br>
sind nicht sinnvoll, da diese Bedingung nie wahr sein wird.<br>
<br>
Angaben, bei denen aufgrund der Definition kein Zustandswechsel erfolgen kann z. B.:<br>
<br>
<code>define di_light DOIF ([08:00]) (set switch on)<br>
attr di_light do always</code><br>
<br>
müssen mit Attribut <code>do always</code> definiert werden, damit sie nicht nur einmal, sondern jedes mal (hier jeden Tag) ausgeführt werden.<br>
<br>
Bei Devices, die mit Zwischenzuständen arbeiten, insbesondere HM-Komponenten (Zwischenzustand: set_on, set_off), sollte die Definition möglichst genau formuliert werden, um unerwünschte Effekte zu vermeiden: <br>
<br>
statt:<br>
<br>
<code>define di_lamp DOIF ([HM_switch] eq "on") (set lamp on) DOELSE (set lamp off)</code><br>
<br>
konkreter spezifizieren:<br>
<br>
<code>define di_lamp DOIF ([HM_switch] eq "on") (set lamp on) DOELSEIF ([HM_switch] eq "off") (set lamp off)</code><br>
<br>
Namenskonvention: Da der Doppelpunkt bei Readingangaben als Trennzeichen gilt, darf er nicht im Namen des Devices vorkommen. In solchen Fällen bitte das Device umbenennen.<br>
<br>
Standardmäßig, ohne das Attribut <code>do always</code>, wird das Wiederholen desselben Kommmandos vom Modul unterbunden. Daher sollte nach Möglichkeit eine Problemlösung mit Hilfe eines und nicht mehrerer DOIF-Module realisiert werden, getreu dem Motto "wer die Lampe einschaltet, soll sie auch wieder ausschalten".
Dadurch wird erreicht, dass unnötiges (wiederholendes) Schalten vom Modul unterbunden werden kann, ohne dass sich der Anwender selbst darum kümmern muss.<br>
<br>
Mehrere Bedingungen, die zur Ausführung gleicher Kommandos führen, sollten zusammengefasst werden. Dadurch wird ein unnötiges Schalten aufgrund verschiedener Zustände verhindert.<br>
<br>
Beispiel:<br>
<br>
<code>define di_lamp DOIF ([brightness] eq "off") (set lamp on) DOELSEIF ([19:00]) (set lamp on) DOELSE (set lamp off)</code><br>
<br>
Hier wird um 19:00 Uhr Lampe eingeschaltet, obwohl sie evtl. vorher schon durch das Ereignis brightness "off" eingeschaltet wurde.<br>
<br>
<code>define di_lamp DOIF ([brightness] eq "off" or [19:00]) (set lamp on) DOELSE (set lamp off)</code><br>
<br>
Hier passiert das nicht mehr, da die ursprünglichen Zustände cmd_1 und cmd_2 jetzt nur noch einen Zustand cmd_1 darstellen und dieser wird nicht wiederholt.<br>
<br>
<!-- Beginn der Kurzreferenz -->
<a name="DOIF_Kurzreferenz"></a>
<b>Kurzreferenz</b>&nbsp;&nbsp;&nbsp;<a href="#DOIF_Inhaltsuebersicht">back</a></br>

<ul>
&lang;&rang; kennzeichnet optionale Angaben
</ul>
</br>
<u><a href="#DOIF">Definition</a></u>
<ul>
<dl>
        <dt> <code><b>define</b> &lt;name&gt; <b>DOIF </b>&lang;<b>(</b>&lt;Bedingung&gt;<b>) </b>&lang;&lang;<b>(</b>&lang;&lt;Befehle&gt;&rang;<b>)</b>&rang; &lang;&lang;&lang;<b>DOELSEIF (</b>&lt;Bedingung&gt;<b>) </b>&lang;<b>(</b>&lang;&lt;Befehle&gt;&rang;<b>)</b>&rang;&rang; ... &rang;&lang;<b>DOELSE </b>&lang;<b>(</b>&lang;&lt;Befehle&gt;&rang;<b>)</b>&rang;&rang;&rang;&rang;&rang;</code>
        </dt>
                <dd>Befehlstrennzeichen ist das Komma<code><b> (</b>&lt;Befehl&gt;<b>,</b> &lt;Befehl&gt;, ...<b>)</b></code>
                </dd>
                <dd>Befehlssequenzen werden in runde Klammern gesetzt <code><b>(</b>&lt;Befehlssequenz A&gt;<b>) (</b>&lt;Befehlssequenz B&gt;<b>) ...</b></code>
                </dd>
                <dd>Enth&auml;lt ein Befehl Kommata, ist er zus&auml;tzlich in runde Klammern einzuschliessen <code><b>(</b>&lt;Befehlsteil a&gt;<b>, </b>&lt;Befehlsteil b&gt; ... <b>)</b></code>
                </dd>
                <dd>Perl-Befehle <code><b>{</b>&lt;Perl-Befehl&gt;<b>}</b></code> sind in geschweifte Klammern einzuschliessen
                </dd>
                <dd>Jede <a href="#DOIF_Berechnungen_im_Ausfuehrungsteil">Berechnung</a> <code><b>{(</b>&lt;Berechnung&gt;<b>)</b>&lang;&lt;Berechnung&gt;&rang;<b>}</b></code> in einem Befehl ist in geschweifte Klammern einzuschliessen und muss mit einer ge&ouml;ffneten runden Klammer beginnen.
                </dd>
</dl>
</ul>
</br>
<u>Readings</u>
<ul>
<dl>
        <dt>Device</dt>
                <dd>Name des ausl&ouml;senden Ger&auml;tes</dd>
</br>
        <dt>cmd</dt>
                <dd>Nr. des letzten ausgef&uuml;hrten Befehls als Dezimalzahl oder 0 nach Initialisierung des DOIF, in der Form &lt;Nr. des Befehlszweiges&gt;&lang;.&lt;Nr. der Sequenz&gt;&rang;</dd>
</br>
        <dt>cmd_event</dt>
                <dd>Angabe des ausl&ouml;senden Ereignisses</dd>
</br>
        <dt>cmd_nr</dt>
                <dd>Nr. des letzten ausgef&uuml;hrten Befehlszweiges</dd>
</br>
        <dt>cmd_seqnr</dt>
                <dd>Nr. der letzten ausgef&uuml;hrten Befehlssequenz</dd>
</br>
        <dt>e_&lt;Device&gt;_&lt;Reading&gt;|&lt;Internal&gt;|Events</dt>
                <dd>Bezeichner und Wert der ausl&ouml;senden Ger&auml;te mit Readings, Internals oder Events</dd>
</br>
        <dt>error</dt>
                <dd>Enthält Fehlermeldungen oder R&uuml;ckgabewerte von Befehlen, siehe <a href="http://www.fhemwiki.de/wiki/DOIF/Tools_und_Fehlersuche#Besonderheit_des_Error-Reading">Besonderheit des Error-Reading</a></dd>
</br>
        <dt>last_cmd</dt>
                <dd>letzter Status</dd>
</br>
        <dt>matched_event_c&lt;lfd. Nr. der Bedingung&gt;_&lt;lfd. Nr. des Events&gt;</dt>
                <dd>Wert, der mit dem Regul&auml;ren Ausdruck &uuml;bereinstimmt</dd>
</br>
        <dt>mode</dt>
                <dd>der Modus, in dem sich DOIF befindet: &lt;enabled|disabled|deactivated&gt;</dd>
</br>
        <dt>state</dt>
                <dd>Status des DOIF nach Befehlsausf&uuml;hrung, Voreinstellung: cmd_&lt;Nr. des Befehlszweiges&gt;&lang;_&lt;Nr. der Befehlssequenz&gt;&rang;</dd>
</br>
        <dt>timer_&lt;lfd. Nr.&gt;_c&lt;Nr. des Befehlszweiges&gt;</dt>
                <dd>verwendete Timer mit Angabe des n&auml;chsten Zeitpunktes</dd>
</br>
        <dt>wait_timer</dt>
                <dd>Angabe des aktuellen Wait-Timers</dd>
</br>
        <dt>warning</dt>
                <dd>Perl-Warnung bei der Auswertung einer Bedingung</dd>
</br>

  <a name="DOIF_Benutzerreadings"></a>
        <dt>&lt;A-Z&gt;_&lt;readingname&gt;</dt>
                <dd>Readings, die mit einem Großbuchstaben und nachfolgendem Unterstrich beginnen, sind für User reserviert und werden auch zuk&uuml;nftig nicht vom Modul selbst benutzt.</dd>
</dl>
</br>
</ul>
<u>Operanden in der Bedingung und den Befehlen</u>
<ul>
<dl>
        <dt><a href="#DOIF_Ereignissteuerung">Status</a> <code><b>[</b>&lt;Device&gt;&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
                <dd></dd>
</br>
        <dt><a href="#DOIF_Ereignissteuerung">Readings</a> <code><b>[</b>&lt;Device&gt;<b>:</b>&lt;Reading&gt;&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
                <dd></dd>
</br>
        <dt><a href="#DOIF_Ereignissteuerung">Internals</a> <code><b>[</b>&lt;Device&gt;<b>:&amp;</b>&lt;Internal&gt;&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
                <dd></dd>
</br>
        <dt><a href="#DOIF_Filtern_nach_Zahlen">Filtern allgemein</a> nach Ausdr&uuml;cken mit Ausgabeformatierung: <code><b>[</b>&lt;Device&gt;:&lt;Reading&gt;|&lt;Internal&gt;:"&lt;Filter&gt;"&lang;:&lt;Output&gt;&rang;&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
</br>
        <dt><a href="#DOIF_Filtern_nach_Zahlen">Filtern einer Zahl</a> <code><b>[</b>&lt;Device&gt;<b>:</b>&lt;Reading&gt;<b>:d</b>&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
</br>
        <dt><a href="#DOIF_Zeitspanne_eines_Readings_seit_der_letzten_Aenderung">Zeitspanne eines Readings seit der letzten &Auml;nderung</a> <code><b>[</b>&lt;Device&gt;<b>:</b>&lt;Reading&gt;<b>:sec</b>&lang;<b>,</b>&lt;Default&gt;&rang;<b>]</b></code></dt>
</br>
        <dt>$DEVICE</dt>
                <dd>f&uuml;r den Ger&auml;tenamen</dd>
</br>
        <dt>$EVENT</dt>
                <dd>f&uuml;r das zugeh&ouml;rige Ereignis</dd>
</br>
        <dt>$EVENTS</dt>
                <dd>f&uuml;r alle zugeh&ouml;rigen Ereignisse eines Triggers</dd>
</br>
        <dt>$SELF</dt>
                <dd>f&uuml;r den Ger&auml;tenamen des DOIF</dd>
</br>
        <dt>&lt;Perl-Funktionen&gt;</dt>
                <dd>vorhandene und selbsterstellte Perl-Funktionen</dd>
</dl>
</br>
</ul>

<u>Operanden in der Bedingung</u>
<ul>
<dl>
        <dt><a href="#DOIF_Ereignissteuerung_ueber_Auswertung_von_Events">Events</a> <code><b>[</b>&lt;Device&gt;<b>:"</b>&lt;Regex-Events&gt;"<b>]</b></code> oder <code><b>["</b>&lt;Regex-Devices&gt;<b>:</b>&lt;Regex-Events&gt;<b>"]</b></code> oder <code><b>["</b>&lt;Regex-Devices&gt;<b>"</b>&lang;<b>:"</b>&lt;Regex-Filter&gt;<b>"</b>&rang;&lang;<b>:</b>&lt;Output&gt;&rang;<b>,</b>&lt;Default&gt;<b>]</b></code></dt>
                <dd>f&uuml;r <code>&lt;Regex&gt;</code> gilt: <code><b>^</b>&lt;ist eindeutig&gt;<b>$</b></code>, <code><b>^</b>&lt;beginnt mit&gt;</code>, <code>&lt;endet mit&gt;<b>$</b></code>, <code><b>""</b></code> entspricht <code><b>".*"</b></code>, Regex-Filter ist mit <code><b>[^\:]*: (.*)</b></code> vorbelegt siehe auch <a target=blank href="https://wiki.selfhtml.org/wiki/Perl/Regul%C3%A4re_Ausdr%C3%BCcke">Regul&auml;re Ausdr&uuml;cke</a> und Events des Ger&auml;tes <a target=blank href="#global">global</a>
                </dd>
</br>
        <dt><a href="#DOIF_Zeitsteuerung">Zeitpunkte</a> <code><b>[</b>&lt;time&gt;<b>]</b> </code></dt>
                <dd>als <code><b>[HH:MM]</b></code>, <code><b>[HH:MM:SS]</b></code> oder <code><b>[Zahl] </b></code> in Sekunden nach Mitternacht</dd>
</br>
        <dt><a href="#DOIF_Zeitsteuerung_mit_Zeitintervallen">Zeitintervalle</a> <code><b>[</b>&lt;begin&gt;<b>-</b>&lt;end&gt;<b>]</b></code></dt>
                <dd>als <code><b>[HH:MM]</b></code>, <code><b>[HH:MM:SS]</b></code> oder <code><b>[Zahl]</b></code> in Sekunden nach Mitternacht</dd>
</br>
        <dt><a href="#DOIF_Indirekten_Zeitangaben">indirekte Zeitangaben</a> <code><b>[[</b>&lt;indirekte Zeit&gt;<b>]]</b></code></dt>
                <dd>als <code><b>[HH:MM]</b></code>, <code><b>[HH:MM:SS]</b></code> oder <code><b>[Zahl]</b></code> in Sekunden nach Mitternacht, <code>&lt;indirekte Zeit&gt;</code> ist ein Status, Reading oder Internal</dd>
</br>
        <dt><a href="#DOIF_Relative_Zeitangaben">relative Zeitangaben</a> <code><b>[+</b>&lt;time&gt;<b>]</b></code></dt>
                <dd>als <code><b>[HH:MM]</b></code>, <code><b>[HH:MM:SS]</b></code> oder <code><b>[Zahl]</b></code> in Sekunden</dd>
</br>
        <dt><a href="#DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet">ausgerichtete Zeitraster</a> <code><b>[:MM]</b></code></dt>
                <dd>in Minuten zwischen 00 und 59</dd>
</br>
        <dt><a href="#DOIF_Relative_Zeitangaben_nach_Zeitraster_ausgerichtet">rel. Zeitraster ausgerichtet</a> <code><b>[+:MM]</b></code></dt>
                <dd>in Minuten zwischen 1 und 59</dd>
</br>
        <dt><a href="#DOIF_Zeitangaben_nach_Zeitraster_ausgerichtet_alle_X_Stunden">rel. Zeitraster ausgerichtet alle X Stunden</a> <code><b>[+[h]:MM]</b></code></dt>
                <dd><b>MM</b> in Minuten zwischen 1 und 59, <b>h</b> in Stunden zwischen 2 und 23</dd>
</br>
        <dt><a href="#DOIF_Wochentagsteuerung">Wochentagsteuerung</a> <code><b>[</b>&lt;time&gt;<b>|012345678]</b></code>, <code><b>[</b>&lt;begin&gt;<b>-</b>&lt;end&gt;<b>]</b><b>|012345678]</b></code></dt>
                <dd>Pipe, gefolgt von ein o. mehreren Ziffern. Bedeutung: 0 bis 6 f&uuml;r So. bis Sa., 7 f&uuml;r $we, Wochenende oder Feiertag, 8 f&uuml;r !$we, Werktags.</dd>
</br>
        <dt><a href="#DOIF_Zeitsteuerung_mit_Zeitberechnung">berechnete Zeitangaben</a> <code><b>[(</b>&lt;Berechnung, gibt Zeit in Sekunden zur&uuml;ck, im Sinne von <a target=blank href="http://perldoc.perl.org/functions/time.html">time</a>&gt;<b>)]</b></code></dt>
                <dd>Berechnungen sind mit runden Klammern einzuschliessen. Perlfunktionen, die HH:MM zur&uuml;ckgeben sind mit geschweiften Klammern einzuschliessen.</dd>
</br>
        <dt><a href="#DOIF_Zeitintervalle_Readings_und_Status_ohne_Trigger">Trigger verhindern</a> <code><b>[?</b>&lt;devicename&gt;<b>]</b></code>, <code><b>[?</b>&lt;devicename&gt;<b>:</b>&lt;readingname&gt;<b>]</b></code>, <code><b>[?</b>&lt;devicename&gt;<b>:&amp;</b>&lt;internalname&gt;<b>]</b></code>, <code><b>[?</b>&lt;time specification&gt;<b>]</b></code></dt>
                <dd>Werden Status, Readings, Internals und Zeitangaben in der Bedingung mit einem Fragezeichen eingeleitet, triggern sie nicht.</dd>
</br>
        <dt>$device, $event, $events</dt>
                <dd>Perl-Variablen mit der Bedeutung der Schl&uuml;sselworte $DEVICE, $EVENT, $EVENTS</dd>
</br>
        <dt>$cmd</dt>
                <dd>Perl-Variablen mit der Bedeutung [$SELF:cmd]</dd>
</br>
        <dt>&lt;Perl-Zeitvariablen&gt;</dt>
                <dd>Variablen f&uuml;r Zeit- und Datumsangaben, $sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst, $week, $hms, $hm, $md, $ymd</dd>
</dl>
</br>
</ul>
<u>set-Befehle</u>
<ul>
<dl>
        <dt><a href="#DOIF_setcheckall">disable</a> <code><b> set </b>&lt;name&gt;<b> checkall</b></code></dt>
                <dd>Überprüfung aller DOIF-Bedingungen mit Ausführung eines wahren DOIF-Zweiges</dd>
</br>
        <dt><a href="#DOIF_setdisable">disable</a> <code><b> set </b>&lt;name&gt;<b> disable</b></code></dt>
                <dd>blockiert die Befehlsausf&uuml;hrung</dd>
</br>
        <dt><a href="#DOIF_Initialisieren_des_Moduls">initialize</a> <code><b> set </b>&lt;name&gt;<b> initialize</b></code></dt>
                <dd>initialisiert das DOIF und aktiviert die Befehlsausf&uuml;hrung</dd>
</br>
        <dt><a href="#DOIF_setenable">enable</a> <code><b> set </b>&lt;name&gt;<b> enable</b></code></dt>
                <dd>aktiviert die Befehlsausf&uuml;hrung, im Gegensatz zur obigen Initialisierung bleibt der letzte Zustand des Moduls erhalten</dd>
</br>
        <dt><a href="#DOIF_setcmd">cmd_&lt;nr&gt</a> <code><b> set </b>&lt;name&gt;<b> cmd_&lt;nr&gt;</b></code></dt>
                <dd>führt ohne Auswertung der Bedingung den Befehlszweig mit der Nummer &lt;nr&gt; aus</dd>
</dl>
</br>
</ul>
<a name="DOIF_getBefehle"></a>
<u>get-Befehle</u>
<ul>
<dl>
        <dt><a name="HTML-Code von uiTable">html</a></dt>
        <dd>liefert HTML-Code einer definierten uiTable zurück.</dd>
</dl>
</br>
</ul>

<a name="DOIF_Attribute_kurz"></a>
<u>Attribute</u>
<ul>
<dl>
        <dt><a href="#DOIF_wait">Verz&ouml;gerungen</a> <code><b>attr</b> &lt;name&gt; <b>wait </b>&lt;timer_1_1&gt;<b>,</b>&lt;timer_1_2&gt;<b>,...:</b>&lt;timer_2_1&gt;<b>,</b>&lt;timer_2_2&gt;<b>,...:...</b></code></dt>
                <dd>Zeit in Sekunden als direkte Angabe oder Berechnung, ein Doppelpunkt trennt die Timer der Bedingungsweige, ein Komma die Timer der Befehlssequenzen eines Bedingungszweiges.</dd>
</br>
        <dt><a href="#DOIF_timerWithWait">Verz&ouml;gerung von Timern</a> <code><b>attr</b> &lt;name&gt; <b>timerWithWait</b></code></dt>
                <dd>erweitert <code>wait</code> auf Zeitangaben</dd>
</br>
        <dt><a href="#DOIF_do_always">Befehlswiederholung zulassen</a> <code><b>attr</b> &lt;name&gt; <b>do always</b></code></dt>
                <dd>wiederholt den Ausf&uuml;hrungsteil, wenn die selbe Bedingung wiederholt wahr wird.</dd>
</br>
        <dt><a href="#DOIF_do_resetwait">Zur&uuml;cksetzen des Waittimers bei Wiederholung</a> <code><b>attr</b> &lt;name&gt; <b>do resetwait</b></code></dt>
                <dd>setzt den Waittimer zur&uuml;ck, wenn die selbe Bedingung wiederholt wahr wird.</dd>
</br>
        <dt><a href="#DOIF_repeatcmd">Befehle wiederholen</a> <code><b>attr</b> &lt;name&gt; <b>repeatcmd </b>&lt;timer Bedingungszweig 1&gt;<b>:</b>&lt;timer Bedingungszweig 2&gt;<b>:...</b></code></dt>
                <dd>Zeit in Sekunden als direkte Angabe oder Berechnung, nach der Befehle wiederholt werden.</dd>
</br>
        <dt><a href="#DOIF_cmdpause">Pause f&uuml;r Wiederholung</a> <code><b>attr</b> &lt;name&gt; <b>cmdpause </b>&lt;Pause cmd_1&gt;<b>:</b>&lt;Pause cmd_2&gt;<b>:...</b></code></dt>
                <dd>Zeit in Sekunden als direkte Angabe oder Berechnung, blockiert die Befehlsausf&uuml;hrung w&auml;hrend der Pause.</dd>
</br>
        <dt><a href="#DOIF_repeatsame">Begrenzung von Wiederholungen</a> <code><b>attr</b> &lt;name&gt; <b>repeatsame </b>&lt;maximale Anzahl von cmd_1&gt;<b>:</b>&lt;maximale Anzahl von cmd_2&gt;<b>:...</b></code></dt>
                <dd>Anzahl als direkte Angabe oder Berechnung, begrenzt die maximale Anzahl unmittelbar folgender Befehlsausf&uuml;hrungen.</dd>
</br>
        <dt><a href="#DOIF_waitsame">Warten auf Wiederholung</a> <code><b>attr</b> &lt;name&gt; <b>waitsame </b>&lt;Wartezeit cmd_1&gt;<b>:</b>&lt;Wartezeit cmd_2&gt;<b>:...</b></code></dt>
                <dd>Wartezeit in Sekunden als direkte Angabe oder Berechnung, f&uuml;r ein unmittelbar wiederholtes Zutreffen einer Bedingung.</dd>
</br>
        <dt><a href="#DOIF_waitdel">L&ouml;schen des Waittimers</a> <code><b>attr</b> &lt;name&gt; <b>waitdel </b>&lt;timer_1_1&gt;<b>,</b>&lt;timer_1_2&gt;<b>,...:</b>&lt;timer_2_1&gt;<b>,</b>&lt;timer_2_2&gt;<b>,...:...</b></code></dt>
                <dd>Zeit in Sekunden als direkte Angabe oder Berechnung, ein laufender Timer wird gel&ouml;scht und die Befehle nicht ausgef&uuml;hrt, falls eine Bedingung vor Ablauf des Timers wiederholt wahr wird.</dd>
</br>
        <dt><a href="#DOIF_checkReadingEvent">Auswertung von Readings auf passende Events beschr&auml;nken</a> <code><b>attr</b> &lt;name&gt; <b>checkReadingEvent </b>&lt;<b>0</b>|<b>ungleich Null</b>&gt;</code></dt>
                <dd>ungleich Null aktiviert, 0 deaktiviert</dd>
</br>
        <dt><a href="#DOIF_selftrigger">Selbsttriggerung</a> <code><b>attr</b> &lt;name&gt; <b>selftrigger </b>&lt;<b>wait</b>|<b>all</b>&gt;</code></dt>
                <dd>lässt die Triggerung des Gerätes durch sich selbst zu. <code>wait</code> zugelassen für verzögerte Befehle, <code>all</code> zugelassen auch für nicht durch wait verzögerte Befehle; es ist nur eine Rekusion möglich</dd>
</br>
        <dt><a href="#DOIF_timerevent">Event beim Setzen eines Timers</a> <code><b>attr</b> &lt;name&gt; <b>timerevent </b>&lt;<b>0</b>|<b>ungleich Null</b>&gt;</code></dt>
                <dd>erzeugt beim Setzen eines Timers ein Event. ungleich Null aktiviert, 0 deaktiviert</dd>
</br>
        <dt><a href="#DOIF_cmdState">Ger&auml;testatus ersetzen</a> <code><b>attr</b> &lt;name&gt; <b>cmdState </b>&lt;Ersatz cmd_1_1&gt;<b>,</b>...<b>,</b>&lt;Ersatz cmd_1&gt;<b>|</b>&lt;Ersatz cmd_2_1&gt;<b>,</b>...<b>,</b>&lt;Ersatz cmd_2&gt;<b>|...</b></code></dt>
                <dd>ersetzt die Standartwerte des Ger&auml;testatus als direkte Angabe oder Berechnung, die Ersatzstatus von Befehlssequenzen werden durch Kommata, die von Befehlszweigen durch Pipe Zeichen getrennt.</dd>
</br>
        <dt><a href="#DOIF_state">dynamischer Status </a> <code><b>attr</b> &lt;name&gt; <b>state </b>&lt;content&gt;</code></dt>
                <dd>&lt;content&gt; ist das Ergebnis eines Perl-Ausdrucks, DOIF-Syntax ([&lt;device&gt;:&lt;reading&gt;], usw.) triggert bei Event die Berechnung.</dd>
</br>
        <dt><a href="#DOIF_Readings">Erzeugen berechneter Readings </a> <code><b>attr</b> &lt;name&gt; <b>DOIF_Readings </b>&lt;readingname_1&gt;<b>:</b>&lt;content_1&gt;<b>,</b>&lt;readingname_2&gt;<b>:</b>&lt;content_2&gt; ...</code></dt>
                <dd>&lt;content_n&gt; ist das Ergebnis von Perl-Ausdrücken, DOIF-Syntax ([&lt;device&gt;:&lt;reading&gt;], usw.) triggert bei Event die Berechnung.</dd>
</br>
        <dt><a href="#DOIF_notexist">Ersatzwert für nicht existierende Readings oder Status</a> <code><b>attr</b> &lt;name&gt; <b>notexist </b>"&lt;Ersatzwert&gt;"</code></dt>
                <dd></dd>
</br>
        <dt><a href="#DOIF_initialize">Status Initialisierung nach Neustart</a> <code><b>attr</b> &lt;name&gt; <b>intialize </b>&lt;Status nach Neustart&gt;</code></dt>
                <dd></dd>
</br>
        <dt><a href="#DOIF_disable">Ger&auml;t vollst&auml;ndig deaktivieren</a> <code><b>attr</b> &lt;name&gt; <b>disable </b>&lt;<b>0</b>|<b>1</b>&gt;</code></dt>
                <dd>1 deaktiviert das Modul vollst&auml;ndig, 0 aktiviert es.</dd>
</br>
        <dt><a href="#DOIF_checkall">Alle Bedingungen pr&uuml;fen</a> <code><b>attr</b> &lt;name&gt; <b>checkall </b>&lt;<b>event</b>|<b>timer</b>|<b>all</b>&gt;</code></dt>
                <dd><code>event</code> Alle Bedingungen werden geprüft, wenn ein Event-Trigger (Ereignisauslöser) auslöst.<br>
                    <code>timer</code> Alle Bedingungen werden geprüft, wenn ein Timer-Trigger (Zeitauslöser) auslöst.<br>
                    <code>all&nbsp;&nbsp;</code> Alle Bedingungen werden gepr&uuml;ft.<br>
                    Die Befehle nach der ersten wahren Bedingung werden ausgef&uuml;hrt.
                </dd>
</br>
        <dt><a href="#DOIF_addStateEvent">Eindeutige Statuserkennung</a> <code><b>attr</b> &lt;name&gt; <b>addStateEvent </b>&lt;<b>0</b>|<b>ungleich Null</b>&gt;</code></dt>
                <dd>fügt einem Ger&auml;testatus-Event "state:" hinzu. ungleich Null aktiviert, 0 deaktiviert, siehe auch <a href="#addStateEvent">addStateEvent</a></dd>
</br>
        <dt><a href="#DOIF_setList__readingList">Readings, die mit set gesetzt werden k&ouml;nnen</a> <code><b>attr</b> &lt;name&gt; <b>readingList </b>&lt;Reading1&gt;&nbsp;&lt;Reading2&gt; ...</code></dt>
                <dd>fügt zum set-Befehl direkt setzbare, durch Leerzeichen getrennte Readings hinzu. siehe auch <a href="#readingList">readingList</a></dd>
</br>
        <dt><a href="#DOIF_setList__readingList">Readings mit Werteliste und optionaler Widgetangabe</a> <code><b>attr</b> &lt;name&gt; <b>setList </b>&lt;Reading1&gt;<b>:</b>&lang;&lt;Modifier1&gt;<b>,</b>&rang;&lt;Value1&gt;<b>,</b>&lt;Value2&gt;<b>,</b>&lt;...&gt;<b> </b>&lt;Reading2&gt;<b>:</b>&lang;&lt;Modifier2&gt;<b>,</b>&rang;&lt;Value1&gt;<b>,</b>&lt;Value2&gt;<b>,</b>&lt;...&gt; ...</code></dt>
                <dd>fügt einem Reading einen optionalen Widgetmodifier und eine Werteliste (, getrennt) hinzu, siehe auch <a href="#setList">setList</a>, <a href="#widgetOverride">widgetOverride</a>, und <a href="#webCmd">webCmd</a></dd>
<br>
  <dt><a href="#DOIF_uiTable">User Interface f&uuml;r DOIF</a> <code><b>attr</b> &lt;name&gt; <b>uiTable</b> &lang;<b>{</b>&lt;perl code (format specification, template specification, function definition, control variable, ...)&gt;<b>}\n</b>&rang;&lt;template file import, method definition, table definition&gt;</code></dt>
    <dd><u>format specification:</u></dd>
    <dd><code>$TABLE = "&lt;CSS-Attribute&gt;"</code> ergänzt das table-Elemente um CSS-Attribute.</dd>
    <dd><code>$TD{&lt;rows&gt;}{&lt;columns&gt;} = "&lt;HTML Attribute&gt;"</code> ergänzt td-Elemente um HTML-Attribute.</dd>
    <dd><code>$TR{&lt;rows&gt;} = "&lt;HTML Attribute&gt;"</code> ergänzt tr-Elemente um HTML-Attribute.</dd>
    <dd><code>$TC{&lt;columns&gt;} = "&lt;HTML Attribute&gt;"</code> ergänzt zu columns gehörende td-Elemente um HTML-Attribute.</dd>
    <dd><u>template specification:</u></dd>
    <dd><code>$TPL{&lt;name&gt;} = "&lt;Zeichenkette&gt;"</code> speichert ein Template.</dd>
    <dd><u>function definition:</u></dd>
    <dd><code>sub FUNC_&lt;name&gt; {&lt;function BLOCK&gt;}</code> definiert eine Funktion.</dd>
    <dd><u>control variables:</u></dd>
    <dd><code>$ATTRIBUTESFIRST = 1;</code> organisiert die Detailansicht um.</dd>
    <dd><code>$SHOWNOSTATE = 1;</code> blendet den Status in der Gerätezeile aus.</dd>
    <dd><code>$SHOWNODEVICELINE = "&lt;regex room&gt;";</code> blendet die Gerätezeile aus, wenn &lt;regex room&gt; zum Raumnamen passt, gilt nicht für den Raum <i>Everything</i>.</dd>
    <dd><code>$SHOWNODEVICELINK = 1;</code> schaltet das Ersetzen des Gerätenamen durch einen Link auf die Detailseite aus.</dd>
    <br>
    <dd><u>template file import:</u></dd>
    <dd><code>IMPORT &lt;path with filename&gt;</code> importiert eine Templatedatei.</dd>
    <dd><u>method definition:</u></dd>
    <dd><code>DEF TPL_&lt;name&gt;(&lt;definition with place holder $1,$2 usw.&gt;)</code> erzeugt ein Methodentemplate zur wiederholten Nutzung in der Tabellendefinition.</dd>
    <dd><u>table definition:</u></dd>
    <dd>Schreiben die nachstehenden Elemente HTML-Code in die Tabellenzelle, so wird er interpretiert.</dd>
    <dd><code>&crarr;</code> oder <code>&crarr;&crarr;</code> trennt Tabellenzeilen.</dd>
    <dd><code>|</code> oder <code>|&crarr;</code> trennt Tabellenzellen.</dd>
    <dd><code>&gt;&crarr;</code> oder <code>,&crarr;</code> sind zur Textstrukturierung zugelassen.</dd>
    <dd><code>WID([&lt;device&gt;:&lt;reading&gt;],"&lt;widget modifier&gt;"&lang;,"&lt;command&gt;"&rang;)</code> bindet ein Widget an &lt;device&gt;:&lt;reading&gt;, &lt;command&gt; steht für <i>set</i> oder <i>setreading</i>, siehe <a href="#widgetOverride"> widgetOverride </a> und <a href="https://wiki.fhem.de/wiki/FHEMWEB/Widgets"> FHEMWEB-Widgets </a></dd>
    <dd><code>STY(&lt;content&gt;,&lt;CSS style attributes&gt;)</code> schreibt den Inhalt von &lt;content&gt; in die Zelle und formatiert ihn mit &lt;CSS style attributes&gt;.</dd>
    <dd><code>&lt;content&gt;</code> schreibt den Inhalt von &lt;content&gt; in die Zelle.</dd>
    <dd>&lt;content&gt; und &lt;CSS style attributes&gt; sind das Ergebnis von Perl-Ausdrücken. Enthalten sie DOIF-Syntax ([&lt;device&gt;:&lt;reading&gt;], usw.), werden sie dynamisch erzeugt.</dd>
    <dd><code>PUP(&lt;DOIF-name to show interface table&gt;, &lt;iconname[@color number]&gt;)</code></dd>
    <dd>gibt ein Link zum Öffnen eines Popup-Fensters zurück.</dd>
    <dd>&lt;DOIF-name to show interface table&gt; Name des DOIF-Gerätes dessen Benutzerschnittstelle angezeigt werden soll.</dd>
    <dd>&lt;iconname[@color number]|string&gt; gibt ein Icon an, wenn das Icon nicht verfügbar ist, wird &lt;string&gt; angezeigt.</dd>
<br>
        <dt><a href="#readingFnAttributes">readingFnAttributes</a></dt>
                <dd></dd>
</dl>
<br>
</ul>
<a name="DOIF_PerlFunktionen_kurz"></a>
<u>Perl-Funktionen</u>
<ul>
  <dl>
    <dt><code>DOIF_hsv(&lt;current value&gt;, &lt;lower value&gt;, &lt;upper value&gt;, &lt;lower HUE value&gt;, &lt;upper HUE value&gt;, &lt;saturation&gt;, &lt;lightness&gt;)</code></dt>
    <dd>gibt eine im HSV-Raum interpolierte HTML Farbnummer zurück, mit Prefix <b>#</b></dd>
    <dd>&lt;current value&gt; aktueller Wert, für den die Farbnummer erzeugt wird.</dd>
    <dd>&lt;lower value&gt; unterer Wert, des Bereiches auf den die Farbnummer skaliert wird.</dd>
    <dd>&lt;upper value&gt; oberer Wert, des Bereiches auf den die Farbnummer skaliert wird.</dd>
    <dd>&lt;lower HUE value&gt; unterer HUE-Wert, der mit dem unteren Wert korrespondiert (0-360).</dd>
    <dd>&lt;upper HUE value&gt; oberer HUE-Wert, der mit dem oberen Wert korrespondiert (0-360).</dd>
    <dd>&lt;saturation&gt; Farbsättigung (0-100).</dd>
    <dd>&lt;lightness&gt; Hellwert (0-100).</dd>
<br>
    <dt><code>DOIF_rgb(&lt;start color number&gt;, &lt;end color number&gt;, &lt;lower value&gt;, &lt;upper value&gt;, &lt;current value&gt;)</code></dt>
    <dd>gibt eine linear interpolierte RGB Farbnummer zurück, abhängig vom Prefix der Start- o. Endfarbnummer mit oder ohne Prefix <b>#</b>.</dd>
    <dd>&lt;start color number&gt; Startfarbnummer des Farbbereiches, mit oder ohne Prefix <b>#</b>.</dd>
    <dd>&lt;end color number&gt; Endfarbnummer des Farbbereiches, mit oder ohne Prefix <b>#</b>.</dd>
    <dd>&lt;lower value&gt; unterer Wert, des Bereiches auf den die Farbnummer skaliert wird.</dd>
    <dd>&lt;upper value&gt; oberer Wert, des Bereiches auf den die Farbnummer skaliert wird.</dd>
    <dd>&lt;current value&gt; aktueller Wert, für den die Farbnummer erzeugt wird.</dd>
<br>
    <dt><code>FW_makeImage(&lt;iconname[@color number]&gt;)</code></dt>
    <dd>gibt HTML-Code zurück, der ein FHEM icon einbindet.</dd>
    <dd>&lt;color number&gt; optionale Farbnummer in Großschreibung, mit oder ohne Prefix <b>#</b>.</dd>
    <dd>weitere Infos im Quelltext von 01_FHEMWEB.pm.</dd>
  </dl>
</ul>
<!-- Ende der Kurzreferenz -->
<br>
<a name="DOIF_Perl_Modus"></a>
<b>Perl Modus</b><br>
<br>
Im Perl-Modus lassen sich insb. komplexere Abläufe innerhalb eines DOIF-Devices in Perl programmieren.
Der Anwender hat mehr Einfluss auf den Ablauf der Steuerung als im FHEM-Modus. Einfache Perlkenntnise werden in diesem Modus vorausgesetzt.
Im Unterschied zum FHEM-Modus, werden für die Steuerung unmittelbar keine Attribute benötigt. DOIF-spezifische Angaben in eckigen Klammern entsprechen vollständig den Angaben im DOIF FHEM-Modus. Deren Syntax kann in der obigen Beschreibung des FHEM-Modus nachgelesen werden.<br>
<br>
Syntax Perl-Modus:<br>
<br>
<ol><code>define &lt;name&gt; DOIF &lt;Blockname&gt; {&lt;Perl mit DOIF-Syntax in eckigen Klammern&gt;} &lt;Blockname&gt; {&lt;Perl mit DOIF-Syntax in eckigen Klammern&gt;} ...</code></ol><br>
<br>
Ein Perlblock wird ausgeführt, wenn dieser, bedingt durch DOIF-spezifischen Angaben in eckigen Klammern innerhalb des Blocks, getriggert wird.
Es wird die vollständige Perl-Syntax unterstützt. Es können beliebig viele Perlblöcke definiert werden. Wird ein Perlblock mit dem Namen "init" benannt, so wird er bereits zum Definitionszeitpunkt ausgeführt. Der Name eines Blocks ist optional.<br>
<br>
FHEM-Befehle werden durch den Aufruf der Perlfunktion <code>fhem"..."</code> ausgeführt. Im Gegensatz zum FHEM-Modus können im Perl-Modus mehrere Blöcke unabhängig voneinander, ausgelöst durch einen Ereignis- oder Zeit-Trigger, ausgeführt werden. So kann die Funktionalität mehrer DOIF-Module im FHEM-Modus innerhalb eines DOIF-Moduls im Perl-Moduls realisiert werden.<br>
<br>
Die Anzahl der eigenen Timer ist im Gegensatz zu einem wait-Timer unbegrenzt.
Zum Zeitpunkt der Definition werden alle DOIF-spezifischen Angaben in Perl übersetzt, zum Zeitpunkt der Ausführung wird nur noch Perl ausgeführt, damit wird maximale Performance gewährleistet.<br>
<br>
<a name="DOIF_Einfache_Anwendungsbeispiele_Perl"></a>
<u>Einfache Anwendungsbeispiele (vgl. <a href="#DOIF_Einfache_Anwendungsbeispiele">Anwendungsbeispiele im FHEM-Modus</a>):</u><ol>
<br>
<code>define di_rc_tv DOIF {if ([remotecontol:"on"]) {fhem"set tv on"} else {fhem"set tv off"}}</code><br>
<br>
<code>define di_clock_radio DOIF {if ([06:30|Mo Di Mi] or [08:30|Do Fr Sa So]) {fhem"set radio on"} elsif ([08:00|Mo Di Mi] or [09:30|Do Fr Sa So]) {fhem"set radio off"}}</code><br>
<br>
<code>define di_lamp DOIF {if ([06:00-09:00] and [sensor:brightness] < 40) {fhem"set lamp:FILTER=STATE!=on on"} else {fhem"set lamp:FILTER=STATE!=off off"}}</code><br>
<br>
</ol>
Bemerkung: Im Gegensatz zum FHEM-Modus arbeitet der Perl-Modus ohne Zustandsauswertung, daher muss der Anwender selbst darauf achten, wiederholdene Ausführungen zu vermeiden (im oberen Beispiel z.B. mit FILTER-Option)<br>
<br>
<b>Spezifische Perl-Funktionen im Perl-Modus</b><br>
<br>
Timer setzen: <code><b>set_Timer(&lt;TimerEvent&gt;, &lt;seconds&gt;)</code></b>, mit &lt;TimerEvent&gt;: beliebige Angabe, sie spezifiziert eindeutig einen Timer und ist gleichzeitig ein Ereignis,
welches nach Ablauf des Timers in FHEM erzeugt wird. Auf dieses Ereignis kann wie üblich mit der DOIF-Syntax durch die Angabe [$SELF:"^&lt;TimerEvent&gt;$"] reagiert werden.
Wird set_Timer mit dem gleichen &lt;TimerEvent&gt vor seinem Ablauf erneut aufgerufen, so wird der laufender Timer gelöscht und neugesetzt.<br>
<br>
Timer holen: <code><b>get_Timer(&lt;TimerEvent&gt;)</code></b>, Returnwert: 0, wenn Timer abgelaufen oder nicht gesetzt ist, sonst Anzahl der Sekunden bis zum Ablauf des Timers<br>
<br>
Laufenden Timer löschen: <code><b>del_Timer(&lt;TimerEvent&gt;)</code></b><br>
<br>
Ein beliebiges FHEM-Event absetzen: <code><b>set_Event(&lt;Event&gt;)</code></b><br>
<br>
Reading schreiben: <code><b>set_Reading(&lt;readingName&gt;,&lt;content&gt;,&lt;trigger&gt;)</code></b>, mit &lt;trigger&gt;: 0 ohne Trigger, 1 mit Trigger<br>
<br>
Es können alle in FHEM vorhanden Funktionen genutzt werden. Größere Perlblöcke können in eigene Funktionen (z. B. in myUtils) ausgelagert werden.
Der Anwender hat die Möglichkeit Instanzvariablen beginnen mit $_ zu nutzen. Sie müssen nicht deklariert werden. Deren Gültigkeitsbereich ist ein definiertes DOIF-Device. Wenn sie nicht vorbelegt werden, gelten sie als nicht definiert. Das lässt sich abfragen mit:<br>
<code>if (defined $_...) ...</code><br>
<br>
Instanzvariablen überleben nicht den Neustart, sie können jedoch im init-Block aus Readings vorbelegt werden.<br>
<br>
Bsp. Vorbelgung einer Instanzvariablen beim Systemstart mit dem Status des Moduls:<br>
<code>init {$_status=ReadingsVal("$SELF","state",0)}</code><br>
alternativ<br>
<code>init {$_status=[?$SELF:state]}</code><br>
<br>
Instanzvariablen lassen sich indizieren, z. B.:<br>
<code>my $i=0;<br>
$_betrag{$i}=100;</code><br>
<br>
Ebenso funktionieren hash-Variablen z. B.: <br>
<code>$_betrag{heute}=100;</code><br>
<br>
Um den aktuellen Status des DOIF-Devices muss sich der Anwender selbst kümmern. Diesen kann er z.B. mit Hilfe der Funktion set_Reading setzen.<br>
<br>
<u>Nutzbare Attribute im Perl-Modus</u><br>
<br>
  <ul>
  <a href="#DOIF_addStateEvent">addStateEvent</a> &nbsp;
  <a href="#DOIF_checkReadingEvent">checkReadingEvent</a> &nbsp;
  <a href="#DOIF_Readings">DOIF_Readings</a> &nbsp;
  <a href="#DOIF_disable">disable</a> &nbsp;
  <a href="#DOIF_initialize">initialize</a> &nbsp;
  <a href="#DOIF_notexist">notexist</a> &nbsp;
  <a href="#DOIF_setList__readingList">readingList</a> &nbsp;
  <a href="#DOIF_setList__readingList">setList</a> &nbsp;
  <a href="#DOIF_startup">startup</a> &nbsp;
  <a href="#DOIF_state">state</a> &nbsp;
  <a href="#DOIF_uiTable">uiTable</a> &nbsp;
  <a href="#DOIF_weekdays">weekdays</a> &nbsp;
  <br><a href="#readingFnAttributes">readingFnAttributes</a> &nbsp;
</ul>
<br>
<b>Weitere Anwendungsbeispiele:</b><br>
<br>
<a name="DOIF_Einknopf_Fernbedienung"></a>
<u>Einknopf-Fernbedienung</u><br>
<br>
Anforderung: Wenn eine Taste innerhalb von zwei Sekunden zwei mal betätig wird, soll der Rollladen nach oben, bei einem Tastendruck nach unten.<br>
<br>
<code>
define di_shutter DOIF {&nbsp;&nbsp;&nbsp;#Perlblock zur Auswertung des Tastendruckes<br>
&nbsp;&nbsp;if (["FS:^on$"] and get_Timer("Timer_shutter")==0){&nbsp;&nbsp;&nbsp;#wenn Taste betätigt wird und kein Timer läuft<br>
&nbsp;&nbsp;&nbsp;&nbsp;set_Timer("Timer_shutter",2)&nbsp;&nbsp;&nbsp;#Timer für zwei Sekunden setzen<br>
&nbsp;&nbsp;} else {&nbsp;&nbsp;&nbsp;#wenn Timer läuft, d.h. ein weitere Tastendruck innerhalb von zwei Sekunden<br>
&nbsp;&nbsp;&nbsp;&nbsp;del_Timer("Timer_shutter")&nbsp;&nbsp;&nbsp;#Timer löschen<br>
&nbsp;&nbsp;&nbsp;&nbsp;fhem"set shutter up";&nbsp;&nbsp;&nbsp;#Rollladen hoch<br>
&nbsp;&nbsp;}<br>
}<br>
{&nbsp;&nbsp;&nbsp;#Perlblock für die Bearbeitung des Timerevents<br>
&nbsp;&nbsp;if ([$SELF:"Timer_shutter"]){&nbsp;&nbsp;&nbsp;#Wenn nach zwei Sekunden Timer abläuft, d.h. nur ein Tastendruck<br>
&nbsp;&nbsp;&nbsp;&nbsp;fhem"set shutter down"&nbsp;&nbsp;&nbsp;#Rollladen runter<br>
&nbsp;&nbsp;}<br>
}<br>
</code>
<br>
<u>Aktion auslösen, wenn innerhalb einer bestimmten Zeitspanne ein Ereignis x mal eintritt</u><br>
<br>
Im folgenden Beispiel wird die Nutzung von Instanzvariablen demonstriert.<br>
<br>
<code>
define di_count DOIF {&nbsp;&nbsp;&nbsp;#Perlblock zur Auswertung des Ereignisses<br>
&nbsp;&nbsp;if (["FS:on"] and get_Timer("Timer_counter")==0){&nbsp;&nbsp;&nbsp;#wenn Ereignis (hier "FS:on") eintritt und kein Timer läuft<br>
&nbsp;&nbsp;&nbsp;&nbsp;$_count=1;&nbsp;&nbsp;&nbsp;#setze count-Variable auf 1<br>
&nbsp;&nbsp;&nbsp;&nbsp;set_Timer("Timer_counter",3600)&nbsp;&nbsp;&nbsp;#setze Timer auf eine Stunde<br>
&nbsp;&nbsp;} else {<br>
&nbsp;&nbsp;&nbsp;&nbsp;$_count++&nbsp;&nbsp;&nbsp;#wenn Timer bereits läuft zähle Ereignis<br>
&nbsp;&nbsp;}<br>
}<br>
{&nbsp;&nbsp;&nbsp;#Perlblock für die Auswertung nach Ablauf des Timers<br>
&nbsp;&nbsp;if ([$SELF:"Timer_counter"]) {&nbsp;&nbsp;&nbsp;#wenn Timer nach einer Stunde abläuft<br>
&nbsp;&nbsp;&nbsp;&nbsp;if ($_count > 10) {Log 3,"count: $_count action"}}&nbsp;&nbsp;&nbsp;#protokolliere im Log die Anzahl der Ereignisse, wenn sie über 10 ist<br>
}<br>
</code><br>
<br>
<a name="DOIF_Treppenhauslicht mit Bewegungsmelder"></a>
<u>Treppenhauslicht mit Bewegungsmelder</u><br>
<br><code>
define di_light DOIF bewegung {&nbsp;&nbsp;&nbsp;#Perlblock namens "bewegung" reagiert auf Bewegung von FS<br>
&nbsp;&nbsp;if (["FS:motion"]) {<br>
&nbsp;&nbsp;&nbsp;&nbsp;if ([?lamp:state] ne "on") {&nbsp;&nbsp;&nbsp;#wenn Lampe aus ist<br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;fhem"set lamp on";&nbsp;&nbsp;&nbsp;#Lampe einschalten<br>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;set_Reading ("state","on",1);&nbsp;&nbsp;&nbsp;#setze Status des DOIF-Moduls auf "on"<br>
&nbsp;&nbsp;&nbsp;&nbsp;}<br>
&nbsp;&nbsp;&nbsp;&nbsp;set_Timer("lamp_off",30);&nbsp;&nbsp;&nbsp;#Timer wird gesetzt bzw. verlängert<br>
&nbsp;&nbsp;}<br>
}<br>
ausschalten {&nbsp;&nbsp;&nbsp;#Perlblock namens "ausschalten" reagiert auf Trigger vom des Timers "lamp_off"<br>
&nbsp;&nbsp;if ([$SELF:"lamp_off"]) {&nbsp;&nbsp;&nbsp;#Wenn Timer lamp_off abläuft<br>
&nbsp;&nbsp;&nbsp;&nbsp;fhem"set lamp off";&nbsp;&nbsp;&nbsp;#schalte Lampe aus<br>
&nbsp;&nbsp;&nbsp;&nbsp;set_Reading ("state","off",1);&nbsp;&nbsp;&nbsp;#setze Status des DOIF-Modus auf "off"<br>
&nbsp;&nbsp;}<br>
}<br></code>
<br>
<a name="DOIF_Fenster_offen_Meldung"></a>
<u>Verzögerte Fenster-offen-Meldung mit Wiederholung für mehrere Fenster</u><br>
<br>
<code>define di_window DOIF { <br>
&nbsp;&nbsp;if (["_window$:open"]) {&nbsp;&nbsp;&nbsp;#wenn ein Fensterdevice endend mit "_window" geöffnet wird<br>
&nbsp;&nbsp;&nbsp;&nbsp;set_Timer ("WINDOW_$DEVICE",600)&nbsp;&nbsp;&nbsp;#setze einen Timer auf 10 Minuten<br>
&nbsp;&nbsp;}<br>
}<br>
{&nbsp;&nbsp;&nbsp;#Timer löschen, wenn Fenster geschlossen wird<br>
&nbsp;&nbsp;if (["_window$:closed"]) {<br>
&nbsp;&nbsp;&nbsp;&nbsp;del_Timer ("WINDOW_$DEVICE")<br>
&nbsp;&nbsp;}<br>
}<br>
{&nbsp;&nbsp;&nbsp;#Auswertung eines Timers<br>
&nbsp;&nbsp;if (["^$SELF:^WINDOW_"]) {&nbsp;&nbsp;&nbsp;#wenn ein Timerevent kommt<br>
&nbsp;&nbsp;&nbsp;&nbsp;my ($window,$device)=split("_","$EVENT");&nbsp;&nbsp;&nbsp;#bestimme das Device aus dem Timerevent "WINDOW_$DEVICE"<br>
&nbsp;&nbsp;&nbsp;&nbsp;Log 3,"Fenster offen, bitte schließen: $device";&nbsp;&nbsp;&nbsp;#Meldung wird protokolliert<br>
&nbsp;&nbsp;&nbsp;&nbsp;set_Timer ("WINDOW_$device",1800)&nbsp;&nbsp;&nbsp;#setze einen neuen Timer für das Fenster für eine erneute Meldung in 30 Minuten<br>
&nbsp;&nbsp;}<br>
}<br>
</code>
</ul>
=end html_DE
=cut
