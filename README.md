[![Build Status](https://travis-ci.org/misterjoshua/ecs-deployment-wait.svg?branch=master)](https://travis-ci.org/misterjoshua/ecs-deployment-wait)

# ECS Deployment Waiter Bash Script

This bash script waits for an Amazon ECS service deployment to complete. You can use this to cause a CD pipeline to wait until deployment finishes before ending a pipeline step.

This script uses the `aws` command and `jq` to poll ECS services for the deployment to complete. This script considers a deployment done when there are primary tasks runnung (the new tasks) and no active tasks (the old tasks). The script exits with an error code when a timeout occurs.

## Example usage

Run the script locally with the AWS profile:

```
ECS_CLUSTER=clustername \
ECS_SERVICE=servicename \
./ecs-deployment-wait.sh
```

Run the script with Bash Script as a Service:

```
ECS_CLUSTER=clustername \
ECS_SERVICE=servicename \
bash <(https://raw.githubusercontent.com/misterjoshua/ecs-deployment-wait/master/ecs-deployment-wait.sh)
```

## Configuration

Configuration is done through environment variables passed to this script.

| Environment Variable | Description |
| -------------------- | ----------- |
| `ECS_CLUSTER` | The name of the ECS cluster
| `ECS_SERVICE` | The name of the ECS service to monitor.
| `TIMEOUT` | How many seconds the script will wait before timing out. (Default: 300 seconds)

The AWS CLI in turn accepts the following environment variables:

| Environment Variable | Description |
| -------------------- | ----------- |
| `AWS_ACCESS_KEY_ID` & `AWS_SECRET_ACCESS_KEY` | AWS IAM credentials.
| `AWS_PROFILE` | Which configuration profile to access.
| `AWS_DEFAULT_REGION` | Which AWS region to use

> Note: Complete AWS CLI documentation is available in the official [AWS CLI User Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html).