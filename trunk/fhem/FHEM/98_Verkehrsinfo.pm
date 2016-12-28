# $Id$
############################################################################
#
# 98_Verkehrsinfo.pm
#
# Copyright (C) 2016 by Martin Schubert
# e-mail: martin@dermschub.de
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or 
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
############################################################################


############################################################################
#
# Changelog:
# 2016-12-26, v2.1
# Bugfix:  update state with readings update
# CHANGE:  update commandref with link to readingFn-Attributen
#
# Changelog:
# 2016-12-13, v2.0RC1
# Bugfix:  Bugfix Hessenschau Message
#
# 2016-11-17, v2.0
# CHANGE:  Module change to HttpNonBlocking
# CHANGE:  remove requirement perl-module json
# CHANGE:  update commandref
#
# 2016-11-10, v1.9
# Bugfix:  hessenschau.de, messages end with a point
#
# Changelog:
# 2016-10-24, v1.8
# Bugfix:  hessenschau.de, messages end with a point
#
# 2016-10-23, v1.7RC2
# CHANGE:  Module change to NonBlocking
# CHANGE:  Code optimization
# CHANGE:  update commandref
# Bugfix:  hessenschau.de, Cant call method "as_trimmed_text" fixed
#
# 2016-08-17, v1.7RC1
# Feature: New Reading for humanly readable message
# Feature: New Attribut for Messageformat
# Feature: New Attribut for Sorting added
# CHANGE:  State Value
# CHANGE:  LWP::Simple replace to HttpUtils
# CHANGE:  check if HTML::TreeBuilder::XPath is installed
# CHANGE:  update commandref
#
# 2016-08-17, v1.6
# Bugfix: verkehrsinfo.de, Display of the zone has been corrected
# Bugfix: Characterset has been corrected
#
# 2016-08-16, v1.5
# Bugfix: verkehrsinfo.de, URL changed to the new address
#
# 2016-08-04, v1.4
# Bugfix: hessenschau.de, Message Sperrung added
#
# 2016-07-29, v1.3
# Bugfix: hessenschau.de, Message Warnung added
#
# 2016-07-11, v1.2
# Feature: Quelle http://hessenschau.de/verkehr/index.html added
#
# 2016-07-03, v1.1
# Bugfix:  Check if a valid URL was passed
# Feature: Include Filterattribut added, regex available, Pipe as delimiter
# Feature: Exclude Filterattribut added, regex available, Pipe as delimiter
#
# 2016-06-29, v1.0
# Initzial Version
# 
############################################################################
package main;
use strict;
use warnings;
#use Encode qw(decode encode);
use HttpUtils;

my $missingModul = "";
eval "use HTML::TreeBuilder::XPath;1" or $missingModul .= "HTML::TreeBuilder::XPath ";


my %Verkehrsinfo_gets = (
	"update" => "noArg",
	"info" => "noArg"
);

#my $encode = 'UTF-8';

sub Verkehrsinfo_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'Verkehrsinfo_Define';
    $hash->{UndefFn}    = 'Verkehrsinfo_Undef';
    $hash->{SetFn}      = 'Verkehrsinfo_Set';
    $hash->{GetFn}      = 'Verkehrsinfo_Get';
    $hash->{AttrFn}     = 'Verkehrsinfo_Attr';
    $hash->{ReadFn}     = 'Verkehrsinfo_Read';

    $hash->{AttrList} =
         "filter_exclude filter_include orderby "
		. "msg_format:road,head,both "
        . $readingFnAttributes;
}

sub Verkehrsinfo_Define($$) {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
    
    if(int(@param) < 4) {
        return "too few parameters: define <name> Verkehrsinfo <url> <interval>";
    }
    
    $hash->{name}  = $param[0];
    $hash->{url}  = $param[2];
    $hash->{Interval} = $param[3];
	
	# check Module is installed
	if ( $missingModul ) {
      my $returnmsg = "Cannot define $hash->{name} device. Perl modul $missingModul is missing.";
	  Log3 $hash->{name}, 1, $returnmsg;
      return $returnmsg;
    }
	
	# check if the url is ok
	if ($hash->{url} !~ /verkehrsinfo\.de\/httpsmobil\/index\.php/ &&
	$hash->{url} !~ /hessenschau\.de\/verkehr\/index\.html/){
		my $returnmsg = "Diese URL wird nicht unterstützt. Bitte schauen Sie in die Modulbeschreibung.";
		Log3 $hash->{name}, 1, $returnmsg;
		return $returnmsg;
	}
	
	# get Zone name
	if ($hash->{url} =~ /verkehrsinfo.de/i){
		my $param = {
                    url        => "https://www.verkehrsinfo.de/httpsmobil/index.php?c=1&lat=&lon=",
                    timeout    => 5,
                    hash       => $hash,
                    callback   =>  \&Verkehrsinfo_HttpNbDefineZone
                };
		HttpUtils_NonblockingGet($param);
	}
	elsif ($hash->{url} =~ /hessenschau.de/i) {
		readingsSingleUpdate( $hash, "zone", "Hessen", 1 );
	}
	
	InternalTimer(gettimeofday()+4, "Verkehrsinfo_GetUpdate", $hash, 0);
	
	readingsSingleUpdate($hash, "state",  'initialized',1 );
    
    return undef;
}

# recieve zone from www http nonblocking
sub Verkehrsinfo_HttpNbDefineZone($) {
	my ($param, $err, $content) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
	
	Log3 $hash, 4, "Verkehrsinfo: ($name) Verkehrsinfo_HttpNbDefineZone start";
	
	if($err ne "")    {
        Log3 $name, 3, "error while requesting ".$param->{url}." - $err";
		readingsSingleUpdate($hash, "state",  'ERROR Update Zone ' . FmtDateTime(time()), 1);
    }
	
	elsif($content ne "")
    {
	
		my $tree = HTML::TreeBuilder->new;
		my @arrzone = split(/[=&]/, $hash->{url});
		my $zone = '';
		if ($arrzone[2] eq "bl")
		{
		
			# prepare HTML Code
			$content =~ s/getLocation\(\)\;//g;
			#####################
			$tree->parse($content);	#<-- Testen !
			#$tree->parse(encode($encode, $content));
			$zone = $tree->findnodes('//button[contains(@onclick, "'.$arrzone[3].'")]')->[0]->as_trimmed_text;
			$zone =~ s/\s\[.*\]//;
		}
		else {
			$zone = $arrzone[3];
		}
		readingsSingleUpdate( $hash, "zone", $zone, 1 );
	}
	Log3 $hash, 4, "Verkehrsinfo: ($name) Verkehrsinfo_HttpNbDefineZone done";
}

sub Verkehrsinfo_Undef($$) {
    my ($hash, $arg) = @_; 
    RemoveInternalTimer($hash);
    return undef;
}

sub Verkehrsinfo_Get($@) {
	my ($hash, @param) = @_;
	
	return '"get Verkehrsinfo" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	if(!$Verkehrsinfo_gets{$opt}) {
		return "Unknown argument $opt, choose one of info:noArg";
	}
	
	if ($opt eq "info"){

		return Verkehrsinfo_GetData($hash->{NAME});
	}
	
}

sub Verkehrsinfo_Set($@) {
	my ($hash, @param) = @_;
	
	return '"set Verkehrsinfo" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	my $value = join("", @param);
	
		
	if(!defined($Verkehrsinfo_gets{$opt})) {
		return "Unknown argument $opt, choose one of update:noArg";
	}

	if ($opt eq "update"){
		Verkehrsinfo_GetUpdate($hash);
		return "Update is runing";
	}	
}

sub Verkehrsinfo_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	if($cmd eq "set") {
        if($attr_name eq "filter_exclude" || $attr_name eq "filter_include") {
			eval { qr/$attr_value/ };
			if ($@) {
				my $err = "Verkehrsinfo: Ungültiger Filter in attr $name $attr_name $attr_value: $@";
				Log3 $name, 3, $err;
				return $err;
			}
		}
		elsif($attr_name eq "msg_format" && $attr_value !~ "road|head|both") {
			my $err = "Verkehrsinfo: Ungültiges Message Format in attr $name $attr_name $attr_value: $@";
			Log3 $name, 3, $err;
			return $err;
		}
		elsif($attr_name eq "msg_format" && InternalVal($name, 'url', '') =~ 'hessenschau.de/verkehr') {
			my $err = "Verkehrsinfo: Message Format ist für " . InternalVal($name, 'url', '') . " nicht Verfügbar";
			Log3 $name, 3, $err;
			return $err;
		}
	}
	return undef;
}

# recieve data from www http nonblocking
sub Verkehrsinfo_HttpNbUpdateData ($) {
	my ($param, $err, $content) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
	
	my $headline;
	my @toc;
	my $message = '';
	my $message_zone = '';
	my $message_head = '';
	my $dataarray;
	
	Log3 $hash, 4, "Verkehrsinfo: ($name) Verkehrsinfo_HttpNbUpdateData start";
	
	if($err ne "")    {
        Log3 $name, 3, "error while requesting ".$param->{url}." - $err";
		readingsSingleUpdate($hash, "state",  'ERROR Update Readings ' . FmtDateTime(time()), 1);
    }
	
	elsif($content ne "")
	{
		# read attribut filter
		my $filterexclude = AttrVal($name,"filter_exclude","");
		my $filterinclude = AttrVal($name,"filter_include",".*");
		my $orderby = AttrVal($name,"orderby","");

		my $tree = HTML::TreeBuilder->new;

		my $i = 1;
		
		##################
		# verkehrsinfo.de
		##################
		if ($hash->{url} =~ /verkehrsinfo.de/i){
		
			# prepare HTML Code
			$content =~ s/getLocation\(\)\;//g;
			
			$tree->parse($content);

			@toc = $tree->findnodes('//div[contains(@class, "panel-body")]/ul/li');
			shift(@toc); # delete advertising
			
			for my $el ( Verkehrsinfo_hf_orderby($orderby, @toc) ) {
				if (grep(!/$filterexclude/i, $el->as_trimmed_text) && grep(/$filterinclude/i, $el->as_trimmed_text)){
					if (exists $el->findnodes('div/div')->[0] && exists $el->findnodes('div')->[1]->findnodes('span')->[0] && exists $el->findnodes('div')->[1]->findnodes('span')->[1]){
						$dataarray->{"e_".$i."_road"} = $el->findnodes('div/div')->[0]->as_trimmed_text;
						$dataarray->{"e_".$i."_head"} = $el->findnodes('div')->[1]->findnodes('span')->[0]->as_trimmed_text;
						$dataarray->{"e_".$i."_msg"} = $el->findnodes('div')->[1]->findnodes('span')->[1]->as_trimmed_text;
						$message .= (AttrVal($name,"msg_format","") =~ "road|both") ? $el->findnodes('div/div')->[0]->as_trimmed_text .', ' : '';
						$message .= (AttrVal($name,"msg_format","") =~ "head|both") ? $el->findnodes('div')->[1]->findnodes('span')->[1]->as_trimmed_text .', ' : '';
						$message .= $el->findnodes('div')->[1]->findnodes('span')->[1]->as_trimmed_text .'. ' ;
						$i++;
					}
					else{
						Log3 $hash, 3, "Verkehrsinfo: ($name) Verkehrsinfo_HttpNbUpdateData DataNodeElements not found";
					}
				}
			}
			$message =~ s/ \(.*?\)//g;  # Remove number of exits
			$message_zone = (ReadingsVal($name, 'zone', '') =~ /[0-9]/i) ? ' für die ' : ' für ';
			$message_zone .= ReadingsVal($name, 'zone', '');
		}
		
		##################
		# hessenschau.de
		##################
		elsif ($hash->{url} =~ /hessenschau.de/i) {
			
			# prepare HTML Code
			$content =~ s/<\/title>/<\/span>/g;
			$content =~ s/<title id="iconTitle--[0-9]+">/<span>/g;
			$content =~ s/<text/<p/g;
			$content =~ s/<\/text>/<\/p>/g;
			$content =~ s/<use.*traffic-arrow.*>.*<\/use>/Richtung/g;
		
			#$tree->parse_content(encode($encode, $content));
			$tree->parse_content($content);
			
			$message_zone = ' für Hessen';
			
			@toc = $tree->findnodes('//li[contains(@class, "trafficInfo__item")]');
			
			for my $el ( Verkehrsinfo_hf_orderby($orderby, @toc) ) {
				if (grep(!/$filterexclude/i, $el->as_trimmed_text) && grep(/$filterinclude/i, $el->as_trimmed_text)){
					if (exists $el->findnodes('div/p')->[0] && exists $el->findnodes('div/span')->[0]){
						# check message if it's road or information
						if ($el->findnodes('div/p')->[0]->as_trimmed_text =~ /^[0-9]/){
							$dataarray->{"e_".$i."_road"} = substr($el->findnodes('div/span')->[0]->as_trimmed_text, 0 ,1).
															$el->findnodes('div/p')->[0]->as_trimmed_text;
							$dataarray->{"e_".$i."_head"} = (exists $el->findnodes('div/strong')->[0]) ? $el->findnodes('div/strong')->[0]->as_trimmed_text : '';
							$dataarray->{"e_".$i."_msg"}  = (exists $el->findnodes('div/p')->[1]) ? $el->findnodes('div/p')->[1]->as_trimmed_text : '';
							$message .= (exists $el->findnodes('div/p')->[1]) ? $el->findnodes('div/p')->[1]->as_trimmed_text : '';
							$message .= ($el->findnodes('div/p')->[1]->as_trimmed_text =~ /\.$/) ? ' ' : '. ';
						}
						else {
							$dataarray->{"e_".$i."_road"} = '-';
							$dataarray->{"e_".$i."_head"} = $el->findnodes('div/span')->[0]->as_trimmed_text;
							$dataarray->{"e_".$i."_msg"}  = $el->findnodes('div/p')->[0]->as_trimmed_text;
							$message .= (AttrVal($name,"msg_format","") =~ "head|both") ? $el->findnodes('div/span')->[0]->as_trimmed_text .', ' : '';
							$message .= $el->findnodes('div/p')->[0]->as_trimmed_text;
							$message .= ($el->findnodes('div/p')->[0]->as_trimmed_text =~ /\.$/) ? ' ' : '. ' ;
						}
						$i++;
					}
					else{
						Log3 $hash, 3, "Verkehrsinfo: ($name) Verkehrsinfo_HttpNbUpdateData DataNodeElements not found";
					}
				}
			}
		}
		
		 
		if ($i - 1 == 0){
			$message_head = "Es liegen um " . strftime('%H:%M', localtime) . $message_zone . " keine Staumeldungen vor.";
		}
		elsif ($i - 1 == 1){
			$message_head  = "Es liegt um " . strftime('%H:%M', localtime) . $message_zone . " eine Staumeldung vor:\n";
		}
		else{
			my $anz_msg = $i - 1;
			$message_head = "Es liegen um " . strftime('%H:%M', localtime) . $message_zone . ', ' . $anz_msg ." Staumeldungen vor:\n";
		}
		
		$dataarray->{'message'} = $message_head . ' ' . $message;
		$dataarray->{'message'} =~ s/\<pre\>//;
		$dataarray->{'message'} =~ s/\<\/pre\>//;
		$dataarray->{'count'} = $i - 1;
		
		
		# delete old readings
		Log3 $hash, 4, "Verkehrsinfo: ($name) Delete old Readings";
		CommandDeleteReading(undef, "$hash->{NAME} e_.*_.*");
		
		Log3 $hash, 4, "Verkehrsinfo: ($name) Create new Readings";
		
		# update readings
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "date_time", FmtDateTime(time()) );
		
		foreach my $readingName (keys %{$dataarray}){
			Log3 $hash, 4, "Verkehrsinfo: ($name) ReadingsUpdate: $readingName - ".$dataarray->{$readingName};
				readingsBulkUpdate($hash,$readingName,$dataarray->{$readingName});
		}
		readingsBulkUpdate($hash, "state",  'update ' . FmtDateTime(time()));
		readingsEndUpdate($hash, 1);
	
	}
	Log3 $hash, 4, "Verkehrsinfo: ($name) Verkehrsinfo_HttpNbUpdateData done";
}

sub Verkehrsinfo_GetUpdate($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if ( $hash->{Interval}) {
        RemoveInternalTimer ($hash);
	}
	InternalTimer(gettimeofday()+$hash->{Interval}, "Verkehrsinfo_GetUpdate", $hash, 1);
	Log3 $hash, 4, "Verkehrsinfo: ($name) internal interval timer set to call GetUpdate again in " . int($hash->{Interval}). " seconds";
	
	my $param = {
                    url        => $hash->{url},
                    timeout    => 5,
                    hash       => $hash,
                    callback   =>  \&Verkehrsinfo_HttpNbUpdateData
                };
	HttpUtils_NonblockingGet($param);
}

# give back all traffic information as formated text
sub Verkehrsinfo_GetData($){

	my ($device) = @_;
	my $hash = $defs{$device};

	if (!defined $device){
		Log3 $hash, 1, "Verkehrsinfo: ($device) Device not found";
		return "Device not found";
	}
	
	my $msg = '';
	my $i = 1;
	
	$msg = ReadingsVal($device, 'count', '') . " Meldungen für ". ReadingsVal($device, 'zone', '') .":\n\n";
	
	for ($i=1; $i <= ReadingsVal($device, 'count', ''); $i++){
		$msg = $msg . ReadingsVal($device, 'e_'.$i.'_road', '') . " - ";
		$msg = $msg . ReadingsVal($device, 'e_'.$i.'_head', '') . "\n";
		$msg = $msg . ReadingsVal($device, 'e_'.$i.'_msg', '') . "\n\n";
	}
	
	return $msg;

}

##################
# helper function
##################

# sort messages
sub Verkehrsinfo_hf_orderby ($@) {
	my ($order, @inp) = @_;
	my @res;
	my %diff;
	for my $oel (split(/\|/, $order)) {
		for my $ael ( @inp ) {
			push(@res, $ael) if (grep (/$oel/i, $ael->as_trimmed_text));
		}
	}
	@diff{ @inp } = @inp;
	delete @diff{ @res };
	
	return (@res, values %diff);
}

1;

=pod
=item device
=item summary read trafficinformation from various sources
=item summary_DE Verkehrsinformationen von verschiedenen Quellen auslesen.
=begin html

<a name="Verkehrsinfo"></a>
<h3>Verkehrsinfo</h3>
<ul>
    <i>Verkehrsinfo</i> can read trafficinformation from various source.
	<br><br>
	<ul>
		<li>Verkehrsinfo.de</li>
		For receiving the traffic informationen, following website https://www.verkehrsinfo.de/httpsmobil will be called on.<br>
		There you can select streets or federal states. Afterwards the URL will be committed as a parameter.
    <br><br>
		<li>Hessenschau.de</li>
		Here is no configuration necessary, the URL http://hessenschau.de/verkehr/index.html will be used as a parameter.
	</ul>
    <br><br>
	
	<b>Requirement:</b>
	<ul><br>
		For this module, following perl-modules are required:<br>
		<li>HTML::TreeBuilder::XPath<br>
		<code>sudo apt-get install libxml-treebuilder-perl libhtml-treebuilder-xpath-perl</code>
		</li>
	</ul>
	<br><br>
	
    <a name="Verkehrsinfodefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; Verkehrsinfo &lt;url&gt; &lt;interval&gt;</code>
        <br><br>
        example: <code>define A8 Verkehrsinfo https://www.verkehrsinfo.de/httpsmobil/index.php?c=staulist&street=A8&lat=&lon= 3600 </code>
		<br><br>
        Options:
        <ul>
              <li><i>url</i><br>
				URL regarding the traffic information</li>
			  <li><i>interval</i><br>
				How often the data will be updated in seconds</li>
        </ul>
    </ul>
    <br>
    
    <a name="Verkehrsinfoset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;option&gt;</code>
        <br><br>
        Options:
        <ul>
              <li><i>update</i><br>
				update will be executed right away</li>
        </ul>
    </ul>
    <br>
	
	<a name="Verkehrsinfoget"></a>
    <b>Get</b><br>
    <ul>
        <code>get &lt;name&gt; &lt;option&gt;</code>
        <br><br>
        Options:
        <ul>
              <li><i>info</i><br>
				output currently traffic information</li>
        </ul>
    </ul>
    <br>
	
	<a name="Verkehrsinfoattr"></a>
    <b>Attributes</b><br>
    <ul>
        <code>attr &lt;name&gt; &lt;option&gt; &lt;value&gt;</code>
        <br><br>
        Options:
        <ul>
            <li><i>filter_exclude</i><br>
				This is an exclusion filter. Traffic information containing these words, will not be displayed.<br>
				The filter supports regular expressions. Attention: regex control character, for example brackets have to be masked with a backslash "\".<br>
				Multiple searching keywords can be seperated with the pipe "|".<br><br></li>
			<li><i>filter_include</i><br>
				This is an inclusion filter. Traffic information containing these words, will be displayed.<br>
				The filter supports regular expressions. Attention: regex control character, for example brackets have to be masked with a backslash "\".<br>
				Multiple searching keywords can be seperated with the pipe "|".<br><br></li>
			<li>Hint: Both filters can be used at the same time, or optional just one.<br>
				The filters are linked with a logical and. That means, for example, when something is excluded, it can be reincluded with the other filter.<br><br></li>
			<li><i>orderby</i><br>
				Messages will be sorted by relevance by reference to the string.<br>
				The sort supports regular expressions.<br>
				Multiple searching keywords can be seperated with the pipe "|".<br><br></li>
			<li><i>msg_format [ road | head | both ]</i> (Nur Verkehrsinfo.de)<br>
				Using this parameter you can format the output, regarding streets, direction or both.<br><br></li>
			<li><i><a href="#readingFnAttributes">readingFnAttributes</a></i><br><br></li>
        </ul>
    </ul>
    <br>
	
	<a name="Verkehrsinforeading"></a>
    <b>Readings</b>
    <ul>
	   <br>
	   <li><b>e_</b><i>0|1|2|3...|9</i><b>_...</b> - aktiv message</li>
	   <li><b>count</b> - number of aktiv messages</li>
	   <li><b>e_</b><i>0</i><b>_road</b> - street</li>
	   <li><b>e_</b><i>0</i><b>_head</b> - direction</li>
	   <li><b>e_</b><i>0</i><b>_msg</b>  - message</li>
    </ul>
    <br>
	
	<a name="Verkehrsinfofunktion"></a>
    <b>Funktion</b>
    <ul>
        <code>Verkehrsinfo_GetData(&lt;devicename&gt;)</code>
		<br><br>
		The function can be accessed anywhere in FHEM.
		The output of this function is the same as get <name> info and the string can be used for further forwarding.
        <br><br>
		example: <code>my $result = Verkehrsinfo_GetData('A8')</code>
    </ul>
    <br>
</ul>
=end html

=begin html_DE

<a name="Verkehrsinfo"></a>
<h3>Verkehrsinfo</h3>
<ul>
    <i>Verkehrsinfo</i> kann die aktuellen Verkehrsinformationen von verschiedenen Quellen auslesen.
	<br><br>
	<ul>
		<li>Verkehrsinfo.de</li>
	Um die gewünschten Verkehrsinformation zu erhalten wird die Webseite https://www.verkehrsinfo.de/httpsmobil besucht. 
	Hier können Sie dann entweder Straßen oder Bundesländer auswählen. Anschließend wird die URL als Parameter übergeben.
    <br><br>
		<li>Hessenschau.de</li>
		Hier ist keine Konfiguration notwendig, man verwendet die URL http://hessenschau.de/verkehr/index.html als Parameter.
	</ul>
    <br><br>
	
	<b>Voraussetzung:</b>
	<ul><br>
		Für dieses Modul werden folgende Perlmodule benötigt:<br>
		<li>HTML::TreeBuilder::XPath<br>
		<code>sudo apt-get install libxml-treebuilder-perl libhtml-treebuilder-xpath-perl</code>
		</li>
		<li>JSON<br>
		<code>sudo apt-get install libjson-perl</code>
		</li>
	</ul>
	<br><br>
	
    <a name="Verkehrsinfodefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; Verkehrsinfo &lt;url&gt; &lt;interval&gt;</code>
        <br><br>
        Beispiel: <code>define A8 Verkehrsinfo https://www.verkehrsinfo.de/httpsmobil/index.php?c=staulist&street=A8&lat=&lon= 3600 </code>
		<br><br>
        Options:
        <ul>
              <li><i>url</i><br>
				URL der auszulesenden Verkehrsinformationen</li>
			  <li><i>interval</i><br>
				Alle wieviel Sekunden die Daten aktualisiert werden</li>
        </ul>
    </ul>
    <br>
    
    <a name="Verkehrsinfoset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;option&gt;</code>
        <br><br>
        Options:
        <ul>
              <li><i>update</i><br>
				Update wird sofort ausgeführt</li>
        </ul>
    </ul>
    <br>
	
	<a name="Verkehrsinfoget"></a>
    <b>Get</b><br>
    <ul>
        <code>get &lt;name&gt; &lt;option&gt;</code>
        <br><br>
        Options:
        <ul>
              <li><i>info</i><br>
				Ausgeben der aktuellen Verkehrsinformationen</li>
        </ul>
    </ul>
    <br>
	
	<a name="Verkehrsinfoattr"></a>
    <b>Attributes</b><br>
    <ul>
        <code>attr &lt;name&gt; &lt;option&gt; &lt;value&gt;</code>
        <br><br>
        Options:
        <ul>
            <li><i>filter_exclude</i><br>
				Dies ist ein Ausschlussfilter. Verkehrsmeldung die eines der Wörter enthalten, werden nicht angezeigt.<br>
				Der Filter unterstütz Regulärer Ausdrücke. Achtung: Regex Steuerzeichen, z.B. Klammern müssen mit einem Backslash "\" maskiert werden.<br>
				Mehrer Suchbegriffe können mit einer Pipe "|" getrennt werden.<br><br></li>
			<li><i>filter_include</i><br>
				Dies ist ein Einschlussfilter. Es werden nur Verkehrsmeldung angezeigt die eines der Wörter enthalten.<br>
				Der Filter unterstütz Regulärer Ausdrücke. Achtung: Regex Steuerzeichen, z.B. Klammern müssen mit einem Backslash "\" maskiert werden.<br>
				Mehrer Suchbegriffe können mit einer Pipe "|" getrennt werden.<br><br></li>
			<li>Hinweis: Beide Filter können gleichzeitig benutzt werden, aber es kann auch wahlweise nur einer verwendet werden.<br>
				Die Filter sind mit einem Logischen UND verknüpft. Das heist z.B.: wenn etwas ausgeschlossen wurde, kann es nicht mit dem Einschlussfilter wiedergeholt werden.<br><br></li>
			<li><i>orderby</i><br>
				Anhand von Zeichefolgen wird eine Sortierung der Meldungen nach Relevanz vorgenommen.<br>
				Die Sortierung unterstützt Regulärer Ausdrücke.<br>
				Mehrer Suchbegriffe können mit einer Pipe "|" getrennt werden.<br><br></li>
			<li><i>msg_format [ road | head | both ]</i> (Nur Verkehrsinfo.de)<br>
				Über diesen Parameter kann die Meldung formatiert werden nach Strasse, Richtung oder beides<br><br></li>
			<li><i><a href="#readingFnAttributes">readingFnAttributes</a></i><br><br></li>
        </ul>
    </ul>
    <br>
	
	<a name="Verkehrsinforeading"></a>
    <b>Readings</b>
    <ul>
	   <br>
	   <li><b>e_</b><i>0|1|2|3...|9</i><b>_...</b> - aktive Meldungen</li>
	   <li><b>count</b> - Anzahl der aktiven Meldungen</li>
	   <li><b>e_</b><i>0</i><b>_road</b> - Straße</li>
	   <li><b>e_</b><i>0</i><b>_head</b> - Fahrtrichtung</li>
	   <li><b>e_</b><i>0</i><b>_msg</b>  - Meldung</li>
    </ul>
    <br>
	
	<a name="Verkehrsinfofunktion"></a>
    <b>Funktion</b>
    <ul>
        <code>Verkehrsinfo_GetData(&lt;devicename&gt;)</code>
		<br><br>
		Die Funktion kann überall in FHEM aufgerufen werden und liefert als Rückgabewert das gleiche Ergebnis wie der get &lt;name&gt; info Aufruf.
		Der Rückgabewert als Text, kann dann für weiteres verwendet werden.
        <br><br>
		Beispiel: <code>my $result = Verkehrsinfo_GetData('A8')</code>
    </ul>
    <br>
</ul>

=end html_DE

=cut
