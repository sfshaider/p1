class _Tools {
    constructor() {
        this.startStatusCheck();
    }

    _requestIDs = {};
    _tokenMetaTag = undefined;
    _realm = undefined;

    json = (options) => {
        // set noQueue to false if it is not defined
        if (typeof options["noQueue"] === 'undefined') {
            options["noQueue"] = false;
        }

        // convert actions to methods
        if (typeof options["action"] !== 'undefined') {
            let actions = {"create":"post",
                "read":"get",
                "update":"put",
                "delete":"delete"};

            options["method"] = actions[options["action"].toLowerCase()];
        }

        // if an unsupported method is found, remove it
        let methods = {"post":1,"get":1,"put":1,"delete":1};
        if (methods[options["method"].toLowerCase()] !== 1) {
            console.error("Invalid method.");
            return;
        }

        // encode options into the url
        let requestOptionsString = '/!';
        if (typeof options["options"] === "object") {
            for (const requestOption in options["options"]) {
                if (options["options"].hasOwnProperty(requestOption)) {
                    requestOptionsString += '/' + requestOption + '/:' + options["options"][requestOption];
                }
            }
            if (requestOptionsString !== '/!') {
                options["url"] += requestOptionsString;
            }
        }

        let requestToken = this.getCurrentToken();

        let key = options['key'];
        this._requestIDs[key] = undefined;
        if (key) {
            // needs toString as the later comparison with the response will fail when using ===
            this._requestIDs[key] = Date.now().toString();
        }

        let ajaxOptions = {
            "url" : options["url"],
            "type": options["method"],
            "dataType":"json",
            "headers": {
                'X-Gateway-Request-Token': requestToken,
                'Request-ID': this._requestIDs[key],
                'Cache-Control': 'no-cache, no-store, must-revalidate',
                'Pragma': 'no-cache',
                'Expires': 0,
                'Accept': 'application/json'
            },
            "data": JSON.stringify(options["data"]),
            "success": (responseData) => {
                const doIt = () => {
                    if (!key || this._requestIDs[key] === responseData['id']) {
                        let rawData = { 'content': responseData['content']['data'] };
                        let successFunctions = [];

                        if (typeof(options.onSuccess) === "function") {
                            successFunctions = [options.onSuccess];
                        } else if (typeof(options.onSuccess) === "object" && Array.isArray(options.onSuccess)) {
                            successFunctions = options.onSuccess;
                        } else {
                            window.console.warn("options.onSuccess is neither a function nor an array.", options.onSuccess);
                        }

                        for (let callbackIndex in successFunctions) {
                            if (typeof(successFunctions[callbackIndex]) !== "function") {
                                window.console.warn("A value passed to onSuccess is not a function:", successFunctions[callbackIndex]);
                            } else {
                                successFunctions[callbackIndex](rawData);
                            }
                        }
                    }
                };

                doIt();
            },
            "error": (errMsg) => {
                if (typeof(options["onError"]) === 'function') {
                    options["onError"](errMsg);
                } else {
                    console.log(errMsg);
                }
            }
        };

        if (options["method"].toLowerCase() !== "get") {
            ajaxOptions['headers']['content-type'] = "application/json";
        }

        this.ajax(ajaxOptions);
    };

    // noinspection JSUnusedGlobalSymbols
    stringHashCode = (string) => {
        let hash = 0;
        if (string.length === 0) return hash;
        for (let i = 0; i < string.length; i++) {
            const char = string.charCodeAt(i);
            hash = ((hash<<5)-hash)+char;
            hash = hash & hash; // Convert to 32bit integer
        }
        return hash;
    };

    // noinspection JSUnusedGlobalSymbols
    convertToLocalTime = (dateFromServer) => {
        if (dateFromServer != null) {
            dateFromServer = dateFromServer.replace(/-/g, '/');

            // get date using time zone of user
            let date = new Date(dateFromServer + ' UTC');
            return this.formatDateTime(date, true);
        }
    };

    formatDateTime = (dateTime, converted) => {
        if (dateTime != null) {
            let date = undefined;
            if (converted) {
                date = dateTime;
            } else {
                date = new Date(dateTime);
            }
            const day = ("0" + date.getDate()).slice(-2);
            const month = ("0" + (date.getMonth() + 1)).slice(-2);
            const year = (date.getFullYear().toString()).slice(-2);

            // convert to am pm
            let hours = date.getHours() > 12 ? date.getHours() - 12 : date.getHours();
            hours = hours < 10 ? "0" + hours : hours;
            const am_pm = date.getHours() >= 12 ? "PM" : "AM";
            const minutes = date.getMinutes() < 10 ? "0" + date.getMinutes() : date.getMinutes();
            const seconds = date.getSeconds() < 10 ? "0" + date.getSeconds() : date.getSeconds();
            const time = hours + ":" + minutes + ":" + seconds + " " + am_pm;

            return month + "/" + day + "/" + year + " " + time;
        }
    };

    ajax = (options) => {
        let request = new XMLHttpRequest();

        request.open(options['type'], options['url']);

        let headers = options['headers'];

        if (typeof(headers) === 'undefined') {
            headers = {};
        }

        for (let headerName in headers) {
            if (headers.hasOwnProperty(headerName)) {
                request.setRequestHeader(headerName, headers[headerName]);
            }
        }

        if (options['type'].toLowerCase() === 'post' || options['type'].toLowerCase() === 'put') {
            request.send(options['data']);
        } else {
            request.send();
        }

        let data = {};

        request.onload = () => {
            data = JSON.parse(request.responseText);
            const success = options['success'];
            const error = options['error'];

            let successFunctions = success;
            if (typeof(success) === 'function') {
                successFunctions = [success];
            } else if (typeof(success) === "object" && Array.isArray(success)) {
                successFunctions = success;
            } else {
                window.console.warn('options.success is neither a function nor an array.', options.success)
            }

            successFunctions.every((successFunction) => {
                if (request.status >= 200 && request.status < 400) {
                    return successFunction(data);
                } else if (typeof(error) === 'function') {
                    return error(data);
                }

                window.console.warn("A value passed to options.success is not a function.");

                return false;
            })
        };

        request.onerror = () => {
            const error = options['error'];
            if (typeof(error) === 'function') {
                error(request.getErrorMessage());
            } else {
                window.console.warn("options['error'] is not defined or is not a function.");
            }
        }
    };

    getRealm = () => {
        if (typeof(this._realm) === 'undefined') {
            let metatags = document.getElementsByTagName('meta');
            for (let i = 0; i < metatags.length; i++) {
                if (metatags[i].getAttribute('name') === 'realm') {
                    this._realm = metatags[i].getAttribute('content');
                    return metatags[i].getAttribute('content');
                }
            }
        } else {
            return this._realm;
        }
    };

    setCurrentToken = (token) => {
        if (typeof(this._tokenMetaTag) === 'undefined') {
            let metatags = document.getElementsByTagName('meta');
            for (let i = 0; i < metatags.length; i++) {
                if (metatags[i].getAttribute('name') === 'request-token') {
                    metatags[i].setAttribute('content',token);
                }
            }
        } else {
            this._tokenMetaTag.setAttribute('content', token);
        }

    };

    getCurrentToken = () => {
        if (typeof(this._tokenMetaTag) === 'undefined') {
            let metatags = document.getElementsByTagName('meta');
            for (let i = 0; i < metatags.length; i++) {
                if (metatags[i].getAttribute('name') === 'request-token') {
                    this._tokenMetaTag = metatags[i];
                    return metatags[i].getAttribute('content');
                }
            }
        } else {
            return this._tokenMetaTag.getAttribute('content');
        }
    };


    // noinspection JSUnusedGlobalSymbols
    startStatusCheck = () => {
        window.setInterval(() => {
            let currentToken = this.getCurrentToken();
            let realm = this.getRealm();
            this.json({
                    url: '/api/login/',
                    action: 'create',
                    data: {
                        'currentToken': currentToken,
                        'cookieName': realm
                    },
                    onSuccess: (data) => {
                        this.setCurrentToken(data['content']['newToken'])
                    }
            })},
            60 * 1000)
    };

    luhn10 = (number) => {
        var nCheck = 0, nDigit = 0, bEven = false;
        number = number.replace(/\D/g, "");

        for (var n = number.length - 1; n >= 0; n--) {
            var cDigit = number.charAt(n),
                nDigit = parseInt(cDigit, 10);

            if (bEven) {
                if ((nDigit *= 2) > 9) nDigit -= 9;
            }

            nCheck += nDigit;
            bEven = !bEven;
        }

        return (nCheck % 10) === 0;
    };

    validateCreditCard = (number) => {
        number = number.toString();
        if (number.includes('*')) {
            return false; // potential masked number
        }

        number = number.replace(/[^\d]/g,'');  // remove anything that's not a digit
        if (number.length >= 12 && number.length <= 19) {
            if (number.match(/^3[47]/) !== null && number.length !== 15) { // we can skip a luhn10 check if these conditions are true
                return false;
            }

            if (this.luhn10(number)) {
                return true;
            }
        }
        return false;
    };

    validateRoutingNumber = (number) => {
        if (number && number.length === 9) {
            let digits = number.split('');
            let validationSequence = [ 3, 7, 1 ];
            let sum = 0;
            for (let i = 0; i < 9; i++) {
                sum += digits[i] * validationSequence[i % 3];
            }

            return (sum % 10) === 0;
        }

        return false;
    };

    validateEmail = (emailAddress) => {
        let valid = /^[a-zA-Z0-9\-+_&=*]+(\.[a-zA-Z0-9\-+_&=*]+)*@[a-z0-9]+(-[a-z0-9]+)*(\.[a-z0-9]+(-[a-z0-9]+)*)*\.[a-z]{2,63}$/.test(emailAddress);
        if (valid) {
            valid = !(/\.\./.test(emailAddress));
        }

        return valid;
    };

    validatePhone = (phoneNumber) => {
        if (!phoneNumber) {
            phoneNumber = "";
        }

        phoneNumber = phoneNumber.toString().replace(/[^\d]*/g, '');
        return /^\d{3}\d{3}\d{4}$/.test(phoneNumber);
    };

    validateExpirationDate = (month,year) => {
        if (month !== '' && !isNaN(month) && year !== '' && !isNaN(year)) {
            month = parseInt(month,10);
            year = parseInt(year,10);
            var today = new Date();
            var todaysMonth = today.getMonth() + 1;
            var todaysYear = today.getFullYear();
            if (month >= 1 && month <= 12 &&
                ((year + 2000) > todaysYear || ((year + 2000) === todaysYear && month >= todaysMonth))) {
                return true;
            }
        }
        return false;
    };

    nullOrValue = (value) => {
        if (value) {
            return value;
        }

        return null;
    };

    isZeroOrEmpty(amount) {
        return (
            typeof(amount) === "undefined" ||
            (typeof(amount) === "number" && isNaN(amount)) ||
            amount === "" ||
            amount === 0 ||
            amount === 0.00 ||
            amount === "--"
        );
    }

    formatCurrency = (amount) => {
        if (this.isZeroOrEmpty(amount)) {
            return "--";
        }

        amount = amount.toString().replace(/,/g, '');       // first remove commas
        amount = parseFloat(amount).toFixed(2).toString();  // parse to float
        const decimalValue = amount.substr(amount.indexOf('.') + 1, amount.length);
        let numbers = amount.substr(0, amount.indexOf('.')).split('').reverse();

        let formattedNumber = '';

        let counter = 0;
        numbers.map((number) => {
            if (counter === 3) {
                formattedNumber = number + ',' + formattedNumber;
                counter = 0;
            } else {
                formattedNumber = number + formattedNumber;
            }

            counter++;
        });

        return formattedNumber + '.' + decimalValue;
    };

    formatPhoneNumber = (phoneNumber) => {
        if (!phoneNumber) {
            phoneNumber = "";
        }

        let formattedNumber = phoneNumber.toString().replace(/\D/g, '');
        let partOne = formattedNumber.substring(0,3);
        let partTwo = formattedNumber.substring(3,6);
        let partThree = formattedNumber.substring(6, 10);

        formattedNumber = partOne;
        if (partTwo.length >= 1) {
            formattedNumber = "(" + partOne + ") " + partTwo;
        }

        if (partThree.length >= 1) {
            formattedNumber += " - " + partThree;
        }

        return formattedNumber;
    };

    formatCreditCard = (value) => {
        value = value.replace(/\s/g, '');
        value = value.substr(0,19);
        if (value.length === 15 && value.startsWith('3')) {
            value = `${value.substring(0, 4)} ${value.substring(4, 7)} ${value.substring(7, 10)} ${value.substring(10,15)}`;
        } else {
            value = value.replace(/.{4}(?=.)/g, '$& ');
        }
        return value;
    };

    unformatCreditCard = (number) => {
        return number.replace(/[^0-9\*]/g,'')
    }

    divideRoutingAndAccountNumber = (number) => {
        let achInfo = {};
        if (!number) {
            return achInfo;
        }

        let masked = number.replace(/\*+/, '*');
        const numbers = masked.split('*');
        achInfo['routingNumber'] = '**' + numbers[0];
        achInfo['accountNumber'] = '**' + numbers[1];
        return achInfo;
    };
}

const _tools = new _Tools();

const getTools = () => {
    return _tools;
};

export default getTools;
