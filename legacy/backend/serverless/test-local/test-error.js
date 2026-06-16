var path = require("path");

const lambdaLocal = require('lambda-local');
 
var jsonPayload = {
}
 
lambdaLocal.execute({
    event: jsonPayload,
    lambdaPath: path.join(__dirname, 'Simple-Hello.js'),
    profilePath: '~/.aws/credentials',
    profileName: 'default',
    timeoutMs: 3000,
    callback: function(err, data) {
        if (err) {
            console.log(err);
        } else {
            console.log(data);
        }
    }
});

