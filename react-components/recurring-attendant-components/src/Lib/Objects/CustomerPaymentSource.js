import getTools from './Tools'

class CustomerPaymentSource {
    constructor(load=false) {
        if (load) {
            this.loadPaymentSource();
        }
    }

    _loaded = false;
    _error = false;
    _hasPaymentSource = false;
    _loadedCallbacks = [];


    setError = (errorMsg) => {
        this._error = true;
        this.setErrorMessage(errorMsg);
    };

    getError = () => {
        return this._error;
    };

    setErrorMessage = (errorMsg) => {
        this._errorMessage = errorMsg;
    };

    getErrorMessage = () => {
        return this._errorMessage;
    };

    setHasPaymentSource = (has) => {
        this._hasPaymentSource = has;
    };

    hasPaymentSource = () => {
        return this._hasPaymentSource;
    };

    setPaymentType = (type) => {
        this._type = type;
    };

    getPaymentType = () => {
        if (this.isCardPayment()) {
            return 'card';
        } else if (this.isACHPayment()) {
            return 'ach';
        }

        return null;
    };

    isCardPayment = () => {
        return /^(card|credit)$/i.test(this._type);
    };

    isACHPayment = () => {
        return /^(ach|checking|savings)$/i.test(this._type);
    };

    setCardNumber = (cardNumber) => {
        this._cardNumber = cardNumber;
    };

    getCardNumber = () => {
        return this._cardNumber;
    };

    setToken = (token) => {
        this._token = token;
    };

    getToken = () => {
        return this._token;
    };

    setRoutingNumber = (routingNumber) => {
        this._routingNumber = routingNumber;
    };

    getRoutingNumber = () => {
        return this._routingNumber;
    };

    setAccountNumber = (accountNumber) => {
        this._accountNumber = accountNumber;
    };

    getAccountNumber = () => {
        return this._accountNumber;
    };

    setAccountType = (accountType) => {
        this._accountType = accountType;
    };

    getAccountType = () => {
        return this._accountType;
    };

    setExpirationMonth = (month) => {
        this._expirationMonth = month;
    };

    getExpirationMonth = () => {
        return parseInt(this._expirationMonth);
    };

    setExpirationYear = (year) => {
        this._expirationYear = year;
    };

    getExpirationYear = () => {
        return this._expirationYear;
    };

    getExpMonthFromHash = (data) => {
        if (data.expMonth === null || data.expMonth == 0 || data.expMonth === "00") {
            return new Date().getMonth() + 1;
        } else {
            return parseInt(data.expMonth);
        }
    };

    getExpYearFromHash = (data) => {
        if (data.expYear === null || data.expYear == 0 || data.expYear === "00" || data.expYear === "0000") {
            return new Date().getFullYear().toString().substr(2, 4);
        } else {
            return data.expYear;
        }
    };

    load = (callback = null) => {
        const tools = getTools();
        tools.json({
            action: 'read',
            url: '/recurring/attendant/api/merchant/customer/paymentsource',
            onSuccess: (data) => {
                this._loaded = true;

                const paymentSourceData = data['content']['paymentsource'][0];
                    if (paymentSourceData) {
                        this.setHasPaymentSource(true);
                    }

                this._type = paymentSourceData['type'];
                if (this.isCardPayment()) {
                    this._cardNumber = paymentSourceData['maskedNumber'];
                    // this is to fix an issue where card numbers were being saved without an expiration date/year
                    // this will still require the user to update their cardnumber with a new month/year

                    this._expirationMonth = this.getExpMonthFromHash(paymentSourceData);
                    this._expirationYear = this.getExpYearFromHash(paymentSourceData);
                } else if (this.isACHPayment()) {
                    const achInfo = getTools().divideRoutingAndAccountNumber(paymentSourceData['maskedNumber']);
                    this._accountNumber = achInfo['accountNumber'];
                    this._routingNumber = achInfo['routingNumber'];
                    this._accountType = paymentSourceData['type']; // type is checking/savings
                }

                this._token = paymentSourceData['token'];
                if (typeof(callback) === "function") {
                    this._loadedCallbacks.push(callback);
                }

                for (let i in this._loadedCallbacks) {
                    if (typeof(this._loadedCallbacks[i]) !== "undefined") {
                        this._loadedCallbacks[i](this);
                        this._loadedCallbacks[i] = undefined;
                    }
                }
            },
            onError: (xhr) => {
                this._loaded = true;

                if (xhr.status === 404) {
                    this.setError(xhr['responseJSON']['content']['data']['message']);
                } else {
                    this.setError('Failed to load payment source.');
                }

                if (typeof(callback) === "function") {
                    this._loadedCallbacks.push(callback);
                }

                for (let i in this._loadedCallbacks) {
                    if (typeof(this._loadedCallbacks[i]) !== "undefined") {
                        this._loadedCallbacks[i](this);
                        this._loadedCallbacks[i] = undefined;
                    }
                }
            }
        });
    };

    save = (callbacks) => {
        let action = 'create';

        if (this._loaded) {
            action = 'update';
        }

        let data = {
            'type': this._type
        };

        if (this.getPaymentType() === 'card') {
            data['expMonth'] = this._expirationMonth;
            data['expYear'] = this._expirationYear;
            data['cardNumber'] = this._cardNumber;
        } else {
            data['accountNumber'] = this._accountNumber;
            data['routingNumber'] = this._routingNumber;
            data['accountType'] = this._accountType;
        }

        data['token'] = this._token;

        const setHasPaymentSource = () => {
            this.setHasPaymentSource(true);
        };

        const tools = getTools();
        tools.json({
            action: action,
            data: data,
            url: '/recurring/attendant/api/merchant/customer/paymentsource',
            onSuccess: [setHasPaymentSource,callbacks.onSuccess],
            onError: callbacks.onError
        });
    };

    deletePaymentSource = (onSuccess, onError) => {
        const tools = getTools();
        tools.json({
            action: 'delete',
            data: {},
            url: '/recurring/attendant/api/merchant/customer/paymentsource',
            onSuccess: onSuccess,
            onError: onError
        });
    };

    didLoad = (callback) => {
        if (typeof(callback) === "function") {
            if (this._loaded) {
                callback(this);
            } else {
                this._loadedCallbacks.push(callback);
            }
        }
    }
}

export default CustomerPaymentSource;
