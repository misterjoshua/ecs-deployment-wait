[![Build Status](https://travis-ci.org/misterjoshua/ecs-deployment-wait.svg?branch=master)](https://travis-ci.org/misterjoshua/ecs-deployment-wait)

# ECS Deployment Waiter Script

This script waits for an Amazon ECS service to [become stable](https://docs.aws.amazon.com/cli/latest/reference/ecs/wait/services-stable.html) after a deployment, such as in a CD pipeline deployment step. The functionality of this script is similar to `aws ecs wait services-stable`, except that it provides a configurable polling interval, configurable timeout, and verbose output.

Like `aws ecs wait services-stable`, this script considers a service stable when there is one service deployment and that deployment's running count of tasks equals its desired count. The script exits with an error code when a timeout occurs.

> Note: This script uses the `aws` and `jq` commands, expecting them in the path.

## Example usage

Run the script locally with the default AWS profile, a one second interval, and ten second timeout:

```
$ ECS_CLUSTER=clustername ECS_SERVICE=servicename INTERVAL=1 TIMEOUT=10 \
./ecs-deployment-wait.sh
Started: Time=Sat Nov 23 17:44:29 MST 2019, Timeout=10 seconds
Deployment task counts: Primary=0, Active=2, Total=2; Elapsed: 0 seconds
Deployment task counts: Primary=0, Active=2, Total=2; Elapsed: 1 seconds
Deployment task counts: Primary=0, Active=2, Total=2; Elapsed: 2 seconds
Deployment task counts: Primary=0, Active=2, Total=2; Elapsed: 3 seconds
Deployment task counts: Primary=2, Active=2, Total=4; Elapsed: 4 seconds
Deployment task counts: Primary=2, Active=2, Total=4; Elapsed: 5 seconds
Deployment task counts: Primary=2, Active=2, Total=4; Elapsed: 6 seconds
Deployment task counts: Primary=2, Active=0, Total=2; Elapsed: 7 seconds
Deployment finished
```

Inject AWS credentials and a region:

```
AWS_ACCESS_KEY_ID=YOUR_KEY_ID_HERE \
AWS_SECRET_ACCESS_KEY=YOUR_KEY_HERE_DONT_PUT_IT_IN_GIT \
AWS_DEFAULT_REGION=aws-region-1 \
ECS_CLUSTER=clustername \
ECS_SERVICE=servicename \
./ecs-deployment-wait.sh
...
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
| `INTERVAL` | The polling interval in seconds. (Default: 5 seconds)

The AWS CLI in turn accepts the following environment variables:

| Environment Variable | Description |
| -------------------- | ----------- |
| `AWS_ACCESS_KEY_ID` & `AWS_SECRET_ACCESS_KEY` | AWS IAM credentials.
| `AWS_PROFILE` | Which configuration profile to access.
| `AWS_DEFAULT_REGION` | Which AWS region to use

> Note: Complete AWS CLI documentation is available in the official [AWS CLI User Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html).
