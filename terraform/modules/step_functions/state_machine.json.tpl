{
  "Comment": "E-Commerce Lakehouse pipeline: Raw -> Bronze -> Silver -> Gold",
  "StartAt": "IngestRawToBronze",
  "States": {

    "IngestRawToBronze": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startJobRun.sync",
      "Parameters": {
        "JobName": "${raw_to_bronze_job}",
        "Arguments": {
          "--EXECUTION_DATE.$": "$.execution_date"
        }
      },
      "Retry": [
        {
          "ErrorEquals": ["Glue.ConcurrentRunsExceededException"],
          "IntervalSeconds": 60,
          "MaxAttempts": 5,
          "BackoffRate": 1.5
        },
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 30,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "NotifyFailure",
          "ResultPath": "$.error"
        }
      ],
      "Next": "BronzeToSilverTransforms"
    },

    "BronzeToSilverTransforms": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "ProductsSilver",
          "States": {
            "ProductsSilver": {
              "Type": "Task",
              "Resource": "arn:aws:states:::glue:startJobRun.sync",
              "Parameters": {
                "JobName": "${products_silver_job}",
                "Arguments": { "--EXECUTION_DATE.$": "$$.Execution.Input.execution_date" }
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 30,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "OrdersSilver",
          "States": {
            "OrdersSilver": {
              "Type": "Task",
              "Resource": "arn:aws:states:::glue:startJobRun.sync",
              "Parameters": {
                "JobName": "${orders_silver_job}",
                "Arguments": { "--EXECUTION_DATE.$": "$$.Execution.Input.execution_date" }
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 30,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "OrderItemsSilver",
          "States": {
            "OrderItemsSilver": {
              "Type": "Task",
              "Resource": "arn:aws:states:::glue:startJobRun.sync",
              "Parameters": {
                "JobName": "${order_items_silver_job}",
                "Arguments": { "--EXECUTION_DATE.$": "$$.Execution.Input.execution_date" }
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 30,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ],
              "End": true
            }
          }
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "NotifyFailure",
          "ResultPath": "$.error"
        }
      ],
      "ResultPath": null,
      "Next": "SilverToGoldTransforms"
    },

    "SilverToGoldTransforms": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "DailyRevenueGold",
          "States": {
            "DailyRevenueGold": {
              "Type": "Task",
              "Resource": "arn:aws:states:::glue:startJobRun.sync",
              "Parameters": {
                "JobName": "${daily_revenue_gold_job}",
                "Arguments": { "--EXECUTION_DATE.$": "$$.Execution.Input.execution_date" }
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 30,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "ProductPerformanceGold",
          "States": {
            "ProductPerformanceGold": {
              "Type": "Task",
              "Resource": "arn:aws:states:::glue:startJobRun.sync",
              "Parameters": {
                "JobName": "${product_performance_gold_job}",
                "Arguments": { "--EXECUTION_DATE.$": "$$.Execution.Input.execution_date" }
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 30,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "CustomerOrdersGold",
          "States": {
            "CustomerOrdersGold": {
              "Type": "Task",
              "Resource": "arn:aws:states:::glue:startJobRun.sync",
              "Parameters": {
                "JobName": "${customer_orders_gold_job}",
                "Arguments": { "--EXECUTION_DATE.$": "$$.Execution.Input.execution_date" }
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 30,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ],
              "End": true
            }
          }
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "NotifyFailure",
          "ResultPath": "$.error"
        }
      ],
      "ResultPath": null,
      "Next": "NotifySuccess"
    },

    "NotifySuccess": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "${sns_topic_arn}",
        "Message": {
          "pipeline": "ecommerce-lakehouse",
          "status": "SUCCESS",
          "execution_date.$": "$$.Execution.Input.execution_date",
          "execution_id.$": "$$.Execution.Id"
        },
        "Subject": "Lakehouse pipeline completed successfully"
      },
      "ResultPath": null,
      "End": true
    },

    "NotifyFailure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "${sns_topic_arn}",
        "Message": {
          "pipeline": "ecommerce-lakehouse",
          "status": "FAILED",
          "execution_date.$": "$$.Execution.Input.execution_date",
          "execution_id.$": "$$.Execution.Id",
          "error.$": "$.error"
        },
        "Subject": "Lakehouse pipeline FAILED - action required"
      },
      "ResultPath": null,
      "Next": "PipelineFailed"
    },

    "PipelineFailed": {
      "Type": "Fail",
      "Error": "PipelineError",
      "Cause": "One or more pipeline stages failed. Check CloudWatch Logs for details."
    }
  }
}
