// index.js

exports.handler = async (event) => {
  console.log('Event: ', JSON.stringify(event, null, 2))

  const response = {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      message: 'Hello from Lambda!',
      timestamp: new Date().toISOString(),
      event
    })
  }

  return response
}
