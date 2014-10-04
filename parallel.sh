#!/usr/bin/env bash
################################################################################
# This script runs multiple ssh instances at the same time, starting as many 
# as the pparallel variable allows. It will make a mess of your /tmp directory 
# and you should probably use paralell-ssh instead.
################################################################################
# TODO 
#		better logging - env variable?
#		better way to handle multi line output
#		report on diffs
#		handle muli command
#       push script? or series of commands?

# Initalize Defaults, flags will override.
summary=0
user="root"
pparallel=5  # How many to run at once.
timeout=10   # SSH connection timeout
ptimeout=600   # Process timeout (if ssh succeeds, but local process takes too long) .. NOT IN USE
host_list=""
breaker="####################"
epoch=$(date +%s)
tempdir="/tmp"
logging=0

# Usage function displays options and arguements.
usage(){
echo "Usage: $0 [OPTIONS] command
OPTIONS:
      -d          set -x
      -c          Command to run.
      -h          Host file to use (default ./hosts).
      -p          Paralell ssh commands to run at once (default 5).
      -s          Summarize the output.
      -u          Username to ssh with (default root).
       "
}



####################
# Get options 
####################
while [ "$1" != "" ]; do
	case $1 in
		-d)
			debug=1
			shift
			;;
		-c)
			command="$2"
			shift 2
			;;
		-h)
			host_file="$2"
			shift 2
			;;
		-l)
			logging=1
			shift 1
			;;
		-p)
			pparallel="$2"
			shift 2
			;;
		-s)
			summary=1
			shift
			;;
		-u)
			user="$2"
			shift 2
			;;
		*)
			usage
			echo "$OPTION is an invalid option."
			exit 1
			;;
	esac
done

# Get list of hosts to run on.
[ "$host_file" == "" ] && {
	[ ! -f ./hosts ] && {
		echo "No hosts file found, or specified."
		usage
		exit 1
	}
	host_file="./hosts" # File to read hosts from
}
# TODO: add test to all clients.

####################
# If we're logging use tee to print output to a log.
####################
no_space=$(echo $command |sed 's/ /_/g')
[ $logging -eq 1 ] && {
	exec 2>&1
	exec > >(tee /$tempdir/${epoch}_${no_space}.txt)
}

[[ "$debug" -eq "1" ]] && set -x

# Checks for defaults.
[ "$command" == "" ] && {
	usage
	echo "You must specify a command."
	exit 1
}

# Checks for defaults.
[ "$host_file" == "" ] && {
	usage
	echo "You must specify a host list or host file."
	exit 1
}
####################
# Function that takes one aguement that is a command to run.
# Uses an epoch date to roughly time the command.
####################
run_command() {
	local host=$1
	local start=$(date +%s)

	# If we want to set process timeout, uncomment, and remove next
	#timeout $ptimeout ssh -o BatchMode=yes -o ConnectTimeout=$timeout $user@$host "$command" >/$tempdir/$host.out 2>/$tempdir/$host.err &

	ssh -o BatchMode=yes -o ConnectTimeout=$timeout $user@$host "$command" >/$tempdir/$host.out 2>/$tempdir/$host.err &
	local pid=$!
	wait $pid # Don't change order, or insert commands between here.
	local rc=$? # Don't change order
	local end=$(date +%s)
	echo $rc >/$tempdir/$host.rc
	echo $(( $end - $start )) > /$tempdir/$host.time
}

####################
# Function that takes arguements and spawns command for each one.
# Uses parallel to determine how many to run at once.
####################
paralellize() {
	# If we have more args to process.
	while [ $# -gt 0 ] ; do
		local job_count=($(jobs -p)) # Use jobs to get array of processes
		if [ ${#job_count[@]} -le $pparallel ] ; then
			run_command $1 &
			shift
		else
			sleep .2
		fi
	done
	wait
}

paralellize $(cat $host_file)

echo $breaker
echo "COMMAND: $command"
echo $breaker

# Loop through and collect results
count=1
for host in $(cat $host_file |grep -v ^#)
do
	# Print output or summarize.
	if [ $summary -eq 1 ]
	then 
		# Summary of command.
		echo -e "[$count]:$host:TIME=$(cat /$tempdir/$host.time)s:RC=$(cat /$tempdir/$host.rc)"
	else 
		# Long version.
		[ -f /$tempdir/$host.out ] && {
			echo -e "$breaker \n$host: $command \n$(cat /$tempdir/$host.out) $(cat /$tempdir/$host.err) \nRC=$(cat /$tempdir/$host.rc) TIME=$(cat /$tempdir/$host.time)s"
		}
	fi

	# Cleanup files created.
	for file in /$tempdir/$host.out /$tempdir/$host.err /$tempdir/$host.rc \
		/$tempdir/$host.time
	do
		[ -f $file ] && {
			rm $file
		}
	done
	count=$(( $count + 1 ))
done

