import getTools from './Tools'

class Adjustment {
    constructor(transactionData = []) {
        this.coaEnabled = false;
        this.transactionInformation = transactionData;
    }

    _isCoaEnabled = (callbacks) => {
        this.tools.json({
            'url': '/recurring/attendant/api/merchant/adjustment',
            'action': 'read',
            'onSuccess': function(data) {
                let coaEnabled = data['content']['enabled'];
                if (coaEnabled === 'true') {
                    if (typeof(callbacks['enabled']) === 'function') {
                        callbacks['enabled'](this);
                    }
                } else {
                    if (typeof(callbacks['disabled']) === 'function') {
                        callbacks['disabled'](this);
                    }
                }
            },
            'onError': function(error) {
                console.log(error);
            }
        });
    };

    loadAdjustment = (callbacks) => {
        getTools().json({
            action: 'create',
            url: '/recurring/attendant/api/merchant/adjustment',
            key: 'adjustment',
            data: {
                "transactionInformation": this.transactionInformation['transactionInformation'],
                "transactionAmount": this.transactionInformation['transactionAmount'],
                "transactionIdentifier": this.transactionInformation['transactionIdentifier'],

            },
            onSuccess: callbacks['onSuccess'],
            onError: callbacks['onError']
        })
    }
}
export default Adjustment;
