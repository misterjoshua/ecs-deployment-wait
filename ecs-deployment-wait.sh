#!/bin/bash -e

function describeService() {
    AWS_PROFILE=${AWS_PROFILE:-}
    ECS_CLUSTER=${ECS_CLUSTER:-cluster}
    ECS_SERVICE=${ECS_SERVICE:-service}

    [ ! -z "$AWS_PROFILE" ] && AWS_PROFILE_ARG="--profile $AWS_PROFILE" || unset AWS_PROFILE
    aws ecs describe-services $AWS_PROFILE_ARG --cluster $ECS_CLUSTER --services $ECS_SERVICE
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

function waitForDeployment() {
    echo "Started: $(date)"
    
    TIMEOUT=${TIMEOUT:-300}
    for (( COUNT=0; COUNT<TIMEOUT; COUNT++)); do
        SERVICE=$(describeService)
        NUM_PRIMARY=$(parseNumPrimary <<<$SERVICE)
        NUM_ACTIVE=$(parseNumActive <<<$SERVICE)
        NUM_TOTAL=$(parseNumTotal <<<$SERVICE)
        
        if (( NUM_PRIMARY > 0 && NUM_ACTIVE == 0 )); then
            echo "Deployment has finished."
            break
        else
            echo -e "Deployment task counts: Primary=$NUM_PRIMARY, Active=$NUM_ACTIVE, Total=$NUM_TOTAL"
            sleep 1
        fi
    done

    echo "Finished: $(date)"
}

waitForDeployment