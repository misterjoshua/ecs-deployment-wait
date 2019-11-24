#!/bin/bash -e

function log() {
    echo "$1" >&2
}

function die() {
    log "$1"
    exit 1
}

function testCommands() {
    [ ! -z "$(command -v jq)" ] || die "The 'jq' command is missing."
    [ ! -z "$(command -v aws)" ] || die "The the 'aws' command is missing."
    [ ! -z "$(command -v date)" ] || die "The the 'date' command is missing."
}

function describeService() {
    ECS_CLUSTER=${ECS_CLUSTER:-cluster}
    ECS_SERVICE=${ECS_SERVICE:-service}

    SERVICE=$(aws ecs describe-services $AWS_PROFILE_ARG --cluster $ECS_CLUSTER --services $ECS_SERVICE)
    serviceIsValid <<<$SERVICE || return 1
    cat <<<$SERVICE
}

function serviceIsValid() {
    [ "true" = "$(jq '.services | length > 0')" ]
}

function serviceNumPrimary() {
    jq '[ .services[].deployments[] | select(.status == "PRIMARY") | .runningCount ] | add // 0' --raw-output
}

function serviceNumActive() {
    jq '[ .services[].deployments[] | select(.status == "ACTIVE") | .runningCount ] | add // 0' --raw-output
}

function serviceNumTotal() {
    jq '[ .services[].deployments[] | .runningCount ] | add // 0' --raw-output
}

function serviceIsStable() {
    [ "true" = "$(jq '([.services[].deployments[]] | length == 1) and ([.services[].deployments[] | select(.runningCount == .desiredCount)] | length == 1)')" ]
}

function now() {
    date +%s
}

function waitForDeployment() {
    TIMEOUT=${TIMEOUT:-300}
    INTERVAL=${INTERVAL:-5}

    log "Started: Time=$(date), Timeout=$TIMEOUT seconds"

    START_TIME=$(now)
    while true; do
        SERVICE=$(describeService)
        (( $? == 0 )) || die "Couldn't describe the service."

        NUM_PRIMARY=$(serviceNumPrimary <<<$SERVICE)
        NUM_ACTIVE=$(serviceNumActive <<<$SERVICE)
        NUM_TOTAL=$(serviceNumTotal <<<$SERVICE)
        let "ELAPSED=$(now) - START_TIME"

        log "Deployment task counts: Primary=$NUM_PRIMARY, Active=$NUM_ACTIVE, Total=$NUM_TOTAL; Elapsed: $ELAPSED seconds"

        if serviceIsStable <<<$SERVICE; then
            # Deployment finished
            return 0
        elif (( ELAPSED > TIMEOUT )); then
            log "Timeout $TIMEOUT seconds. (actual: $ELAPSED)"
            return 1
        else
            # Deployment not done yet. Check again in a bit.
            let "COUNT++"
            sleep $INTERVAL
        fi
    done
}

function selftest() {
    log "Beginning self test."

    log "Saving mock function originals."
    ORIG_describeService=$(declare -f describeService)
    ORIG_serviceNumActive=$(declare -f serviceNumActive)
    ORIG_serviceNumPrimary=$(declare -f serviceNumPrimary)
    ORIG_serviceNumTotal=$(declare -f serviceNumTotal)
    ORIG_serviceIsStable=$(declare -f serviceIsStable)

    function describeService() { echo ""; }
    function serviceNumTotal() {
        let "OUT=$(serviceNumActive) + $(serviceNumPrimary)"
        echo $OUT
    }
    function serviceIsStable() {
        (( $(serviceNumPrimary) == 2 && $(serviceNumActive) == 0 ))
    }

    #

    log "Testing that waitForDeploy can timeout."
    function serviceNumActive() { echo 2; }
    function serviceNumPrimary() { echo 0; }

    TIMEOUT=2
    TOLERANCE_SECONDS=2
    START=$(now)
    TIMEOUT=$TIMEOUT INTERVAL=1 waitForDeployment && die "Timeout didn't occur." || log "Timeout test succeeded."
    END=$(now)

    #

    log "Testing that waiting detects a completed ECS cutover."

    # This is the simulation:
    # Start: 0 primary, 2 active
    # After primary delay: 2 primary, 2 active
    # After cutover delay: 2 primary, 0 active (appropriate time to exit)
    PRIMARY_DELAY_SECONDS=3
    function serviceNumPrimary() { (( $(now) > START+PRIMARY_DELAY_SECONDS )) && echo 2 || echo 0; }
    CUTOVER_DELAY_SECONDS=7
    function serviceNumActive() { (( $(now) < START+CUTOVER_DELAY_SECONDS )) && echo 2 || echo 0; }

    START=$(now)
    TIMEOUT=10 INTERVAL=1 waitForDeployment || die "Wait for deployment shouldn't have failed in cutover simulation."
    END=$(now)

    TOLERANCE_SECONDS=2
    (( END <= START+CUTOVER_DELAY_SECONDS+TOLERANCE_SECONDS )) || die "waitForDeploy waited longer than the time."
    (( END >= START+CUTOVER_DELAY_SECONDS )) || die "waitForDeploy didn't wait for the cutover."
    log "Cutover test succeeded."

    #

    log "Restoring original functions."
    eval "$ORIG_describeService"
    eval "$ORIG_serviceNumActive"
    eval "$ORIG_serviceNumPrimary"
    eval "$ORIG_serviceNumTotal"
    eval "$ORIG_serviceIsStable"
}

###############
# Script begins
###############

if [ "$1" = "selftest" ]; then
    selftest || die "Self test failed."
    exit 0
fi

testCommands || die "Missing commands necessary to run this script."
waitForDeployment && log "Deployment finished." || die "Deployment didn't succeed."
