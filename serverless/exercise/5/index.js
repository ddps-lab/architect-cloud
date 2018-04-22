function isPalindrome(str) {
  return str === str.split('').reverse().join('');
}

exports.handler = function(event, context) {
    var input = process.env.INPUT;
    
    if(isPalindrome(input)) {
        context.done(null, input + ' is palindrome')
    }
    else {
        context.done(null, input + ' is not palindrome')
    }
};
