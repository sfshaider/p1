import getTools from './Tools';

class BillMember {
    _error = false;

    _accountCodes = [];

    setError = (errorMsg) => { this._error = true; this.setErrorMessage(errorMsg); };
    getError = () => { return this._error; };

    setErrorMessage = (errorMsg) => { this._errorMessage = errorMsg; };
    getErrorMessage = () => { return this._errorMessage; };

    setBilled = (billed) => { this._billed = billed; };
    billed = () => { return this._billed; };

    setResponse = (response) => { this._responseMessage = response; };
    getResponse = () => { return this._responseMessage; };

    setAmount = (amount) => { this._amount = amount; };
    getAmount = () => { return this._amount; };

    setCVV = (cvv) => { this._cvv = cvv; };
    getCVV = () => { return this._cvv; };

    setDescription = (description) => { this._description = description; };
    getDescription = () => { return this._description; };

    setStatus = (status) => { this._status = status };
    getStatus = () => { return this._status };

    setAccountCode = (code, value) => { this._accountCodes[code] = value; };
    getAccountCode = (code) => { return this._accountCodes[code]; };

    setMerchantClassifierID = (id) => { this._merchantClassifierID = id; };
    getMerchantClassifierID = () => { return this._merchantClassifierID; };

    // transaction results
    getOrderID = () => { return this._orderID; };
    getDateTime = () => { return this._dateTime; };


    billCustomer = (callbacks) => {
        const tools = getTools();

        let billData = {
            'amount': this._amount,
            'description': this._description,
            'cvv': this._cvv,
            'acctCode1': this._accountCodes[0],
            'acctCode2': this._accountCodes[1],
            'acctCode3': this._accountCodes[2],
            'merchantClassifierID': this._merchantClassifierID
        };

        tools.json({
            action: 'create',
            url: '/recurring/attendant/api/merchant/customer/billmember/!/format/v1',
            data: billData,
            onSuccess: (data) => {
                let billed = data['content']['billed'];
                this._billed = (billed === 1);
                this._responseMessage = data['content']['message'];
                this._status = data['content']['status'];
                this._orderID = data['content']['transaction']['orderID'];
                this._dateTime = data['content']['transaction']['transactionDateTime']

                if (typeof(callbacks['onSuccess']) === 'function') {
                    callbacks['onSuccess'](this)
                }
            },
            onError: (xhr) => {
                if (xhr.status === 422) {
                    this.setError(xhr['responseJSON']['content']['data']['message']);
                } else {
                    this.setError('Failed to bill member.');
                }

                if (typeof(callbacks['onError']) === 'function') {
                    callbacks['onError'](this);
                }
            }
        });
    }
}

export default BillMember;
