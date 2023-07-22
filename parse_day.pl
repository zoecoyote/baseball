#!/usr/bin/perl

sub usage { print "Usage: ./parse_day.pl filename <action>\n" ; exit ; }

# action can be default and scores ...
# output for default goes into dateid.mlbgames.csv file for
# importation into the mlbgames table in current.db

# this script parses the output of
# http://statsapi.mlb.com/api/v1/schedule/games/?sportId=1&date=${printdate}
# and extracts gameids for further processing
# this endpoint also provides box scores which probably
# should replace nget_box.sh.

use strict ;
use warnings ;
use JSON;
#use Data::Dumper;
use IO::File ;

my %team_map = () ;
my $curdir = "/home/mea/baseball/br_year_data" ;
my $file = "$curdir/teamname.map" ;
my $document = new IO::File ;
if ( $document -> open ( $file ) ) {
	foreach my $tmp (<$document>) {
		chomp $tmp ;
		my @items = split / +/ , $tmp ;
		my $name = $items[1] ;
		$name =~ s/ /_/g ;
		$team_map{$name} = $items[0] ;
	}
	$document -> close ;
} else { print "can't open file $file\n" ; exit ; }

my $filename = "20190831.games" ;
my $action = "none" ;
my $actions = " none " ;
if ( my @args = @ARGV ) {
	$filename = $args[0] ;
	if ( $#args > 0 ) { $action = $args[1] ; }
} else { usage ; }
if ( $actions !~ /$action/ ) { print "bad action $action\n" ; exit ; }

my $log_fh = new IO::File ">> $curdir/data/parse_day.log" ;

my $json_text = do {
   open(my $json_fh, "<:encoding(UTF-8)", $filename)
      or die("Can't open \$filename\": $!\n");
   local $/;
   <$json_fh>
};

my $json = JSON->new;
my $data = $json->decode($json_text);

my @awayhome = qw ( away home ) ;

my %teamwins = () ; # keyed by teamid
my %teamloss = () ; # keyed by teamid
my %teamscore = () ; # keyed by teamid
my %game = () ; # keyed by mlbgames , value gameid
my %iswinner = () ;

my @gamepk = () ;  # contains all gameids
my %boxrecord = () ; # keyed by gameid , value box record
my %checkthis = () ; # keyed by gameid, checks for double headers

my ($sec,$min,$hour,$mday,$mon,$xyear,$wday,$yday,$isdst) = localtime();
$xyear += 1900;
my $mydate = sprintf "%d%02d%02d" , $xyear , $mon + 1 , $mday ;
my $mytime = sprintf "%02d%02d" , $hour, $min ;
my $logtext = "$mydate $mytime parse_day.pl" ;
print $log_fh "$logtext processing $filename\n" ;

my %teamid = () ; # keyed by teamid , value existance

my $dateid = $mydate ; #this has to be global
foreach my $dates ( @{$data->{dates}} ) {
#print $tmp->{date}."\n";
#print "got here $#{$tmp->{teams}}\n" ;
#foreach my $mykey ( keys %$tmp ) { print "under dates $mykey\n" ; }
	$dateid = $dates->{date} ;
	$dateid =~ s/-//g ;
	my $awayteam = "none" ;
	my $hometeam = "none" ;
	foreach my $tmp2 ( @{$dates->{games}} ) {
	   foreach my $ah ( @awayhome ) {
		my $teamname = "none" ; 
		if ( exists  $tmp2->{teams}{$ah}{team}{name} ) {
			$teamname = $tmp2->{teams}{$ah}{team}{name} ;
		}
		$teamname =~ s/ /_/g ;
#		my $teamid = "XXX" ;
		my $teamid = uc substr ( $teamname,0,3 ) ;
		if ( ! exists $team_map{$teamname} ) {
			print "no map for teamname $teamname\n" ; 
		} else { $teamid = $team_map{$teamname} ; }
		if ( $ah eq "away" ) { $awayteam = $teamid ; }
		else { $hometeam = $teamid ; }
		if ( exists $tmp2->{teams}{$ah}{leagueRecord}{wins} ) {
			$teamwins{$teamid} = $tmp2->{teams}{$ah}{leagueRecord}{wins} ;
		} else { $teamwins{$teamid} = 0 ; }
		if ( exists $tmp2->{teams}{$ah}{leagueRecord}{losses} ) {
			$teamloss{$teamid} = $tmp2->{teams}{$ah}{leagueRecord}{losses} ;
		} else { $teamloss{$teamid} = 0 ; }
		if ( exists $tmp2->{teams}{$ah}{score} ) {
			$teamscore{$teamid} = $tmp2->{teams}{$ah}{score} ;
		} else { $teamscore{$teamid} = 0 ; }
#		if ( exists $tmp2->{teams}{$ah}{isWinner} ) {
#			$iswinner{$teamid} = $tmp2->{teams}{$ah}{isWinner} ;
#		} else { $iswinner{$teamid} = 0 ; } 
	   }
	   my $gameid =  $dateid . " 0" . " " . $awayteam . " " . $hometeam ;
	   my $rgameid =  $dateid . " 0" . " " . $hometeam . " " . $awayteam ;
	   my $gnum = 0 ;
	   my $mlbgameid = $tmp2->{gamePk} ;
	   my $gamestate = $tmp2->{status}{detailedState} ;
	   print $log_fh "$logtext $mlbgameid gamestate $gamestate\n" ;
	   if ( $gamestate eq "Suspended" ) {
		print $log_fh "$logtext game suspended skipping mlbgameid\n" ; next ;
	   }
	   if ( exists $checkthis{$gameid} ) { # it's a double header
		my $xmlbgameid = $checkthis{$gameid} ;
		# very messy below but it might work!
		if ( exists $game{$xmlbgameid} ) {
			$game{$xmlbgameid} =~ s/,0,/,1,/ ;
		}
		$gnum = 2 ;
	   } else { 
		$checkthis{$gameid} = $mlbgameid ; 
		$checkthis{$rgameid} = $mlbgameid ; 
		$teamid{$awayteam} =  0 ;
		$teamid{$hometeam} =  0 ;
	   }
	   my $printwinner = $awayteam ;
	   my $printfinal = "FINAL" ;
	   if ( $teamscore{$hometeam} > $teamscore{$awayteam} ) {
		$printwinner = $hometeam ;
	   } elsif ( $teamscore{$awayteam} > $teamscore{$hometeam} ) {
		$printwinner = $awayteam ;
	   } else { $printwinner = "TIE" ; }
	   my $gamedate = $tmp2->{gameDate} ;
	   my ( $xdateid,$gametime ) = split /T/,$gamedate ;
	   my ( $hour,$minute,$second ) = split /:/ , $gametime ;
	   my $xhour = $hour ;
	   $xhour =~ s/^0// ;
	   if ( $xhour < 8 ) { $xhour = sprintf "%02d" , $xhour + 24 - 5 ; }
	   else { $xhour = sprintf "%02d" , $xhour - 5 ; }
	   $gametime = $xhour . ":" . $minute ;
	
	   my $awayrecord = sprintf "%s_%s" , $teamwins{$awayteam} , $teamloss{$awayteam} ;
	   my $homerecord = sprintf "%s_%s" , $teamwins{$hometeam} , $teamloss{$hometeam} ;
	   $gameid =~ s/ /,/g ;
	   $game{$mlbgameid} = "$dateid,$gnum,$gametime,$mlbgameid,$awayteam,$hometeam" ;
	   $boxrecord{$mlbgameid} = sprintf "$gameid $teamscore{$awayteam} $teamscore{$hometeam} $printwinner $printfinal $awayrecord $homerecord" ;
#	   push @gamepk , $tmp2->{gamePk} ;
	}
} #endof @{data->{dates}}

#print "got here action $action\n" ;

print $log_fh "$logtext all done ... making mlbgames.csv\n" ;
$log_fh -> close ;

if ( $action eq "none" ) {
	my $datefile = "$curdir/data/$dateid.mlbgames.csv" ;
	my $date_fh = new IO::File ;
	if ( $date_fh -> open ( "> $datefile" )) {
	} else { print "can't open file $datefile\n" ; exit ; }

	foreach my $mlbgameid ( sort {$a <=> $b} keys %game ) { 
		print $date_fh "$game{$mlbgameid}\n" ; 
	}
	$date_fh -> close ;
} elsif ( $action eq "scores" ) {
	foreach my $mlbgameid ( keys %boxrecord ) {
		print "$boxrecord{$mlbgameid} $mlbgameid\n" ;
	}
}

exit ;

