import getTools from './Tools';
import TransactionResponse from './TransactionResponse';

class Transaction {
    _error = false;
    _transaction = undefined;
    _transactionResponse = {};
    _accountCodes = {};

    constructor(transaction=undefined) {
        this._transaction = transaction;
    };

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

    setOrderID = (orderID) => {
        this._orderID = orderID;
    };

    getOrderID = () => {
        return this._orderID;
    };

    setTransactionRefID = (refID) => {
        this._transactionRefID = refID;
    };

    getTransactionRefID = () => {
        return this._transactionRefID;
    };

    setBillingName = (name) => {
        this._billingName = name;
    };

    getBillingName = () => {
        return this._billingName;
    };

    setBillingAddress = (address) => {
        this._billingAddress = address;
    };

    getBillingAddress = () => {
        return this._billingAddress;
    };

    setBillingCity = (city) => {
        this._billingCity = city;
    };

    getBillingCity = () => {
        return this._billingCity;
    };

    setBillingState = (state) => {
        this._billingState = state;
    };

    getBillingState= () => {
        return this._billingState;
    };

    setBillingPostalCode = (zip) => {
        this._billingPostalCode = zip;
    };

    getBillingPostalCode = () => {
        return this._billingPostalCode;
    };

    setBillingCountry = (country) => {
        this._billingCountry = country;
    };

    getBillingCountry= () => {
        return this._billingCountry;
    };

    setBillingEmail = (email) => {
        this._billingEmail = email;
    };

    getBillingEmail = () => {
        return this._billingEmail;
    };

    setBillingPhone = (phone) => {
        this._billingPhone = phone;
    };

    getBillingPhone = () => {
        return this._billingPhone;
    };


    setShippingName = (name) => {
        this._shippingName = name;
    };

    getShippingName = () => {
        return this._shippingName;
    };

    setShippingAddress = (address) => {
        this._shippingAddress = address;
    };

    getShippingAddress = () => {
        return this._shippingAddress;
    };

    setShippingCity = (city) => {
        this._shippingCity = city;
    };

    getShippingCity = () => {
        return this._shippingCity;
    };

    setShippingState = (state) => {
        this._shippingState = state;
    };

    getShippingState= () => {
        return this._shippingState;
    };

    setShippingPostalCode = (zip) => {
        this._shippingPostalCode = zip;
    };

    getShippingPostalCode = () => {
        return this._shippingPostalCode;
    };

    setShippingCountry = (country) => {
        this._shippingCountry = country;
    };

    getShippingCountry= () => {
        return this._shippingCountry;
    };

    setShippingEmail = (email) => {
        this._shippingEmail = email;
    };

    getShippingEmail = () => {
        return this._shippingEmail;
    };

    setShippingPhone = (phone) => {
        this._shippingPhone = phone;
    };

    getShippingPhone = () => {
        return this._shippingPhone;
    };

    setAmount = (amount) => {
        this._amount = amount;
    };

    getAmount = () => {
        return this._amount;
    };

    setCurrency = (currency) => {
        this._currency = currency;
    };

    getCurrency = () => {
        return this._currency;
    };

    setMode = (mode) => {
        this._mode = mode;
    };

    getMode = () => {
        return this._mode;
    };

    setType = (type) => {
        this._type = type;
    };

    getType = () => {
        return this._type;
    };

    setPaymentType = (paymentType) => {
        this._paymentType = paymentType;
    };

    getPaymentType = () => {
        return this._paymentType;
    };

    setCardNumber = (cardNumber) => {
        this._cardNumber = cardNumber.replace(/[^\d]/g,"");
    };

    getCardNumber = () => {
        return this._cardNumber;
    };

    setExpirationMonth = (expMonth) => {
        this._expMonth = expMonth;
    };

    getExpirationMonth = () => {
        return this._expMonth;
    };

    setExpirationYear = (expYear) => {
        this._expYear = expYear;
    };

    getExpirationYear = () => {
        return this._expYear;
    };

    setCVV = (cvv) => {
        this._cvv = cvv;
    };

    getCVV = () => {
        return this._cvv;
    };

    setAccountNumber = (acctNumber) => {
        this._accountNumber = acctNumber;
    };

    getAccountNumber = () => {
        return this._accountNumber;
    };

    setAccountType = (acctType) => {
        this._accountType = acctType;
    };

    getAccountType = () => {
        return this._accountType;
    };

    setToken = (token) => {
        this._token = token;
    };

    getToken = () => {
        return this._token;
    };

    setAccountCode = (code, value) => {
        this._accountCodes[code] = value;
    };

    getAccountCode = (code) => {
        return this._accountCodes[code];
    };

    getAccountCodes = () => {
        return this._accountCodes;
    };

    setRoutingNumber = (routingNumber) => {
        this._routingNumber = routingNumber;
    };

    getRoutingNumber = () => {
        return this._routingNumber;
    }

    setMerchantClassifierID = (id) => {
        this._merchantClassifierID = id;
    }

    getMerchantClassifierID = () => {
        return this._merchantClassifierID;
    }

    /*
        Note: Added these methods in case that the transactions change
        from being synchronous in the future.
     */
    setProcessMode = mode => this._mode = mode;

    getProcessMode = () => this._mode;

    /*******************
        Response Data
     *******************/

    setAuthorizationCode = (transaction, code) => {
        if (this._transactionResponse[transaction]) {
            this._transactionResponse[transaction]['authorizationCode'] = code;
        }
    };

    getAuthorizationCode = (transaction) => {
        if (this._transactionResponse[transaction]) {
            return this._transactionResponse[transaction]['authorizationCode'];
        }
    };

    setStatus = (transaction, status) => {
        if (this._transactionResponse[transaction]) {
            this._transactionResponse[transaction]['status'] = status;
        }
    };

    getStatus = (transaction) => {
        if (this._transactionResponse[transaction]) {
            return this._transactionResponse[transaction]['status'];
        }
    };

    setAVSResponse = (transaction, avs) => {
        if (this._transactionResponse[transaction]) {
            this._transactionResponse[transaction]['avsResponse'] = avs;
        }
    };

    getAVSResponse = (transaction) => {
        if (this._transactionResponse[transaction]) {
            return this._transactionResponse[transaction]['avsResponse'];
        }
    };

    setCVVResponse = (transaction, cvv) => {
        if (this._transactionResponse[transaction]) {
            this._transactionResponse[transaction]['cvvResponse'] = cvv;
        }
    };

    getCVVResponse = (transaction) => {
        if (this._transactionResponse[transaction]) {
            return this._transactionResponse[transaction]['cvvResponse'];
        }
    };

    setMerchantTransactionID = (transaction, merchTransID) => {
        if (this._transactionResponse[transaction]) {
            this._transactionResponse[transaction]['merchantTransactionID'] = merchTransID;
        }
    };

    getMerchantTransactionID = (transaction) => {
        if (this._transactionResponse[transaction]) {
            return this._transactionResponse[transaction]['merchantTransactionID'];
        }
    };

    setMessage = (transaction, message) => {
        if (this._transactionResponse[transaction]) {
            this._transactionResponse[transaction]['message'] = message;
        }
    };

    getMessage = (transaction) => {
        if (this._transactionResponse[transaction]) {
            return this._transactionResponse[transaction]['message'];
        }
    };

    setErrors = (transaction, errors) => {
        if (this._transactionResponse[transaction]) {
            this._transactionResponse[transaction]['errors'] = errors;
        }
    };

    getErrors = (transaction) => {
        if (this._transactionResponse[transaction]) {
            return this._transactionResponse[transaction]['errors'];
        }
    };

}

const createTransaction = (transaction,callbacks) => {
    let transactionArray = transaction;

    if (typeof(transaction !== "object" || !Array.isArray(transaction))) {
        transactionArray = [transaction];
    }

    const data = {};

    if (typeof(callbacks) !== "object") {
        console.error("callbacks parameter is not an object.");
        return;
    }

    if (typeof(callbacks.onSuccess) !== "function") {
        console.error("callbacks.onSuccess parameter is not a function.");
        return;
    }

    if (typeof(callbacks.onError) !== "function") {
        console.error("callbacks.onError parameter is not a function.");
        return;
    }

    if (transactionArray.length < 1) {
        console.error("At least one transaction is required.")
        callbacks.onError();
        return;
    }

    for (let i = 0; i < transactionArray.length; i++) {
        let trans = transactionArray[i];
        let transactionData = {};
        if (typeof(trans) !== 'undefined') {
            const accountCodes = {
                1: trans.getAccountCode(0),
                2: trans.getAccountCode(1),
                3: trans.getAccountCode(2)
            };
            const billingInfo = {};
            billingInfo['name']       = trans.getBillingName();
            billingInfo['address']    = trans.getBillingAddress();
            billingInfo['city']       = trans.getBillingCity();
            billingInfo['state']      = trans.getBillingState();
            billingInfo['postalCode'] = trans.getBillingPostalCode();
            billingInfo['country']    = trans.getBillingCountry();
            billingInfo['email']      = trans.getBillingEmail();
            billingInfo['phone']      = trans.getBillingPhone();

            const shippingInfo = {};
            shippingInfo['name']       = trans.getShippingName();
            shippingInfo['address']    = trans.getShippingAddress();
            shippingInfo['city']       = trans.getShippingCity();
            shippingInfo['state']      = trans.getShippingState();
            shippingInfo['postalCode'] = trans.getShippingPostalCode();
            shippingInfo['country']    = trans.getShippingCountry();
            shippingInfo['email']      = trans.getShippingEmail();
            shippingInfo['phone']      = trans.getShippingPhone();

            const paymentInfo = {};
            if (trans.getPaymentType() === 'card') {
                const card = {};
                card['number']   = trans.getCardNumber();
                card['expMonth'] = trans.getExpirationMonth();
                card['expYear']  = trans.getExpirationYear();
                card['cvv']      = trans.getCVV();
                card['token']    = trans.getToken();
                paymentInfo['card'] = card;
            } else if (trans.getPaymentType() === 'ach') {
                const ach = {};
                ach['accountNumber'] = trans.getAccountNumber();
                ach['routingNumber'] = trans.getRoutingNumber();
                ach['token']         = trans.getToken();
                ach['accountType']   = trans.getAccountType();
                paymentInfo['ach']   = ach;
            }

            paymentInfo['type'] = trans.getType();
            paymentInfo['mode'] = trans.getMode();

            transactionData['orderID'] = trans.getOrderID();
            transactionData['transactionRefID'] = trans.getTransactionRefID();
            transactionData['billingInfo'] = billingInfo;
            transactionData['shippingInfo'] = shippingInfo;
            transactionData['payment'] = paymentInfo;
            transactionData['amount'] = trans.getAmount();
            transactionData['currency'] = trans.getCurrency();
            transactionData['accountCode'] = accountCodes;
            transactionData['merchantClassifierID'] = trans.getMerchantClassifierID();
            transactionData['processMode'] = 'sync'; // if this needs to change, call setProcessMode(mode) and then getProcessMode() here
        }

        data[i] = transactionData;
    }

    const tools = getTools();
    tools.json({
        'action': 'create',
        'data': {transactions: data},
        'url': '/recurring/attendant/api/merchant/order/transaction/!/format/:v1',
        'onSuccess': (data) => {
            const transactionResults = data['content']['transactions'];
            const transactionKeys = Object.keys(transactionResults);
            const results = transactionKeys.map((trans) => {
                if (typeof(transactionArray[trans]) !== 'undefined') {
                    return new TransactionResponse(transactionArray[trans], {
                        authorizationCode: transactionResults[trans]['authorizationCode'],
                        cvvResponse: transactionResults[trans]['cvvResponse'],
                        avsResponse: transactionResults[trans]['avsResponse'],
                        message: transactionResults[trans]['message'],
                        status: transactionResults[trans]['status'] || 'problem',
                        errors: transactionResults[trans]['errors'],
                        orderID: transactionResults[trans]['merchantOrderID'],
                        transactionDateTime: transactionResults[trans]['transactionDateTime']
                    });
                }
            });

            if (typeof(callbacks) === 'object' && typeof(callbacks.onSuccess) === 'function') {
                callbacks.onSuccess(results);
            }
        },
        'onError': (xhr) => {
            this.setError('Failed to process transaction.');
            if (typeof(callbacks) === 'object' && typeof(callbacks.onError) === 'function') {
                callbacks.onError(xhr);
            }
        }
    });
};

export default Transaction;
export {createTransaction};
