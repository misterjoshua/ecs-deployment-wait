#!/bin/bash -e

function testCommands() {
    [ ! -z "$(command -v jq)" ] || die "The 'jq' command is missing"
    [ ! -z "$(command -v aws)" ] || die "The the 'aws' command is missing"
}

function describeService() {
    ECS_CLUSTER=${ECS_CLUSTER:-cluster}
    ECS_SERVICE=${ECS_SERVICE:-service}

    SERVICE=$(aws ecs describe-services $AWS_PROFILE_ARG --cluster $ECS_CLUSTER --services $ECS_SERVICE)
    parseIsValid <<<$SERVICE || return 1
    cat <<<$SERVICE
}

function parseIsValid() {
    [ "$(jq '.services | length > 0')" = "true" ]
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

function parseIsStable() {
    jq '([.services[].deployments[]] | length == 1) and ([.services[].deployments[] | select(.runningCount == .desiredCount)] | length == 1)'
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
    TIMEOUT=${TIMEOUT:-300}
    INTERVAL=${INTERVAL:-5}

    log "Started: Time=$(date), Timeout=$TIMEOUT seconds"

    START_TIME=$(now)
    while true; do
        SERVICE=$(describeService)
        (( $? == 0 )) || die "Couldn't describe the service"

        NUM_PRIMARY=$(parseNumPrimary <<<$SERVICE)
        NUM_ACTIVE=$(parseNumActive <<<$SERVICE)
        NUM_TOTAL=$(parseNumTotal <<<$SERVICE)
        let "ELAPSED=$(now) - START_TIME"

        log "Deployment task counts: Primary=$NUM_PRIMARY, Active=$NUM_ACTIVE, Total=$NUM_TOTAL; Elapsed: $ELAPSED seconds"

        if [ "$(parseIsStable <<<$SERVICE)" = "true" ]; then
            # Deployment finished
            return 0
        elif (( ELAPSED > TIMEOUT )); then
            log "Timeout $TIMEOUT seconds (actual: $ELAPSED)"
            return 1
        else
            # Deployment not done yet. Check again in a bit.
            let "COUNT++"
            sleep $INTERVAL
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
    ORIG_PARSEISSTABLE=$(declare -f parseIsStable)

    function describeService() { echo ""; }
    function parseNumTotal() {
        let "OUT=$(parseNumActive) + $(parseNumPrimary)"
        echo $OUT
    }
    function parseIsStable() {
        (( $(parseNumPrimary) == 2 && $(parseNumActive) == 0 )) && echo "true" || echo "false"
    }

    #

    log "Testing that waitForDeploy can timeout"
    function parseNumActive() { echo 2; }
    function parseNumPrimary() { echo 0; }

    TIMEOUT=2
    TOLERANCE_SECONDS=2
    START=$(now)
    TIMEOUT=$TIMEOUT INTERVAL=1 waitForDeployment && die "Timeout didn't occur" || log "Timeout test succeeded"
    END=$(now)

    #

    log "Testing that waiting detects a completed ECS cutover"

    # This is the simulation:
    # Start: 0 primary, 2 active
    # After primary delay: 2 primary, 2 active
    # After cutover delay: 2 primary, 0 active (appropriate time to exit)
    PRIMARY_DELAY_SECONDS=3
    function parseNumPrimary() { (( $(now) > START+PRIMARY_DELAY_SECONDS )) && echo 2 || echo 0; }
    CUTOVER_DELAY_SECONDS=7
    function parseNumActive() { (( $(now) < START+CUTOVER_DELAY_SECONDS )) && echo 2 || echo 0; }

    START=$(now)
    TIMEOUT=10 INTERVAL=1 waitForDeployment || die "Wait for deployment shouldn't have failed in cutover simulation"
    END=$(now)

    TOLERANCE_SECONDS=2
    (( END <= START+CUTOVER_DELAY_SECONDS+TOLERANCE_SECONDS )) || die "waitForDeploy waited longer than the time."
    (( END >= START+CUTOVER_DELAY_SECONDS )) || die "waitForDeploy didn't wait for the cutover"
    log "Cutover test succeeded."

    #

    log "Restoring original functions"
    eval "$ORIG_PARSENUM"
    eval "$ORIG_PARSENUMACTIVE"
    eval "$ORIG_PARSENUMPRIMARY"
    eval "$ORIG_PARSENUMTOTAL"
    eval "$ORIG_PARSEISSTABLE"
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
