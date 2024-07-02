import boto3
import os
import json

# Initialize SSM client
ssm = boto3.client('ssm')

# Get the parameter name from environment variable
PARAMETER_NAME = os.environ['PARAMETER_NAME']

def handler(event, context):
    try:
        # Get current parameter value
        response = ssm.get_parameter(Name=PARAMETER_NAME)
        current_value = int(response['Parameter']['Value'])

        # Increment value
        new_value = current_value + 1

        # Update parameter with new value
        ssm.put_parameter(
            Name=PARAMETER_NAME,
            Value=str(new_value),
            Type='String',
            Overwrite=True
        )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Parameter updated successfully',
                'oldValue': current_value,
                'newValue': new_value
            })
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error updating parameter',
                'error': str(e)
            })
        }
