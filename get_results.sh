#!/bin/bash

# contains fish ID's and their labeled species, along with other data
FISH_FILE=fish.csv
if [ ! -f "$FISH_FILE" ]
then
    echo "ERROR: add fish.csv to the current directory, or change"
    echo "       the script to use the proper name of the file"
    exit 1
fi
# contains fish ID's and the file containing DNA test results
FILES_FILE=files.csv
if [ ! -f "$FILES_FILE" ]
then
    echo "ERROR: add files.csv to the current directory, or change"
    echo "       the script to use the proper name of the file"
    exit 1
fi

# contains a copy of this script's output
REPORT_FILE=report.txt
# contains a copy of fish.csv, but with added columns showing the top 3 queried
# species guesses
REPORT_CSV=fish_report.csv

log() {
    echo -e "$1" | tee --append report.txt >&2
    # I prefer:
    ## tee --append report.txt <<<"$@"
    # but vim is making syntax highlighting a pain if I do that :/
    # (even though it's valid).
    # I'll change it back when(if) I fix vim.
}
debug() {
    log "=== $1 ==="
}
log "[Started $(date)]"
log ""

getFishInfo() { # (id)
    ## Assumptions:
    ## fish IDs are in the first col, and start each line in the file
    strings "$FISH_FILE" | grep "^$1" | head -1
}

getSpeciesGuess() { # (csv info string)
    echo "$1" | awk -F, '{print $2}'
}

getFishFilePrefixes() { # (id)
    strings "$FILES_FILE" | grep ",$1" | awk -F, '{print $3}'
}

getFishSequence() { # (file prefix)
    strings data/$1* | grep term | sed 's/term//'
}

queryNIH() { # (sequence)
    REQUEST_ID=`./query_nih.sh "$1"`
    # be nice
    debug "REQUEST_ID: $REQUEST_ID"
    sleep 1m
    curl 'https://blast.ncbi.nlm.nih.gov/Blast.cgi?CMD=Get&RID='$REQUEST_ID 2>/dev/null \
        | grep 'class="tl"' \
        | head -3 \
        | sed 's/.*">\(.*\)<\/div>/\1/'
}



# clear report.csv, and get it ready for data
head -1 $FISH_FILE > $REPORT_CSV

### 1. Determine how many fish there are.
## Assumptions:
##    * Consecutive, unique fish IDs
##    * CSV doesn't end with newline character, so wc will report 1 less than
##      actual number of CSV entries
##    * One of the lines (the first) is a descriptive line with no fish ID
## Note: having too high an estimate is better than having too low of one
NUM_FISH=`wc -l fish.csv | awk '{print $1}'`

### 2. Figure out species for each fish, and report it
## Assumptions:
##    * Fish IDs are 0-padded 3-digit numbers
for FISH_ID in `seq -w 001 $NUM_FISH`
do
    FISH_INFO=$(getFishInfo $FISH_ID)
    debug "FISH_INFO: $FISH_INFO"
    FISH_LABEL=`getSpeciesGuess "$FISH_INFO"`
    debug "FISH_LABEL: $FISH_LABEL"
    [ -z "$FISH_LABEL" ] && continue # skip if no label
    log "Fish [$FISH_ID] labeled as '$FISH_LABEL' tests as..."
    GUESSES_FILE=`mktemp`
    for PREFIX in `getFishFilePrefixes $FISH_ID`
    do
        debug "PREFIX: $PREFIX"
        FISH_SEQUENCE=`getFishSequence $PREFIX`
        debug "FISH_SEQUENCE: $FISH_SEQUENCE"
        [ -z "$FISH_SEQUENCE" ] && continue # skip if no fish seq
        queryNIH "$FISH_SEQUENCE" |
        while read GUESS
        do
            log "\t[$PREFIX] $GUESS"
            echo -n ",\"$GUESS\"" >> "$GUESSES_FILE"
        done
    done
    # no guesses = no data file?
    # if not, it's something more sinister...
    if [ "$(wc -c "$GUESSES_FILE" | awk '{print $1}')" -le 3 ]
    then
        log "\tNothing (no data file?)"
    fi
    # append current row, with guesses
    echo "$FISH_INFO$(cat $GUESSES_FILE)" >> $REPORT_CSV
    rm $GUESSES_FILE
    log ""
done

log "[Finished $(date)]"
