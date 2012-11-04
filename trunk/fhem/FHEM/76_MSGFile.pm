##############################################
# $Id: 76_MSGFile.pm 2012-06-20 18:29:00 rbente
##############################################
package main;

use strict;
use warnings;
use Switch;
my %sets = (
  "add" => "MSGFile",
  "clear" => "MSGFile",
  "list" => "MSGFile"
);
##############################################
# Initialize Function
#  Attributes are:
#     filename    the name of the file
#     filemode    new = file will be created from scratch
#                 append = add the new lines to the end of the existing data
#     CR          0 = no CR added to the end of the line
#                 1 = CR added to the end of the line
##############################################
sub
MSGFile_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "MSGFile_Set";
  $hash->{DefFn}     = "MSGFile_Define";
  $hash->{UndefFn}   = "MSGFile_Undef";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6 filename filemode:new,append CR:0,1";
}

##############################################
# Set Function
# all the data are stored in the global array  @data
# as counter we use a READING named msgcount
##############################################
sub
MSGFile_Set($@)
{
  my ($hash, @a) = @_;
    return "Unknown argument $a[1], choose one of ->  " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));

  
  my $name = shift @a;

	return "no set value specified" if(int(@a) < 1);
	return "Unknown argument ?" if($a[0] eq "?");
	my $v = join(" ", @a);

##### we like to add another line of data	
	if($a[0] eq "add")
	{
##### split the line in command and data	
		my $mx = shift @a;
		my $my = join(" ",@a);
##### check if we like to have and CR at the end of the line		
		if(AttrVal($name, "CR", "0") eq "1")
		{
			$my = $my . "\n";
		}
##### get the highest number of lines, store the line in  @data and increase 
##### the counter, at the end set the status
		my $count = $hash->{READINGS}{msgcount}{VAL};
		$data{$name}{$count} = $my;
		$hash->{READINGS}{msgcount}{TIME} = TimeNow();
		$hash->{READINGS}{msgcount}{VAL}  = $count + 1;
		$hash->{STATE} = "addmsg";

	}
	
##### we like to clear our buffer, first clear all lines of @data
##### and then set the counter to 0 and the status to clear
	if($a[0] eq "clear")
	{
		my $i;
		for($i=0;$i<ReadingsVal($name,"msgcount",0);$i++)
		{
			$data{$name}{$i} = "";
		}
		$hash->{READINGS}{msgcount}{TIME} = TimeNow();
		$hash->{READINGS}{msgcount}{VAL} = 0;
		$hash->{STATE} = "clear";

	}

##### we like to see the buffer

	if($a[0] eq "list")
	{
		my $i;
		my $mess = "---- Lines of data for $name ----\n";
		for($i=0;$i<ReadingsVal($name,"msgcount",0);$i++)
		{
			$mess .= $data{$name}{$i};
		}
		return "$mess---- End of data for $name ----";
	}
	
  Log GetLogLevel($name,2), "messenger set $name $v";

#   set stats  
 # $hash->{CHANGED}[0] = $v;
  $hash->{READINGS}{state}{TIME} = TimeNow();
  $hash->{READINGS}{state}{VAL} = $v;
  return undef;
}

##############################################
# Define Function
# set the counter to 0
# and filemode to "new"
##############################################
sub
MSGFile_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $errmsg = "wrong syntax: define <name> MSGFile filename";
  my $name = $hash->{NAME};

  return $errmsg    if(@a != 3);
  $attr{$name}{filename} = $a[2];
  $attr{$name}{filemode} = "new";
  $attr{$name}{CR} = "1";
  

  $hash->{STATE} = "ready";
  $hash->{TYPE}  = "MSGFile";
  $hash->{READINGS}{msgcount}{TIME} = TimeNow();
  $hash->{READINGS}{msgcount}{VAL}  = 0;
  return undef;
}
##############################################
# Undefine Function
# flush all lines of data
##############################################
sub
MSGFile_Undef($$)
{
	my ($hash, $name) = @_;
	my $i;
############  flush the data 
	for($i=0;$i<ReadingsVal($name,"msgcount",0);$i++)
	{
		$data{$name}{$i} = "";
	}

	delete($modules{MSGFile}{defptr}{$hash->{CODE}}) if($hash && $hash->{CODE});
	return undef;
}
1;
