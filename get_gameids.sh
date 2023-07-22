#!/bin/bash

# Usage: ./get_gameids.sh <MMDD> <action>

# this script should be run at the beginning of the day
# to populate the mlbgmaes table containng 
# a unique record for each game

# this script is run only once per day
# and called by the main cron script so never run manually

BASE="/home/mea/baseball/br_year_data" ;
DATA="$BASE/data" ;
JSON="$DATA/json_data" ;
CURYEAR=$( date +%Y ) ;
action="ids" ;
year=$CURYEAR ;

monthday=$( date +%m%d ) ;
dateid=$( date +%Y%m%d ) ;
myhour=$( date +%H%M ) ;
month=${monthday:0:2} ;
day=${monthday:2:2} ;
printdate="${month}/${day}/${year}" ;
debug=0 ;
LOGTEXT="$dateid $myhour get_gameids.sh" ;

if [ ! -z $2 ] ; then 
	action=$2 ; 
	if [ $action == "debug" ] ; then 
		echo "$LOGTEXT debug on" ; debug=1 ; exit ;
	elif [ $action != "force" ] ; then echo "$LOGTEXT bad action $action" ; exit ; fi
	monthday=$1 ;
	dateid=${CURYEAR}${1} ;
	# need to sanitize monthday here
elif [ ! -z $1 ] ; then 
	action=$1 ; 
	if [ $action == "debug" ] ; then 
		echo "$LOGTEXT debug on" ; debug=1 ; exit ;
	elif [ $action != "force" ] ; then echo "$LOGTEXT bad action $action" ; exit ; fi
fi

MLBURL="http://statsapi.mlb.com/api/v1/schedule/games/?sportId=1&date=${printdate}" ;
OFILE="$JSON/games_${dateid}.json" ;

if [ $debug -eq 1 ] ; then echo "$LOGTEXT debug mode" ; 
elif [ ! -s $OFILE ] ; then
	echo "$LOGTEXT --> wget -O $OFILE $MLBURL" ;
	wget -O $OFILE $MLBURL ;
else echo "$LOGTEXT $OFILE exists" ; exit ;
fi

if [ ! -s $OFILE ] ; then echo "$LOGTEXT no output $OFILE" ; exit ; fi

# we have an output let's process it

importfile="$DATA/${dateid}.mlbgames.csv" ;
echo "$LOGTEXT ./json/parse_day.pl $OFILE"  ;
$BASE/json/parse_day.pl $OFILE ;

# the above created a dateid.mlbgames.csv which can
# be imported into the mlbgames table using .import command

# WEBDB is the sqlite database used by external web users
# DB is the internal sqlite database used internally
# WEBDB is a subset of DB

DB="$DATA/current.db" ;
WEBDB="$HOME/current/current.db" ;

if [ ! -s $importfile ] ; then 
	if [ ! -e $importfile ] ; then
		echo "$LOGTEXT can't find mlbgameid csv file $importfile"   ; 
	else echo "$LOGTEXT mlbgameid csv file $importfile empty"   ; 
	fi
else
	if [ ! -s $DB ] ; then echo "$LOGTEXT no db $DB" ; exit ; fi
	echo ".import $importfile mlbgames"  | sqlite -csv $DB  ; 
	if [ -s $WEBDB ] ; then 
		echo ".import $importfile mlbgames"  | sqlite -csv $WEBDB  ; 
	fi
fi

if [ ! -d $JSON/$dateid ] ; then 
	echo "$LOGTEXT making directory $JSON/$dateid" ; 
	mkdir "$JSON/$dateid" ;
fi
# insert current day into datemap
	daterecord=$( echo "select dateid,dateindex from datemap order by dateid desc limit 1 ; " | sqlite -csv $DB )  ;
	if [ -z "$daterecord" ] ; then daterecord="0,0" ; fi
	echo $daterecord | while  IFS=,  read dbdateid dateindex ;
	do
		if [ $dbdateid -ge $dateid ] ; then
			echo "$LOGTEXT dateid $dateid already in datemap" ;
			continue ;
		else let newdateindex=$dateindex+1 ;
		fi
		echo "$LOGTEXT adding $dateid,$newdateindex to datemap" ;
		echo "insert into datemap values ( $dateid , $newdateindex , \"none\" );" | sqlite -csv $DB ;
		if [ -s $WEBDB ] ; then
			echo "insert into datemap values ( $dateid , $newdateindex , \"none\" );" | sqlite -csv $WEBDB ;
		fi
	done


exit ;

