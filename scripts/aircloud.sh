#!/bin/bash


##########################################################
# ./airCloud.sh <action> <room> <temperature> <mode> <fanspeed> <fanswing>
#
# <action> : on (Power On) / off (Power Off) / powerstatus (AC Power Status) / modestatus (AC Mode Status) / roomtemperature (Room Temperature) / idutemperature (AC Thermostat Temperature) / fanspeed (Fan Mode) / fanswing (Swing Mode) / websocatdebug (display Hitachi websocket full result in json) / websocatdebug2 
# <room> : Name of the room on the Aircloud application
# <temperature> : Target temperature
# <mode> : COOLING / HEATING / FAN / DRY / AUTO(defaut)
# <fanspeed> : LV1 / LV2 / LV3 / LV4 / LV5 / AUTO(defaut)
# <fanswing> :  VERTICAL / OFF(defaut)
##########################################################


#login and password in base64
hitachiuser=$(echo "<replace with your Hitachi's account email in base64>" | base64 -d)
hitachipassword=$(echo "<replace with your Hitachi's account password in base64>" | base64 -d)
#or in plain text

#hitachipassword="<replace with your Hitachi's account password in plain text>"
#hitachiuser=<replace with your Hitachi's account email in plain text>
websocatbinary="<replace with the path to websocat binary>"
wssairCloud="wss://notification-global-prod.aircloudhome.com/rac-notifications/websocket"
pingtimeout="5"

uuid=$(curl -s https://www.uuidtools.com/api/generate/v1 | jq -r .[0])
#uuid=$(uuidgen)

#echo $uuid
token=$(curl -s -H "Accept: application/json" -H "Content-Type: application/json; charset=UTF-8" -H "Host: api-global-prod.aircloudhome.com" -H "User-Agent: okhttp/4.2.2" --data-binary "{\"email\":\"$hitachiuser\",\"password\":\"$hitachipassword\"}" --compressed "https://api-global-prod.aircloudhome.com/iam/auth/sign-in" | jq -r .token)
#echo $token
familyId=$(curl -s -H "Authorization: Bearer $token" -H "Content-Type: application/json" -H "Accept: application/json" -H "Host: api-global-prod.aircloudhome.com" -H "User-Agent: okhttp/4.2.2" --compressed "https://api-global-prod.aircloudhome.com/iam/user/v2/who-am-i" | jq -r .familyId)
#echo $familyId
cloudlds=$(curl -s -H "Authorization: Bearer $token" -H "Content-Type: application/json" -H "Accept: application/json" -H "Host: api-global-prod.aircloudhome.com" -H "User-Agent: okhttp/4.2.2" --compressed "https://api-global-prod.aircloudhome.com/rac/ownership/groups/cloudIds/$familyId")
#echo $cloudlds
connectandsub=$(printf "CONNECT\naccept-version:1.1,1.2\nheart-beat:10000,10000\nAuthorization:Bearer $token\n\n\0\nSUBSCRIBE\nid:$uuid\ndestination:/notification/$familyId/$familyId\nack:auto\n\n\0" | base64 -w0 )

# echo "#########################################"
# echo "Order parameters"
# echo "1 :" $1
# echo "2 :" $2
# echo "3 :" $3
# echo "4 :" $4
# echo "5 :" $5
# echo "6 :" $6
# echo "#########################################"


if [ "$2" = "" ]
	then
		:
	else
		roomName=$2
		roomId=$(echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n" | jq -r ".data[] | select(.name==\"$roomName\") | .id")
		#echo "roomID : " $roomId
		  while [ -z "$roomId" ]
		  do
			roomId=$(echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n" | jq -r ".data[] | select(.name==\"$roomName\") | .id")
			#echo "roomID : " $roomId
			sleep 10
		  done
fi

temperature=$3".0"
mode=$4
fanSpeed=$5
fanSwing=$6

if [ "$4" = "" ]
	then
		mode="AUTO"
	elif [ "$4" = "FAN" ]; then
		temperature="0"
	else
		:
fi

if [ "$5" = "" ] && [ "$4" != "FAN" ]
	then
		fanSpeed="AUTO"
	elif [ "$5" = "" ] && [ "$4" = "FAN" ]; then
        fanSpeed="LV2"
	else
		:
fi

if [ "$6" = "" ]
	then
		fanSwing="OFF"
	else
		:
fi

# echo "#########################################"
# echo "Content of variables"
# echo "Room :" $roomName "    ID :" $roomId
# echo "Temperature :" $temperature
# echo "Mode :" $mode
# echo "Fan Speed :" $fanSpeed
# echo "Fan Swing :" $fanSwing
# echo "#########################################"

case "$1" in
"on")
  now=$(date)
  #echo "ON at $now"  >> /opt/scripts/logs.txt
  if [ -z "$roomId" ]
  then
	:
  else
	websocatresult=$(echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n")
	#until [[ $(echo $websocatresult | jq -r ".data[] | select(.id==$roomId) | .power") = "ON" ]]
	until [ $(echo $websocatresult | jq -r ".data[] | select(.id==$roomId) | .power") = "ON" ] && [ $(echo $websocatresult | jq -r ".data[] | select(.id==$roomId) | .iduTemperature") -eq $(echo $temperature) ] && [ $(echo $websocatresult | jq -r ".data[] | select(.id==$roomId) | .fanSpeed") = $(echo $fanSpeed) ]
	do
		#echo "ON $mode $temperature at $now"  >> /opt/scripts/logs.txt
		curl -s -H "Authorization: Bearer $token" -H "Accept: application/json" -H "Content-Type: application/json; charset=UTF-8" -H "Host: api-global-prod.aircloudhome.com" -H "User-Agent: okhttp/4.2.2" --data-binary "{\"fanSpeed\":\"$fanSpeed\",\"fanSwing\":\"$fanSwing\",\"humidity\":\"0\",\"id\":$roomId,\"iduTemperature\":$temperature,\"mode\":\"$mode\",\"power\":\"ON\"}" -X PUT --compressed "https://api-global-prod.aircloudhome.com/rac/basic-idu-control/general-control-command/$roomId?familyId=$familyId"
		sleep 20
		websocatresult=$(echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n")
	done
  fi
;;
"off")
  now=$(date)
  #echo "OFF at $now" >> /opt/scripts/logs.txt
  if [ -z "$roomId" ]
  then
	:
  else
	until [ $(echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n" | jq -r ".data[] | select(.id==$roomId) | .power") = "OFF" ]
	do
		#echo "OFF $mode $temperature at $now"  >> /opt/scripts/logs.txt
		curl -s -H "Authorization: Bearer $token" -H "Accept: application/json" -H "Content-Type: application/json; charset=UTF-8" -H "Host: api-global-prod.aircloudhome.com" -H "User-Agent: okhttp/4.2.2" --data-binary "{\"fanSpeed\":\"$fanSpeed\",\"fanSwing\":\"$fanSwing\",\"humidity\":\"0\",\"id\":$roomId,\"iduTemperature\":$temperature,\"mode\":\"$mode\",\"power\":\"OFF\"}" -X PUT --compressed "https://api-global-prod.aircloudhome.com/rac/basic-idu-control/general-control-command/$roomId?familyId=$familyId"
		sleep 20
	done
  fi
;;
"powerstatus")
	echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n" | jq -r ".data[] | select(.id==$roomId) | .power"
;;
"modestatus")
	echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n" | jq -r ".data[] | select(.id==$roomId) | .mode"
;;
"powerstatusbymode")
	echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n" | jq -r ".data[] | select((.id==$roomId) and (.mode==\"$mode\")) | .power"
;;
"roomtemperature")
	echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n" | jq -r ".data[] | select(.id==$roomId) | .roomTemperature"
;;
"roomhumidity")
	echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n" | jq -r ".data[] | select(.id==$roomId) | .humidity"
;;
"idutemperature")
	echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n" | jq -r ".data[] | select(.id==$roomId) | .iduTemperature"
;;
"fanspeed")
	echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n" | jq -r ".data[] | select(.id==$roomId) | .fanSpeed"
;;
"fanswing")
	echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n" | jq -r ".data[] | select(.id==$roomId) | .fanSwing"
;;
"websocatdebug")
	echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -q -n $wssairCloud | grep -a HITACHI | tr -d "\n" | jq
;;
"websocatdebug2")
        echo $connectandsub | $websocatbinary -b --base64 --ping-timeout=$pingtimeout -n $wssairCloud
;;
*)
esac
