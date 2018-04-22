console.log('Loading function');
 
exports.handler = function(event, context, callback) {
    console.log('Received event:', JSON.stringify(event));
    console.log('Hello ', event.name);    
    console.log('start time =', context.getRemainingTimeInMillis());
    console.log('functionName =', context.functionName);
    console.log('functionVersion =', context.functionVersion);
    console.log('AWSrequestID =', context.awsRequestId);
    console.log('memoryLimitinMB =', context.awsRequestId);
    console.log('logGroupName =', context.logGroupName);
    console.log('logStreamName =', context.logStreamName);
    console.log('clientContext =', context.clientContext);
    console.log('clientContext =', context.clientContext);  
    callback(null, "Hello " + event.name);
    console.log('end time =', context.getRemainingTimeInMillis());
};
