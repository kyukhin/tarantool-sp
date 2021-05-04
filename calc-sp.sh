#!/bin/bash

# TODO: case insensitive labels/columns
# TODO: report NORMAL issue links

if [[ $# -eq 1 && $# -eq 2 ]]; then
    echo "Usage: $0 <project> [<team>]"
    echo "Example: $0 35"
    echo "Example: $0 48 teamC"
    exit 1
fi

proj_num=$1

if [ $# -eq 1 ]; then
    team="all"
else
    team="$2"
fi
 
login=$USER
token=`cat token`
auth="${login}:${token}"

# Fetch _real_ project ID
id=`curl -s \
         -H "Accept: application/vnd.github.v3+json" \
	 -H "Accept: application/vnd.github.inertia-preview+json" \
         -u "${auth}" \
         "https://api.github.com/orgs/tarantool/projects" |jq -r "map(select(.number == $proj_num)) |.[0].id"`

if [ $id == "null" ]
then
    echo "Unable to find project w/ id $proj_num. Shot yourself."
    exit 1;
fi

echo "Found internal project id: $id"

# Fetch list of columns
columns=`curl -s \
              -H "Accept: application/vnd.github.v3+json" \
	      -H "Accept: application/vnd.github.inertia-preview+json" \
              -u "${auth}" \
              "https://api.github.com/projects/$id/columns"`

numcol=`echo $columns | jq length`

totalsp=0
# Walk through project columns
echo "Found columns: $numcol"
for (( i=0; i<$numcol; i++ )) ; do
    name=`echo $columns | jq -r .[$i].name`
    if [[ $name == "Backlog" || $name == "Done" ]] ; then
	echo "Skipping column: $name"
	continue
    fi
    echo "Walking through column: $name"

    idcol=`echo $columns | jq -r .[$i].id`
    if [[ $idcol == "null" ]] ; then
	echo "Strange, there's no id for existing column $name. Go fuck yourself."
	continue
    fi

    continue=1
    pagenum=1
    while : ; do
	cards=`curl -s -H "Accept: application/vnd.github.v3+json" \
		       -H "Accept: application/vnd.github.inertia-preview+json" \
		       -u "${auth}" \
		       "https://api.github.com/projects/columns/$idcol/cards?page=$pagenum"`
	echo "https://api.github.com/projects/columns/$idcol/cards?page=$pagenum"

	# Loop it bitch
	numcard=`echo $cards |jq length`
	if [[ $numcard == 0 ]] ; then	    
	    break
	fi
	echo "Looping over cards, page: $pagenum, count: $numcard"
	for (( k=0; k<$numcard; k++ )) ; do
	    card=`echo $cards |jq -r ".[$k]"`
	    issueurl=`echo $cards |jq -r ".[$k].content_url"`
	    if [ $issueurl == "null" ] ; then
		echo "!!!ACHTUNG!!! Don't use cards on our boards, bitch! They doesn't allow to set labels! Kill yourself!"
		continue
	    fi
	    
	    issue=`curl -s -H "Accept: application/vnd.github.v3+json" \
		    -H "Accept: application/vnd.github.inertia-preview+json" \
         	    -u "${auth}" \
         	    $issueurl`

	    labels=`echo $issue |jq -r .labels`
	    echo -n "$issueurl ... "
	    # echo $labels |jq -r .
	    # Check if team is right
	    if [[ $team != "all" && `echo $labels |jq -r "map(select(.name == \"$team\")) |.[0].name"` == "null" ]] ; then
		echo Skip
		continue
	    fi
	    echo -n "Use ... "

	    # Walk through labels, search for SP. Skip ititiatives
	    numlab=`echo $labels |jq length`
	    skip=0
	    sp="null"
	    for (( j=0; j<$numlab; j++ )) ; do
		lab=`echo $labels | jq -r ".[$j].name"`
		if [[ "$lab" =~ ^([0-9]+)sp$ ]]; then
		    sp=$lab
		    numsp=${BASH_REMATCH[1]}
		    echo "Found $numsp SP"
		fi
		if [[ $lab == "Initiative" ]]; then
		    echo "Skipping initiative $issueurl"
		    skip=1
		fi
	    done
	    if [[ $skip == 0 && $sp == "null" ]]; then
		echo "!!!ACHTUNG!!! Warning, you forgot to set SP for the issue"
		continue
	    fi
	    if [[ $skip == 0 ]]; then
		let "totalsp = $totalsp + $numsp"
	    fi
	done
	let pagenum++
    done
done

echo "**********"
echo "Total SP for $team: $totalsp"
echo "**********"

