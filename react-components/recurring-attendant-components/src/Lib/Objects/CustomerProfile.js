import getTools from './Tools'

class CustomerProfile {
    constructor(load=false,options) {
        if (load) {
            this.load((profile) => {
                if (typeof(options["success"]) === "function") {
                    options["success"](profile);
                }
            });
        }
    }

    _loaded = false;
    _error = false;
    _hasProfile = false;
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

    setHasProfile = (hasProfile) => {
        this._hasProfile = hasProfile;
    };

    hasProfile = () => {
        return this._hasProfile;
    };

    setUsername = (username) => {
        this._username = username;
    };

    getUsername = () => {
        return this._username || "";
    };

    setName = (name) => {
        this._name = name;
    };

    getName = () => {
        return this._name || "";
    };

    setEmail = (email) => {
        this._email = email;
    };

    getEmail = () => {
        return this._email || "";
    };

    setCompany = (company) => {
        this._company = company;
    };

    getCompany = () => {
        return this._company || "";
    };

    setAddr1 = (addr1) => {
        this._addr1 = addr1;
    };

    getAddr1 = () => {
        return this._addr1 || "";
    };

    setAddr2 = (addr2) => {
        this._addr2 = addr2;
    };

    getAddr2 = () => {
        return this._addr2 || "";
    };

    setCity = (city) => {
        this._city = city;
    };

    getCity = () => {
        return this._city || "";
    };

    setState = (state) => {
        this._state = state;
    };

    getState = () => {
        return this._state || "";
    };

    setPostalCode = (postalCode) => {
        this._postalCode = postalCode;
    };

    getPostalCode = () => {
        return this._postalCode || "";
    };

    setCountry = (country) => {
        this._country = country;
    };

    getCountry = () => {
        return this._country || "";
    };

    setShippingName = (shippingName) => {
        this._shippingName = shippingName;
    };

    getShippingName = () => {
        return this._shippingName || "";
    };

    setShippingAddr1 = (shippingAddr1) => {
        this._shippingAddr1 = shippingAddr1;
    };

    getShippingAddr1 = () => {
        return this._shippingAddr1 || "";
    };

    setShippingAddr2 = (shippingAddr2) => {
        this._shippingAddr2 = shippingAddr2;
    };

    getShippingAddr2 = () => {
        return this._shippingAddr2 || "";
    };

    setShippingCity = (shippingCity) => {
        this._shippingCity = shippingCity;
    };

    getShippingCity = () => {
        return this._shippingCity || "";
    };

    setShippingState = (shippingState) => {
        this._shippingState = shippingState;
    };

    getShippingState = () => {
        return this._shippingState || "";
    };

    setShippingPostalCode = (shippingPostalCode) => {
        this._shippingPostalCode = shippingPostalCode;
    };

    getShippingPostalCode = () => {
        return this._shippingPostalCode || "";
    };

    setShippingCountry = (shippingCountry) => {
        this._shippingCountry = shippingCountry;
    };

    getShippingCountry = () => {
        return this._shippingCountry || "";
    };

    setPhone = (phone) => {
        this._phone = phone;
    };

    getPhone = () => {
        return this._phone || "";
    };

    setFax = (fax) => {
        this._fax = fax;
    };

    getFax = () => {
        return this._fax || "";
    };

    setStatus = (status) => {
        this._status = status;
    };

    getStatus = () => {
        return this._status || "";
    };

    setRecurringFee = (recurringFee) => {
        this._recurringFee = recurringFee;
    };

    getRecurringFee = () => {
        return this._recurringFee || "";
    };

    setStartDate = (startDate) => {
        this._startDate = startDate;
    };

    getStartDate = () => {
        return this._startDate || "";
    };

    setEndDate = (endDate) => {
        this._endDate = endDate;
    };

    getEndDate = () => {
        return this._endDate || "";
    };

    setBalance = (balance) => {
        this._balance = balance;
    };

    getBalance = () => {
        return this._balance || "";
    };

    setBillCycle = (billCycle) => {
        this._billCycle = billCycle;
    };

    getBillCycle = () => {
        return this._billCycle || "";
    };

    setAccountCode = (code) => { this._acctCode = code; };
    getAccountCode = () => { return this._acctCode; };

    load = (callback = null) => {
        const tools = getTools();
        tools.json({
            action: 'read',
            url: '/recurring/attendant/api/merchant/customer/profile',
            onSuccess: (data) => {
                var profileData = data['content']['profile'][0];
                if (profileData) {
                    this.setHasProfile(true);
                }
                this.setUsername(profileData['username']);
                this.setName(profileData['name']);
                this.setEmail(profileData['email']);
                this.setCompany(profileData['company']);
                this.setAddr1(profileData['address1']);
                this.setAddr2(profileData['address2']);
                this.setCity(profileData['city']);
                this.setState(profileData['state']);
                this.setPostalCode(profileData['postalCode']);
                this.setCountry(profileData['country']);
                this.setShippingName(profileData['shippingName']);
                this.setShippingAddr1(profileData['shippingAddress1']);
                this.setShippingAddr2(profileData['shippingAddress2']);
                this.setShippingCity(profileData['shippingCity']);
                this.setShippingState(profileData['shippingState']);
                this.setShippingPostalCode(profileData['shippingPostalCode']);
                this.setShippingCountry(profileData['shippingCountry']);
                this.setPhone(profileData['phone']);
                this.setFax(profileData['fax']);
                this.setStatus(profileData['status']);
                this.setRecurringFee(profileData['recurringFee']);
                this.setStartDate(profileData['startDate']);
                this.setEndDate(profileData['endDate']);
                this.setBalance(profileData['balance']);
                this.setBillCycle(profileData['billCycle']);
                this.setAccountCode(profileData['acctCode']);
                this._loaded = true;

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
                if (xhr.status === 422) {
                    this.setError(xhr['responseJSON']['content']['data']['message']);
                } else {
                    this.setError('Failed to load profile.');
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

        const data = {
            name: this._name,
            email: this._email,
            address1: this._addr1,
            address2: this._addr2,
            city: this._city,
            state: this._state,
            postalCode: this._postalCode,
            country: this._country,
            shippingName: this._shippingName,
            shippingAddr1: this._shippingAddr1,
            shippingAddr2: this._shippingAddr2,
            shippingCity: this._shippingCity,
            shippingState: this._shippingState,
            shippingPostalCode: this._shippingPostalCode,
            shippingCountry: this._shippingCountry,
            phone: this._phone,
            fax: this._fax,
            status: this._status,
            recurringFee: this._recurringFee,
            startDate: this._startDate,
            balance: this._balance,
            billCycle: this._billCycle,
        };

        if (this._acctCode !== null && this._acctCode !== "") {
            data.acctCode = this._acctCode;
        }

        window.console.log(data);

        const setHasProfile = () => {
            this.setHasProfile(true);
        };
        
        const tools = getTools();
        tools.json({
            action: action,
            data: data,
            url: '/recurring/attendant/api/merchant/customer/profile',
            onSuccess: [setHasProfile,callbacks.onSuccess],
            onError: callbacks.onError
        });
    };

    deleteCustomerProfile = (onSuccess, onError) => {
        const tools = getTools()
        tools.json({
            action: 'delete',
            data: {},
            url: '/recurring/attendant/api/merchant/customer/profile',
            onSuccess: onSuccess,
            onError: onError
        });
    };

    updateCustomerPassword = (onSuccess, onError, password) => {
        const tools = getTools();
        tools.json({
            action: 'update',
            url: '/recurring/attendant/api/merchant/customer/password',
            data: password,
            onSuccess: onSuccess,
            onError: onError
        });
    }

    didLoad = (callback) => {
        if (typeof(callback) === "function") {
            if (this._loaded) {
                callback(this);
            } else {
                this._loadedCallbacks.push(callback);
            }
        }
    }
};

export default CustomerProfile;