#!/bin/bash
#A PID fan controller
#Depenencies: bash, GNU bc
#Matt Cooper, 2015
# TODO: - Use arrays. Itll be easier.
#       - Functions. Can then implement
#         arbitrary numbers of cooling devices.
#       - Avoid bc. Its slow.
#       - Better output for users.
#       - Better configuration. Config
#         script would be nice like pwmconfig
#       - Adjustment of config while
#         the loop is running.
#       - Error handling.
##### initialisation: load config######
        source config                 #
#######################################
{ 
    echo 1 > "$pwm1en"
    echo "$pwm_max1" > "$pwm1path"
 } &                                       #set initial pwm here
{
    echo 1 > "$pwm2en"                        #enable pwm
    echo "$pwm_max2" > "$pwm2path"             #set initial pwm here
 } &
# sleep 2  #use if you want a running start
##set up old temps - only needed for weighted average derivative

  for a in {5..0};
  do read T$a <$temp1
     sleep $dt
  done
  
#   for a in {5..0}
#       do : 
#           T[$a]=$(<"$temp1")
#   done

pwm_new1=$C1
pwm_new2=$C2
#O=($C1 $C2)
mkdir /dev/shm/bashPIDdata
echo "$I1init" > /dev/shm/bashPIDdata/I1 &
echo "$I2init" > /dev/shm/bashPIDdata/I2 &
I1=$I1init
I2=$I2init
#I=($I1init $I2init)

###########################################################
##begin main loop

while [[ $T0 -lt $Tmax ]] #break loop when T>Tmax
       do time { 
#time command used for debugging
          T5=$T4
          T4=$T3
          T3=$T2
          T2=$T1
          T1=$T0

#      for x in {5..1}
#          do T[$((x + 1))]=${T[$x]}
#       done

#deetee[0]=$(date '+%S%N')
wait          #waits until background sleep and all calcs are done
#########
sleep "$dt" &  #sleep is in background, allowing calculations to be done during the sleep cycle.
#########
clear
          T0=$(<$temp1)
##temp functions now stored
##################################console output for user
#date
#echo pwm_new1 = $pwm_new1 pwm_new2 = $pwm_new2
#echo Fan Speed = $(<$fan)
#echo Integrator values from file $(<data/I1) $(<data/I2)
#echo T0 = $T0
##################################why math when not needed?
 if [[ $T0 -lt $pwm1_mintrip  && $T0 -lt $pwm2_mintrip ]]
  then
   echo "$pwm_min1_1" > "$pwm1path" &
   echo "$pwm_min2_1" > "$pwm2path" &
   echo Temperature below trip points &
  continue
 elif [[ $T0 -gt $pwm1_maxtrip  && $T0 -gt $pwm2_maxtrip ]]
  then
   echo "$pwm_max1_1" > "$pwm1path" &
   echo "$pwm_max2_1" > "$pwm2path" &
   echo $I1max > data/I1 &
   echo $I2max > data/I2 &
   I1=$I1max
   I2=$I2max
            {
         K=$((T0 - Thot))
         j=$((K / Tstep))
                   if [[ $j -ge "$numfreq" ]]
             then
                      j="$numfreq"
                 elif [[ $j -le 0 ]]
             then
                      j=0
                   fi
         t=$(echo "$dtsave / (2 * $j)" | bc -l) #poll faster when throttling
         echo new j "$j"
         echo new freq "${freq_list[$j]}"

            for z in $(seq 0 "$cores")
              do cpufreq-set -c "$z" -u "${freq_list[$j]}"
            done
            }
   continue
  fi
###########PID part-do for both sets of constants
###################pwm1######################
{ 
       if [[ $T0 -ge $pwm1_maxtrip ]]
 then
          pwm_new1=$pwm_max1_1
          I1=$I1max
     elif [[ $T0 -le $pwm1_mintrip ]]
 then
          pwm_new1=$pwm_min1_1
     else
          E1=$((T1 - s1))
          E0=$((T0 - s1))
I1=$(<data/I1)
echo "(($i1 * $dt * $half * $((E0 + E1))) + $I1 )" | bc -l > data/I1 # read from file not var
# I1int=$(echo "($I1 + 0.5)/1" | bc)    #now an integer
I1int=$(cut -d "." -f 1 data/I1)       #truncates rather than rounds but saves a bc call
      if [[ $I1int -ge $I1max ]]
 then
          I1=$I1max
          echo $I1max > data/I1
    elif [[ $I1int -le $I1min ]]
 then
         I1=$I1min
         echo $I1min > data/I1
      fi
I1=$(<data/I1)
pwm_new1=$(echo "($C1 + ($p1 * $E0) + $I1 + ($d1 * (($((T0 - T1)) / $dt) + $((T0 - T2)) / (4 * $dt) + $((T0 - T3)) / (6 * $dt) + $((T0 - T4))/(8 * $dt) + $((T0 - T5)) / (10 * $dt)) + $half))/1" | bc)
#pwm_new1=$(echo "($C1 + ($p1 * $E0) + $I1 + ($d1 * ($((T0 - T1)) / $dt) + $((T0 - T2)) / (4 * $dt) + $((T0 - T3)) / (6 * $dt) + $((T0 - T4))/(8 * $dt) + $((T0 - T5)) / (10 * $dt))) + 0.5)/1)" | bc)
###########################################
     if [[ $pwm_new1 -ge $pwm_max1_1 ]]
then
         pwm_new1=$pwm_max1_1
   elif [[ $pwm_new1 -le $pwm_min1_1 ]]
then
         pwm_new1=$pwm_min1_1
     fi
     fi
echo $pwm_new1 > $pwm1path 
#echo pwm_new1 = $pwm_new1
#echo I1 var $I1
#echo I1 file $(<data/I1)
#deetee[1]=$(date '+%S%N')
 } &
########################end of pwm1################
##############################pwm2#################
{ 
        if [[ $T0 -ge $pwm2_maxtrip ]]
 then
        pwm_new2=$pwm_max2_1
        I2=$I2max
   elif [[ $T0 -le $pwm2_mintrip ]]
 then
        pwm_new2=$pwm_min2_1
 else
          E1=$((T1 - s2))
          E0=$((T0 - s2))
I2=$(<data/I2)
echo "(($i2 * $dt * $half * $((E0 + E1))) + $I2 )" | bc -l > data/I2 # read from file not var
I2int=$(($(cut -d "." -f 1 <data/I2) + 1))       #truncates rather than rounds but saves a bc call
 { 
       if [[ $I2int -ge $I2max ]]
 then
          I2=$I2max
          echo $I2 > data/I2
    elif [[ $I2int -le $I2min || $I2int -le 1 ]]
 then
        I2=$I2min
         echo $I2 > data/I2
       fi
 }
 { 
I2=$(<data/I2)
pwm_new2=$(echo "($C2 + ($p2 * $E0) + $I2 + ($d2 * (($((T0 - T1)) / $dt) + $((T0 - T2)) / (4 * $dt) + $((T0 - T3)) / (6 * $dt) + $((T0 - T4))/(8 * $dt) + $((T0 - T5)) / (10 * $dt)) + $half))/1" | bc)
      if [[ $pwm_new2 -ge $pwm_max2_1 ]]
  then
         pwm_new2=$pwm_max2_1
    elif [[ $pwm_new2 -le $pwm_min2_1 ]]
  then
         pwm_new2=$pwm_min2_1
      fi
 }
 fi
echo "$pwm_new2" > "$pwm2path" &
#echo pwm_new2 = "$pwm_new2"
#echo I2 var = $I2
#echo I2 file = $(<data/I2)
#deetee[2]=$(date '+%S%N')
 } &
 
        if [[ T0 -gt Thot]]
        then
            {
         K=$((T0 - Thot))
         j=$((K / Tstep))
                   if [[ $j -ge "$numfreq" ]]
             then
                      j="$numfreq"
                 elif [[ $j -le 0 ]]
             then
                      j=0
                   fi
         t=$(echo "$dtsave / (2 * $j)" | bc -l) #poll faster when throttling
         echo new j "$j"
         echo new freq "${freq_list[$j]}"

            for z in $(seq 0 "$cores")
              do cpufreq-set -c "$z" -u "${freq_list[$j]}"
            done
            fi
            }
################################end of pwm2##################
 }
done
#loop broken for cooling and reinitialisation

echo Too hot, fans on max
echo "$pwm_max1" > "$pwm1path" &
echo "$pwm_max2" > "$pwm2path" &
echo 0 > "$pwm1en"
echo 0 > "$pwm2en"


until [[ "$T0" -lt "$Tmaxhyst" ]]
  do :
  { 
         T0=$(<$temp1)
         echo temp "$T0"
         {
         K=$((T0 - Thot))
         j=$((K / Tstep))
                   if [[ $j -ge "$numfreq" ]]
             then
                      j="$numfreq"
                 elif [[ $j -le 0 ]]
             then
                      j=0
                   fi
         t=$(echo "$dtsave / (2 * $j)" | bc -l) #poll faster when throttling
         echo new j "$j"
         echo new freq "${freq_list[$j]}"

            for z in $(seq 0 "$cores")
              do cpufreq-set -c "$z" -u "${freq_list[$j]}"
            done
            }
         sleep "$t"
 }
done
sleep "$coolsleep"
exec "$0" #start from the beginning when cool. the config will apply changes too.
