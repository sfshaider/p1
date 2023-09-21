var Security = new function() {
    var self = this;

    this.getAutoResetPasswordEmail = function(merchant, callback, spinnerSelector) {
        Tools.createSpinner('email',spinnerSelector)
        Tools.startSpinner('email');
        Tools.json({
            url: '/admin/api/reseller/merchant/:' + merchant + '/auto_reset_password',
            action: 'read',
            onSuccess: function(responseData) {
                Tools.stopSpinner('email');
                callback(responseData.content.email);
            },
            onError: function() {
                console.error('failed to load email address');
                Tools.stopSpinner('email');
            }
        });
    }

    this.autoResetPassword = function(merchant, callback, spinnerSelector) {
        Tools.createSpinner('password',spinnerSelector)
        Tools.startSpinner('password');
        Tools.json({
            url: '/admin/api/reseller/merchant/:' + merchant + '/auto_reset_password',
            action: 'update',
            onSuccess: function(responseData) {
                Tools.stopSpinner('password');
                callback(responseData.content.message);
            },
            onError: function() {
                Tools.stopSpinner('password');
                console.error('failed to reset password');
                callback('Failed to reset password');
            }
        });
    }
}