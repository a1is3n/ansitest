#!/bin/bash

# Select from a list of known virtualbox VMs, which to stop/start - can handle multiple like 1,3,5

# REQUIRES VboxManage, tr, pr, awk, sed, bash version > 3.2.57(1)-release

#NOTE running vms that are still "coming up" from disk-saved state are NOT
# considered as "running" until they are all the way up!

# This script will XOR the state of a VM - if running, it will Stop it; if not running, it will Start it.
# Entering "all" will STOP all running VMs

# NOTE Cleaning up the logfile when it gets too big is left as an exercise for the end-user :B
logf=$HOME/vms-stopped-started.log
vbm=VBoxManage

debugg=0

# failexit.mrg
function failexit () {
  echo '! Something failed! Code: '"$1 $2" # code # (and optional description)
  exit $1
}

function stopvm () {
  echo "$(date) - $(whoami) Stopping VM ${vm} / ${vmuuid}" |tee -a $logf
#[ $debugg -eq 0 ] && time $vbm controlvm $stopthis savestate && echo "$vm is now stopped - $(date)" |tee -a $logf
[ $debugg -eq 0 ] && time $vbm controlvm $vmuuid savestate && echo "$(date) - $vm is now stopped" |tee -a $logf
# Dont actually stop any if debugging
}

function startvm () {
  echo "$(date) - $(whoami) Starting VM ${vm} / ${vmuuid}" |tee -a $logf
#[ $debugg -eq 0 ] && time $vbm startvm ${vm} && echo "$vm is now running - $(date)" |tee -a $logf
[ $debugg -eq 0 ] && time $vbm startvm $vmuuid && echo "$(date) - $vm is now running" |tee -a $logf
# Dont actually start any if debugging
}


########## MAIN
if [ "$1" = "s" ] || [ "$1" = "" ]; then
# select ; REF: https://www.baeldung.com/linux/reading-output-into-array
  runtest=$($vbm list runningvms)
  if [ "$runtest" = "" ]; then
    echo "FYI: No VMs are currently running under ID $(whoami)"
  else
    echo "( $(echo "$runtest" |grep -c \}) ) VMs are currently running" # ya, its a hack :B
  fi

  OIFS=$IFS
  IFS=$'\n'
# populate array with list of known VMs
  declare -a vmlist=( $($vbm list vms |tr -d '"' |sort) )
#LiveCD--64 {hexnum}

  maxvmnum=${#vmlist[@]} # of elements in array

  IFS=$OIFS

cols=$(stty size |awk '{print $2}') # columns / terminal size - REF: https://stackoverflow.com/questions/1780483/lines-and-columns-environmental-variables-lost-in-a-script
echo "o-> Utility to change the state of a virtualbox VM - stop if running, start if not running <-o"  
  # dump array - REF: https://opensource.com/article/18/5/you-dont-know-bash-intro-bash-arrays
  for i in ${!vmlist[@]}; do
     echo "$i ${vmlist[$i]}"
  done |tr -d '"{}' |pr -2 -t -w $cols |awk 'NF>0'
# Remove quotes and brackets from output, filter thru 'pr', no blank lines
# ISSUE - interesting, $COLUMNS is not avail at runtime! but we can get from stty size awk=2
# FEATURE: fancy display in 2 columns sorted vertically  

#  done |tr -d '"{}' |awk '{print $1" "$2" "$3}' |paste - - |column -t
# Old way - fancy display in 2 columns; $1=number of entry, $2=nameofvm, $3=vmUUID

  echo -n "Enter comma-separated number(s) of VM to XOR, or all to stop-all: "
  read vmn
  echo "You selected $vmn"
else
  vm="$1"
fi

[ $debugg -gt 0 ] && set -x

# auto-lowercase it for convenience
vmn=${vmn,,}
test4comma=$(echo $vmn |grep -c ',')

if [ "$vmn" = "all" ]; then
# we are assuming there is no concievable way an end-user would want to XOR the state of every.single.vm
  STOPALLVMS.sh # external script, needs to be in PATH
  exit;

elif [ $test4comma -gt 0 ]; then
# vmn is comma-separated, multiple "1,3,5"
  procthese="$vmn"
# SANITY
  procthese=$(echo $procthese |sed 's/,,/,/g') # get rid of multiple commas JIC
  procthese=$(echo $procthese |sed 's/ //g') # get rid of spaces
    
# self-shortening loop, like bash "shift"
  stopafterme=0
  
  while [ ${#procthese} -gt 0 ]; do
# check length 

    if [ "${procthese:0:1}" = "," ]; then
# if 1st char , skip it and gimme the rest    
#[ $debugg -gt 0 ] && echo "TRIPPED 1stchar comma"
      procthese=${procthese:1}
#    else
#[ $debugg -gt 0 ] && echo "NOTRIP 1stchar comma" 
    fi

    procthisvmnum=${procthese%%,*} # Deletes longest match of $substring from back of $string; 1,3,5 = get 1
[ "$procthisvmnum" = "" ] && failexit 99 "procthisvmnum is blank!"
 
# sanity - REF: https://stackoverflow.com/questions/806906/how-do-i-test-if-a-variable-is-a-number-in-bash
    regexp='^[0-9]+$' # yes, I know it should probably go outside the loop but easier to read
    if ! [[ $procthisvmnum =~ $regexp ]] ; then
      echo "Error: $procthisvmnum is Not a number" |tee -a $logf
      procthese=$(echo $procthese |sed 's/'$procthisvmnum'//') # take out the bad input
      continue; # next iteration
    fi

#    if [ $procthisvmnum -gt $maxvmnum ]; then 
# we are zero-indexed, remember
    if [ $procthisvmnum -ge $maxvmnum ]; then 
      echo "Invalid VM number $procthisvmnum , outside max known: $maxvmnum" |tee -a $logf
      procthese=$(echo $procthese |sed 's/'$procthisvmnum'//') # take out the bad number
      continue; # next iteration
    fi
    
    vm=${vmlist[$procthisvmnum]} # get name + uuid from "known" array
[ "$vm" = "" ] && failexit 45 "$vm not found in list!"    
    vmuuid=$(echo $vm |tr -d '{}' |awk '{print $2}') # take out brackets and only print uuid
    vm=$(echo $vm |tr -d '"' |awk '{print $1}') # take out quotes and only print name, note we are changing the vbl so uuid has 2b b4

# check cur list of Running vms against known array info
    stopthis=$(VBoxManage list runningvms |awk '/'$vm'/ {print $2}' |tr -d '{}') # get vm uuid + remove brackets
    if [ "$stopthis" = "" ]; then
# start it
      startvm $vmuuid # $vm
    else
      stopvm $vmuuid # $stopthis 
    fi
    
    [ $stopafterme -gt 0 ] && break;
    
    procthese=$(echo ${procthese#*,*}) # 1,3,5 take out the 1,
#    [ $(echo $procthese |grep -c ',') -eq 0 ] && let stopafterme=1 # no more commas, last one
    [ $(echo $procthese |grep -c ',') -eq 0 ] && break; # no more commas, last one
#3,5
  done

else
# Single VM, either a number or passed as arg
  if [ "${#vmn}" -gt 0 ]; then 
# check length, user entered selection

# sanity - REF: https://stackoverflow.com/questions/806906/how-do-i-test-if-a-variable-is-a-number-in-bash
    re='^[0-9]+$'
    if ! [[ $vmn =~ $re ]] ; then
      failexit 10 "Error: $vmn is Not a number" 
    fi

    if [ $vmn -gt $maxvmnum ]; then
      echo "Invalid VM number $procthisvmnum , outside max known: $maxvmnum" |tee -a $logf
      failexit 250 "Invalid VM index number"
    fi

    vm=${vmlist[$vmn]}
# get name by number from array - NOTE if this equates to 0 somehow, it still works - was BUG if you enter random text as selection
  fi

  vm=$(echo $vm |tr -d '"' |awk '{print $1}') # take out quotes and only print name

  # take out brackets and only print uuid
  vmuuid=$($vbm list vms |grep ${vm} |awk '{print $2}' |tr -d '{}')
  [ "$vmuuid" = "" ] && failexit 46 "Cannot find uuid for $vm / unknown VM?"

  stopthis=$(VBoxManage list runningvms |awk '/'$vm'/ {print $2}' |tr -d '{}') # remove brackets
  if [ "$stopthis" = "" ]; then
# start it
    startvm $vmuuid # $vm
  else
    stopvm $vmuuid # $stopthis 
  fi

#  stopvm $stopthis
fi

date;

ls -lh $logf

exit;

# 2022.0520 Dave Bechtel
# Adapted from: vbox-selectvm-statechange / vbox-select-stopvm.sh
# Script version: 20220520@1805
# xxx TODO editme ^^

# The script is smart enough to XOR a VM if you pass it the UUID (without the brackets) or vmname as arg :)

# In all cases, we should pass the UUID to stop/start in case of dup vm names to avoid confusion...
# + standardized date format in logfile

# fixed single-vm treatment, check if single-vm index number outside known, dont failexit if no vms are running
# Feature: display sorted vertically with ' pr -2 ' instead of paste

# NOTE this one uses vertical-sorted display and haz Extra Sanity

# The script will not care if you put in the same number two or more times.
