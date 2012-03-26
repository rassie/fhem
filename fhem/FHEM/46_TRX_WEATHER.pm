#################################################################################
# 46_TRX_WEATHER.pm
# Module for FHEM to decode weather sensor messages for RFXtrx
#
# The following devices are implemented to be received:
#
# temperature sensors (TEMP):
# * "THR128" 	is THR128/138, THC138
# * "THGR132N" 	is THC238/268,THN132,THWR288,THRN122,THN122,AW129/131
# * "THWR800" 	is THWR800
# * "RTHN318"	is RTHN318
# * "TX3_T" 	is LaCrosse TX3, TX4, TX17
#
# temperature/humidity sensors (TEMPHYDRO):
# * "THGR228N"	is THGN122/123, THGN132, THGR122/228/238/268
# * "THGR810"	is THGR810
# * "RTGR328"	is RTGR328
# * "THGR328"	is THGR328
# * "WTGR800_T"	is WTGR800
# * "THGR918"	is THGR918, THGRN228, THGN500
# * "TFATS34C"	is TFA TS34C
# * "WT450H"	is UPM WT450H
#
# temperature/humidity/pressure sensors (TEMPHYDROBARO):
# * "BTHR918"	is BTHR918
# * "BTHR918N"	is BTHR918N, BTHR968
#
# rain gauge sensors (RAIN):
# * "RGR918" 	is RGR126/682/918
# * "PCR800"	is PCR800
# * "TFA_RAIN"	is TFA
#
# wind sensors (WIND):
# * "WTGR800_A" is WTGR800
# * "WGR800_A"	is WGR800
# * "WGR918_A"	is STR918, WGR918
# * "TFA_WIND"	is TFA
#
# derived from 41_OREGON.pm
#
#  Willi Herzig, 2012
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
##################################
#
# values for "set global verbose"
# 4: log unknown protocols
# 5: log decoding hexlines for debugging
#
# $Id: $
package main;

use strict;
use warnings;

# Hex-Debugging into READING hexline? YES = 1, NO = 0
my $TRX_HEX_debug = 0;

my $time_old = 0;

sub
TRX_WEATHER_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^[\x38-\x78].*";
  #$hash->{Match}     = "^[^\x30]";
  $hash->{DefFn}     = "TRX_WEATHER_Define";
  $hash->{UndefFn}   = "TRX_WEATHER_Undef";
  $hash->{ParseFn}   = "TRX_WEATHER_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 loglevel:0,1,2,3,4,5,6";

}

#####################################
sub
TRX_WEATHER_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

	my $a = int(@a);
	#print "a0 = $a[0]";
  return "wrong syntax: define <name> TRX_WEATHER code" if(int(@a) != 3);

  my $name = $a[0];
  my $code = $a[2];

  $hash->{CODE} = $code;
  #$modules{TRX_WEATHER}{defptr}{$name} = $hash;
  $modules{TRX_WEATHER}{defptr}{$code} = $hash;
  AssignIoPort($hash);

  return undef;
}

#####################################
sub
TRX_WEATHER_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{TRX_WEATHER}{defptr}{$name});
  return undef;
}



#########################################
# From xpl-perl/lib/xPL/Util.pm:
sub hi_nibble {
  ($_[0]&0xf0)>>4;
}
sub lo_nibble {
  $_[0]&0xf;
}
sub nibble_sum {
  my $c = $_[0];
  my $s = 0;
  foreach (0..$_[0]-1) {
    $s += hi_nibble($_[1]->[$_]);
    $s += lo_nibble($_[1]->[$_]);
  }
  $s += hi_nibble($_[1]->[$_[0]]) if (int($_[0]) != $_[0]);
  return $s;
}

# --------------------------------------------
# From xpl-perl/lib/xPL/RF/Oregon.pm:
# This function creates a simple key from a device type and message
# length (in bits).  It is used to as the index for the parts table.
sub type_length_key {
  ($_[0] << 8) + $_[1]
}

# --------------------------------------------
# sensor types 

my %types =
  (
   # TEMP
   type_length_key(0x50, 0x08) =>
   {
    part => 'TEMP', method => \&common_temp,
   },
   # HYDRO
   type_length_key(0x51, 0x08) =>
   {
    part => 'HYDRO', method => \&common_hydro,
   },
   # TEMP HYDRO
   type_length_key(0x52, 0x0a) =>
   {
    part => 'TEMPHYDRO', method => \&common_temphydro,
   },
   # TEMP HYDRO BARO
   type_length_key(0x54, 0x0d) =>
   {
    part => 'TEMPHYDROBARO', method => \&common_temphydrobaro,
   },
   # RAIN
   type_length_key(0x55, 0x0b) =>
   {
    part => 'RAIN', method => \&common_rain,
   },
   # WIND
   type_length_key(0x56, 0x10) =>
   {
    part => 'WIND', method => \&common_anemometer,
   },
  );


# --------------------------------------------

#my $DOT = q{.};
# Important: change it to _, because FHEM uses regexp
my $DOT = q{_};

my @TRX_WEATHER_winddir_name=("N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW");

# --------------------------------------------
# The following functions are changed:
#	- some parameter like "parent" and others are removed
#	- @res array return the values directly (no usage of xPL::Message)

sub temperature {
  my ($bytes, $dev, $res, $off) = @_;

  my $temp =
    (
    (($bytes->[$off] & 0x80) ? -1 : 1) *
        (($bytes->[$off] & 0x7f)*256 + $bytes->[$off+1]) 
    )/10;

  push @$res, {
       		device => $dev,
       		type => 'temp',
       		current => $temp,
		units => 'Grad Celsius'
  	}

}

sub humidity {
  my ($bytes, $dev, $res, $off) = @_;
  my $hum = $bytes->[$off];
  my $hum_str = ['dry', 'comfortable', 'normal',  'wet']->[$bytes->[$off+1]];
  push @$res, {
		device => $dev,
                type => 'humidity',
                current => $hum,
                string => $hum_str,
		units => '%'
	}
}

sub pressure {
  my ($bytes, $dev, $res, $off) = @_;

  #my $offset = 795 unless ($offset);
  my $hpa = ($bytes->[$off])*256 + $bytes->[$off+1];
  my $forecast = { 0x00 => 'noforecast',
		   0x01 => 'sunny',
                   0x02 => 'partly',
                   0x03 => 'cloudy',
                   0x04 => 'rain',
                 }->{$bytes->[$off+2]} || 'unknown';
  push @$res, {
		device => $dev,
                type => 'pressure',
                current => $hpa,
                units => 'hPa',
                forecast => $forecast,
   	}
}

sub simple_battery {
  my ($bytes, $dev, $res, $off) = @_;

  my $battery;

  my $battery_level = $bytes->[$off] & 0x0f;
  if ($battery_level == 0x9) { $battery = 'ok'}
  elsif ($battery_level == 0x0) { $battery = 'low'}
  else { 
	$battery = sprintf("unknown-%02x",$battery_level);
  }

  push @$res, {
		device => $dev,
		type => 'battery',
		current => $battery,
	}
}

sub battery {
  my ($bytes, $dev, $res, $off) = @_;

  my $battery;

  my $battery_level = ($bytes->[$off] & 0x0f) + 1;

  if ($battery_level > 5) {
    $battery = sprintf("ok %d0%%",$battery_level);
  } else {
    $battery = sprintf("low %d0%%",$battery_level);
  }

  push @$res, {
		device => $dev,
		type => 'battery',
		current => $battery,
	}
}


my @uv_str =
  (
   qw/low low low/, # 0 - 2
   qw/medium medium medium/, # 3 - 5
   qw/high high/, # 6 - 7
   'very high', 'very high', 'very high', # 8 - 10
  );

sub uv_string {
  $uv_str[$_[0]] || 'dangerous';
}

# Test if to use longid for device type
sub use_longid {
  my ($longids,$dev_type) = @_;

  return 0 if ($longids eq "");
  return 0 if ($longids eq "0");

  return 1 if ($longids eq "1");
  return 1 if ($longids eq "ALL");

  return 1 if(",$longids," =~ m/,$dev_type,/);

  return 0;
}

# ------------------------------------------------------------
#
sub common_anemometer {
    	my $type = shift;
	my $longids = shift;
    	my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  #Log 1,"subtype=$subtype";
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "WTGR800_A",
	0x02 => "WGR800_A",
	0x03 => "WGR918_A",
	0x04 => "TFA_WIND",
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log 1,"TRX_WEATHER: common_anemometer error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  #my $seqnbr = sprintf "%02x", $bytes->[2];
  #Log 1,"seqnbr=$seqnbr";

  my $dev_str = $dev_type;
  if (use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  my $dir = $bytes->[5]*256 + $bytes->[6];
  my $dirname = $TRX_WEATHER_winddir_name[$dir/22.5];

  my $avspeed = $bytes->[7]*256 + $bytes->[8];
  my $speed = $bytes->[9]*256 + $bytes->[10];

 	push @res, {
                               device => $dev_str,
                               type => 'speed',
                               current => $speed,
                               average => $avspeed,
                               units => 'mps',
                              } , {
                               device => $dev_str,
                               type => 'direction',
                               current => $dir,
                               string => $dirname,
                               units => 'degrees',
                              } 
	;
  simple_battery($bytes, $dev_str, \@res, 15);

  return @res;
}


# -----------------------------
sub common_temp {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  #Log 1,"subtype=$subtype";
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "THR128",
	0x02 => "THGR132N", # was THGR228N,
	0x03 => "THWR800",
	0x04 => "RTHN318",
	0x05 => "TX3_T", # LaCrosse TX3
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log 1,"RFX_WEATHER: common_temp error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  #my $seqnbr = sprintf "%02x", $bytes->[2];
  #Log 1,"seqnbr=$seqnbr";

  my $dev_str = $dev_type;
  if (use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }
  #Log 1,"dev_str=$dev_str";

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  temperature($bytes, $dev_str, \@res, 5); 
  simple_battery($bytes, $dev_str, \@res, 7);
  return @res;
}

# -----------------------------
sub common_hydro {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  #Log 1,"subtype=$subtype";
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "TX3_H", # LaCrosse TX3
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log 1,"RFX_WEATHER: common_hydro error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  my $dev_str = $dev_type;
  if (use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }
  #Log 1,"dev_str=$dev_str";

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  humidity($bytes, $dev_str, \@res, 5); 
  simple_battery($bytes, $dev_str, \@res, 7);
  return @res;
}

# -----------------------------
sub common_temphydro {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  #Log 1,"subtype=$subtype";
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "THGR228N", # THGN122/123, THGN132, THGR122/228/238/268
	0x02 => "THGR810",
	0x03 => "RTGR328",
	0x04 => "THGR328",
	0x05 => "WTGR800_T",
	0x06 => "THGR918",
	0x07 => "TFATS34C",
	0x08 => "WT450H",
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log 1,"RFX_WEATHER: common_temphydro error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  my $dev_str = $dev_type;
  if (use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }
  #Log 1,"dev_str=$dev_str";

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  temperature($bytes, $dev_str, \@res, 5);
  humidity($bytes, $dev_str, \@res, 7); 
  simple_battery($bytes, $dev_str, \@res, 9);
  return @res;
}

# -----------------------------
sub common_temphydrobaro {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;

  my $subtype = sprintf "%02x", $bytes->[1];
  #Log 1,"subtype=$subtype";
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "BTHR918",
	0x02 => "BTHR918N",
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log 1,"RFX_WEATHER: common_temphydrobaro error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  my $dev_str = $dev_type;
  if (use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }
  #Log 1,"dev_str=$dev_str";

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  temperature($bytes, $dev_str, \@res, 5); 
  humidity($bytes, $dev_str, \@res, 7); 
  pressure($bytes, $dev_str, \@res, 9);
  simple_battery($bytes, $dev_str, \@res, 12);
  return @res;
}

# -----------------------------
sub common_rain {
  my $type = shift;
  my $longids = shift;
  my $bytes = shift;


  my $subtype = sprintf "%02x", $bytes->[1];
  #Log 1,"subtype=$subtype";
  my $dev_type;

  my %devname =
    (	# HEXSTRING => "NAME"
	0x01 => "RGR918",
	0x02 => "PCR800",
	0x03 => "TFA_RAIN",
  );

  if (exists $devname{$bytes->[1]}) {
  	$dev_type = $devname{$bytes->[1]};
  } else {
  	Log 1,"RFX_WEATHER: common_rain error undefined subtype=$subtype";
  	my @res = ();
  	return @res;
  }

  my $dev_str = $dev_type;
  if (use_longid($longids,$dev_type)) {
  	$dev_str .= $DOT.sprintf("%02x", $bytes->[3]);
  }
  if ($bytes->[4] > 0) {
  	$dev_str .= $DOT.sprintf("%d", $bytes->[4]);
  }
  #Log 1,"dev_str=$dev_str";

  my @res = ();

  # hexline debugging
  if ($TRX_HEX_debug) {
    my $hexline = ""; for (my $i=0;$i<@$bytes;$i++) { $hexline .= sprintf("%02x",$bytes->[$i]);} 
    push @res, { device => $dev_str, type => 'hexline', current => $hexline, units => 'hex', };
  }

  my $rain = $bytes->[5]*256 + $bytes->[6];
  my $train = $bytes->[7]*256*256 + $bytes->[8]*256 + $bytes->[9];

  push @res, {
                               device => $dev_str,
                               type => 'rain',
                               current => $rain,
                               units => 'mm/h',
                              } ;
  push @res, {
                               device => $dev_str,
                               type => 'train',
                               current => $train,
                               units => 'mm',
                              };
  battery($bytes, $dev_str, \@res, 10);
  return @res;
}

sub raw {
  $_[0]->{raw} or $_[0]->{raw} = pack 'H*', $_[0]->{hex};
}

# -----------------------------

sub
TRX_WEATHER_Parse($$)
{
  my ($iohash, $hexline) = @_;

  #my $hashname = $iohash->{NAME};
  #my $longid = AttrVal($hashname,"longids","");
  #Log 1,"2: name=$hashname, attr longids = $longid";

  my $longids = 0;
  if (defined($attr{$iohash->{NAME}}{longids})) {
  	$longids = $attr{$iohash->{NAME}}{longids};
  	#Log 1,"0: attr longids = $longids";
  }

  my $time = time();
  # convert to binary
  my $msg = pack('H*', $hexline);
  if ($time_old ==0) {
  	Log 5, "TRX_WEATHER: decoding delay=0 hex=$hexline";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log 5, "TRX_WEATHER: decoding delay=$time_diff hex=$hexline";
  }
  $time_old = $time;

  # convert string to array of bytes. Skip length byte
  my @rfxcom_data_array = ();
  foreach (split(//, substr($msg,1))) {
    push (@rfxcom_data_array, ord($_) );
  }

  my $num_bytes = ord($msg);

  if ($num_bytes < 3) {
    return;
  }

  my $type = $rfxcom_data_array[0];

  my $sensor_id = unpack('H*', chr $type);
  #Log 1, "TRX_WEATHER: sensor_id=$sensor_id";

  my $key = type_length_key($type, $num_bytes);

  my $rec = $types{$key} || $types{$key&0xfffff};
  unless ($rec) {
#Log 3, "TRX_WEATHER: ERROR: Unknown sensor_id=$sensor_id num_bytes=$num_bytes message='$hexline'.";
    Log 4, "TRX_WEATHER: ERROR: Unknown sensor_id=$sensor_id message='$hexline'";
Log 1, "TRX_WEATHER: ERROR: Unknown sensor_id=$sensor_id message='$hexline'";
    return "TRX_WEATHER: ERROR: Unknown sensor_id=$sensor_id \n";
  }
  
  my $method = $rec->{method};
  unless ($method) {
    Log 4, "TRX_WEATHER: Possible message from Oregon part '$rec->{part}'";
    Log 4, "TRX_WEATHER: sensor_id=$sensor_id";
    return;
  }

  my @res;

  if (! defined(&$method)) {
    Log 4, "TRX_WEATHER: Error: Unknown function=$method. Please define it in file $0";
    Log 4, "TRX_WEATHER: sensor_id=$sensor_id\n";
    return "TRX_WEATHER: Error: Unknown function=$method. Please define it in file $0";
  } else {
    #Log 1, "TRX_WEATHER: parsing sensor_id=$sensor_id message='$hexline'";
    @res = $method->($rec->{part}, $longids, \@rfxcom_data_array);
  }

  # get device name from first entry
  my $device_name = $res[0]->{device};
  #Log 1, "device_name=$device_name";

  if (! defined($device_name)) {
    Log 4, "TRX_WEATHER: error device_name undefined\n";
    return "TRX_WEATHER: Error: Unknown devicename.";
  }

  my $def = $modules{TRX_WEATHER}{defptr}{"$device_name"};
  if(!$def) {
	Log 3, "TRX_WEATHER: Unknown device $device_name, please define it";
    	return "UNDEFINED $device_name TRX_WEATHER $device_name";
  }
  # Use $def->{NAME}, because the device may be renamed:
  my $name = $def->{NAME};
  #Log 1, "name=$new_name";

  my $n = 0;
  my $tm = TimeNow();

  my $i;
  my $val = "";
  my $sensor = "";
  foreach $i (@res){
 	#print "!> i=".$i."\n";
	#printf "%s\t",$i->{device};
	if ($i->{type} eq "temp") { 
			#printf "Temperatur %2.1f %s ; ",$i->{current},$i->{units};
			$val .= "T: ".$i->{current}." ";

			$sensor = "temperature";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};
  	} 
	elsif ($i->{type} eq "humidity") { 
			#printf "Luftfeuchtigkeit %d%s, %s ;",$i->{current},$i->{units},$i->{string};
			$val .= "H: ".$i->{current}." ";

			$sensor = "humidity";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "battery") { 
			#printf "Batterie %d%s; ",$i->{current},$i->{units};
			my $tmp_battery = $i->{current};
			my @words = split(/\s+/,$i->{current});
			$val .= "BAT: ".$words[0]." "; #user only first word

			$sensor = "battery";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "pressure") { 
			#printf "Luftdruck %d %s, Vorhersage=%s ; ",$i->{current},$i->{units},$i->{forecast};
			# do not add it due to problems with hms.gplot
			$val .= "P: ".$i->{current}." ";

			$sensor = "pressure";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;

			$sensor = "forecast";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{forecast};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{forecast};;
	}
	elsif ($i->{type} eq "speed") { 
			$val .= "W: ".$i->{current}." ";
			$val .= "WA: ".$i->{average}." ";

			$sensor = "wind_speed";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;

			$sensor = "wind_avspeed";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{average};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{average};;
	}
	elsif ($i->{type} eq "direction") { 
			$val .= "WD: ".$i->{current}." ";
			$val .= "WDN: ".$i->{string}." ";

			$sensor = "wind_dir";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current} . " " . $i->{string};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current} . " " . $i->{string};;
	}
	elsif ($i->{type} eq "rain") { 
			$val .= "RR: ".$i->{current}." ";

			$sensor = "rain_rate";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "train") { 
			$val .= "TR: ".$i->{current}." ";

			$sensor = "rain_total";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "flip") { 
			$val .= "F: ".$i->{current}." ";

			$sensor = "rain_flip";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	elsif ($i->{type} eq "uv") { 
			$val .= "UV: ".$i->{current}." ";
			$val .= "UVR: ".$i->{risk}." ";

			$sensor = "uv_val";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;

			$sensor = "uv_risk";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{risk};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{risk};;
	}
	elsif ($i->{type} eq "hexline") { 
			$sensor = "hexline";			
			$def->{READINGS}{$sensor}{TIME} = $tm;
			$def->{READINGS}{$sensor}{VAL} = $i->{current};
			$def->{CHANGED}[$n++] = $sensor . ": " . $i->{current};;
	}
	else { 
			print "\nTRX_WEATHER: Unknown: "; 
			print "Type: ".$i->{type}.", ";
			print "Value: ".$i->{current}."\n";
	}
  }

  if ("$val" ne "") {
    # remove heading and trailing space chars from $val
    $val =~ s/^\s+|\s+$//g;

    $def->{STATE} = $val;
    $def->{TIME} = $tm;
    $def->{CHANGED}[$n++] = $val;
  }

  #
  #$def->{READINGS}{state}{TIME} = $tm;
  #$def->{READINGS}{state}{VAL} = $val;
  #$def->{CHANGED}[$n++] = "state: ".$val;

  DoTrigger($name, undef);

  return $val;
}

1;
