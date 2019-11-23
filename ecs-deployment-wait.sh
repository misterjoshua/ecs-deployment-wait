#!/bin/bash -e

function testCommands() {
    [ ! -z "$(command -v jq)" ] || die "The 'jq' command is missing"
    [ ! -z "$(command -v aws)" ] || die "The the 'aws' command is missing"
}

function describeService() {
    ECS_CLUSTER=${ECS_CLUSTER:-cluster}
    ECS_SERVICE=${ECS_SERVICE:-service}

    [ ! -z "$AWS_PROFILE" ] && AWS_PROFILE_ARG="--profile $AWS_PROFILE"
    aws ecs describe-services $AWS_PROFILE_ARG --cluster $ECS_CLUSTER --services $ECS_SERVICE || exit 1
}

function parseNumPrimary() {
    jq '[ .services[].deployments[] | select(.status == "PRIMARY") | .runningCount ] | add // 0' --raw-output
}

function parseNumActive() {
    jq '[ .services[].deployments[] | select(.status == "ACTIVE") | .runningCount ] | add // 0' --raw-output
}

function parseNumTotal() {
    jq '[ .services[].deployments[] | .runningCount ] | add // 0' --raw-output
}

function now() {
    date +%s
}

function die() {
    log "$1"
    exit 1
}

function log() {
    echo "$1" >&2
}

function waitForDeployment() {
    TIMEOUT_SECONDS=${TIMEOUT:-10}
    
    log "Started: Time=$(date), Timeout=$TIMEOUT_SECONDS seconds"
    
    START_TIME=$(now)
    while true; do
        SERVICE=$(describeService)
        NUM_PRIMARY=$(parseNumPrimary <<<$SERVICE)
        NUM_ACTIVE=$(parseNumActive <<<$SERVICE)
        NUM_TOTAL=$(parseNumTotal <<<$SERVICE)
        let "ELAPSED_SECONDS=$(now) - START_TIME"

        log "Deployment task counts: Primary=$NUM_PRIMARY, Active=$NUM_ACTIVE, Total=$NUM_TOTAL; Elapsed: $ELAPSED_SECONDS seconds"
        
        if (( NUM_PRIMARY > 0 && NUM_ACTIVE == 0 )); then
            # Deployment finished
            return 0
        elif (( ELAPSED_SECONDS > TIMEOUT_SECONDS )); then
            log "Timeout $TIMEOUT_SECONDS seconds (actual: $ELAPSED_SECONDS)"
            return 1
        else
            # Deployment not done yet. Check again in a bit.
            let "COUNT++"
            sleep 1
        fi
    done
}

function selftest() {
    log "Beginning self test"

    log "Saving mock function originals"
    ORIG_PARSENUM=$(declare -f describeService)
    ORIG_PARSENUMACTIVE=$(declare -f parseNumActive)
    ORIG_PARSENUMPRIMARY=$(declare -f parseNumPrimary)
    ORIG_PARSENUMTOTAL=$(declare -f parseNumTotal)

    function describeService() { echo ""; }
    function parseNumTotal() {
        let "OUT=$(parseNumActive) + $(parseNumPrimary)"
        echo $OUT
    }

    #

    log "Testing that waitForDeploy can timeout"
    function parseNumActive() { echo 2; }
    function parseNumPrimary() { echo 0; }
    
    TIMEOUT=2
    TOLERANCE_SECONDS=2
    START=$(now)
    TIMEOUT=$TIMEOUT waitForDeployment && die "Timeout didn't occur" || log "Timeout test succeeded"
    END=$(now)

    #

    log "Testing that waiting detects a completed ECS cutover"
    
    # This is the simulation:
    # Start: 0 primary, 2 active
    # After primary delay: 2 primary, 2 active
    # After cutover delay: 2 primary, 0 active (appropriate time to exit)
    PRIMARY_DELAY_SECONDS=3
    function parseNumPrimary() { (( $(now) > START+PRIMARY_DELAY_SECONDS )) && echo 2 || echo 0; }
    CUTOVER_DELAY_SECONDS=5
    function parseNumActive() { (( $(now) < START+CUTOVER_DELAY_SECONDS )) && echo 2 || echo 0; }
    
    START=$(now)
    TIMEOUT=10 waitForDeployment || die "Wait for deployment shouldn't have failed in cutover simulation"
    END=$(now)
    
    TOLERANCE_SECONDS=2
    (( END <= START+CUTOVER_DELAY_SECONDS+TOLERANCE_SECONDS )) || die "waitForDeploy waited longer than the time."
    (( END >= START+CUTOVER_DELAY_SECONDS )) || die "waitForDeploy didn't wait for the cutover"

    #

    log "Restoring original functions"
    eval "$ORIG_PARSENUM"
    eval "$ORIG_PARSENUMACTIVE"
    eval "$ORIG_PARSENUMPRIMARY"
    eval "$ORIG_PARSENUMTOTAL"
}

###############
# Script begins
###############

if [ "$1" = "selftest" ]; then
    selftest || die "Self test failed"
    exit 0
fi

testCommands || die "Missing commands necessary to run this script."
waitForDeployment && log "Deployment finished" || die "Deployment didn't succeed."