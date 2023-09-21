import React, {Component} from "react";
import Adjustment from '../Lib/Objects/Adjustment';
import FormElement from "../Lib/FormElement";
import Country from "../Lib/Objects/Country";
import State from '../Lib/Objects/State';
import BillMember from "../Lib/Objects/BillMember";
import Transaction,{createTransaction} from "../Lib/Objects/Transaction";
import getTools from "../Lib/Objects/Tools";
import {getPaymentFormDataSettings} from '../Lib/Payment';
import { withRouter } from "react-router-dom";
import PNPModal, {PNPModalButtons} from '../PNPComponents/PNPModal/PNPModal';
import PNPButton from '../PNPComponents/PNPButton/PNPButton';
import { Button, AnimatedButton } from "../PNPComponents/Button/Button";


class MakePayment extends Component {

    constructor(props) {
        super(props);

        this.cursor = 0;

        this.knownFields = [
            'name',
            'emailAddress',
            'company',
            'phoneNumber',
            'fax',
            'address1',
            'address2',
            'city',
            'state',
            'postalCode',
            'country',
            'shippingName',
            'shippingAddress1',
            'shippingAddress2',
            'shippingCity',
            'shippingState',
            'shippingPostalCode',
            'shippingCountry',
            'cardNumber',
            'accountNumber',
            'routingNumber',
            'token',
            'expirationMonth',
            'expirationYear',
            'amount',
            'cvv',
            'accountType',
            'adjustmentAmount',
            'disclaimer',
            'paymentType'
        ];

        this.state = {
            formData: {
                cvv: '',
                paymentType: '',
                cardNumber: '',
                accountNumber: '',
                routingNumber: '',
                accountType: '',
                cursor: 0,
                statesLoaded: false,
                disabled: false
            },
            saveProfile: false,
            savePayment: false,
            saveProfileAndPayment: false,
            saveProfileCheckboxExists: false,
            resultsSuccess: false,
            resultsError: false,
            selectedCountry: '',
            responseMessage: '',
            responseStatus: '',
            modalVisible: false,
            btnContent: '',
            deleteProfile: false,
            profileErrorMsg: null
        };

        this.field = {};
    }

    componentWillMount() {
        let formData = {...this.state.formData};

        const date = new Date();
        formData["expirationMonth"] = date.getMonth() + 1;
        formData["expirationYear"] = date.getFullYear();
        formData["paymentType"] = 'card';
        formData["amount"] = getTools().formatCurrency(parseFloat(0).toFixed(2));
        formData["totalAmount"] = getTools().formatCurrency(parseFloat(0).toFixed(2));
        formData["adjustmentAmount"] = getTools().formatCurrency(parseFloat(0).toFixed(2));
        this.setState({formData: formData});
    };

    componentDidMount() {
        this.initSection();
    }

    componentDidUpdate(prevProps, prevState) {
        if (prevProps.states !== this.props.states) {
            if (this.props.states.length > 1) {
                const formData = {...this.state.formData};
                formData['statesLoaded'] = true;
                this.setState({ formData: formData });
            }
        }
    }

    componentWillReceiveProps(nextProps) {
        if (nextProps.country !== this.props.country || nextProps.country === this.props.country) {
            const formData = {...this.state.formData};
            formData['disabled'] = false;
            formData['statesLoaded'] = true;
            this.setState({ formData });
        }
    }

    toggleModalHandler = (callback) => {
        if (typeof(callback) === 'function') {
            callback();
        }

        this.dimBackground();
        this.setState( prevState => ({
            modalVisible: !prevState.modalVisible
        }), () => {
            if (this.state.modalVisible) {
                try {
                    const viewHeight = Math.max(document.documentElement.clientHeight,window.innerHeight || 0);
                    const modalElement = document.getElementById("modal");
                    const delta = (modalElement.getBoundingClientRect().top + window.scrollY);

                    if (viewHeight <= (modalElement.clientHeight + delta)) {
                        modalElement.scrollIntoView(true);
                    } else {
                        window.scrollTo(0,0);
                    }
                } catch (e) {
                    window.scrollTo(0, 0);
                }
            }
        });
    };

    dimBackground = () => {
        document.getElementById('modal-cover').style.cssText = "background-color: rgb(0,0,0);\n" +
            "                opacity: 0.8;\n" +
            "                display: block;\n" +
            "                width: 100%;\n" +
            "                height: 4000px;\n" +
            "                position: absolute;\n" +
            "                z-index: 999998;\n" +
            "                margin-top: -2100px;\n";
    };

    clearBackground = () => {
        document.getElementById('modal-cover').style.cssText = '';
    };

    clearSession = () => {
        document.getElementById('logout').click();
    };

    clearModalBackground = () => {
        this.clearBackground();
        this.setState( prevState => ({ modalVisible: !prevState.modalVisible }));
    };

    initFields = () => {
        let fields = {};
        for (let i = 0; i < this.props.settings.elements.length; i++) {
            const field = {...this.props.settings.elements[i]};
            if (field.field) {
                field.defaultValue = field.value;
                fields[field.field] = field;
            }
        }

        this.field = fields;
    };

    initSection = () => {
        const formData = {...this.state.formData};

        this.initFields();

        for (let fieldName in this.field) {
            formData[fieldName] = this.field[fieldName].defaultValue || '';
            if (this.field[fieldName].dataType === 'currency') {
                formData[fieldName] = getTools().formatCurrency(formData[fieldName]);
            }
        }

        // assigns country from the session
        let defaultCountry = null;
        if (this.field.country) {
            defaultCountry = this.field.country.defaultValue;
        }

        this.props.profile.didLoad((profile) => {
            if (profile.hasProfile()) {
                const formDataUpdatedFromProfile = this.loadCustomerProfile(profile, formData);
                defaultCountry = formDataUpdatedFromProfile['country']; // assigns country from the profile
                formDataUpdatedFromProfile['phoneNumber'] = getTools().formatPhoneNumber(formDataUpdatedFromProfile['phoneNumber']);
                this.props.paymentSource.didLoad((paymentSource) => {
                    if (paymentSource.hasPaymentSource()) {
                        const formDataUpdatedFromPaymentSource = this.loadPaymentSource(paymentSource, formDataUpdatedFromProfile);
                        if (paymentSource.isCardPayment()) {
                            // TODO: Fix Adjustment bug where it calculates on the managePaymentInformation section
                            this.getAdjustment(
                                {
                                    'cardNumber': formDataUpdatedFromPaymentSource['cardNumber'],
                                    'amount': formDataUpdatedFromPaymentSource['amount'],
                                    'token': formDataUpdatedFromPaymentSource['token'],
                                    'paymentType': 'card'
                                });
                            this.setState({formData: formDataUpdatedFromPaymentSource});
                        } else if (paymentSource.isACHPayment()) {
                            this.getAdjustment(
                                {
                                    'amount': formDataUpdatedFromPaymentSource['amount'],
                                    'paymentType': 'ach'
                                });
                            this.setState({formData: formDataUpdatedFromPaymentSource});
                        }
                    } else {
                        this.setState({formData: formDataUpdatedFromProfile});
                    }
                });
            } else {
                this.setState({formData: formData});
            }
            this.loadCountryData(formData,defaultCountry);
        });
    };

    fieldValueIfOverride = (fieldName, loadedValue) => {
        const fieldSettings = this.field[fieldName] || {};
        return (fieldSettings.override === 'true' ? fieldSettings.defaultValue : loadedValue);
    };

    fieldValueIfOverrideOnSubmit = (fieldName, loadedValue, formData) => {
        const fieldSettings = this.field[fieldName] || {};
        return (fieldSettings.overrideOnSubmit === 'true' ? fieldSettings.defaultValue : formData[fieldName]);
    };


    loadCustomerProfile = (profileObject,formData) => {
        return this.loadCustomerProfileFunction(profileObject,formData,'fieldValueIfOverride');
    };

    overrideCustomerProfile = (profileObject,formData) => {
        return this.loadCustomerProfileFunction(profileObject,formData,'fieldValueIfOverrideOnSubmit');
    };

    loadCustomerProfileFunction = (profileObject,formData,functionName) => {
        const formDataCopy = {...formData};

        if (profileObject.hasProfile()) {
            formDataCopy["name"]               = this[functionName]("name",profileObject.getName() || '', formData);
            formDataCopy["address1"]           = this[functionName]("address1",profileObject.getAddr1() || '', formData);
            formDataCopy["address2"]           = this[functionName]("address2",profileObject.getAddr2() || '', formData);
            formDataCopy["city"]               = this[functionName]("city",profileObject.getCity() || '', formData);
            formDataCopy["state"]              = this[functionName]("state",profileObject.getState() || '', formData);
            formDataCopy["country"]            = this[functionName]("country",profileObject.getCountry() || '', formData);
            formDataCopy["postalCode"]         = this[functionName]("postalCode",profileObject.getPostalCode() || '', formData);
            formDataCopy["emailAddress"]       = this[functionName]("emailAddress",profileObject.getEmail() || '', formData);
            formDataCopy["phoneNumber"]        = this[functionName]("phoneNumber",profileObject.getPhone() || '', formData);
            formDataCopy["company"]            = this[functionName]("company",profileObject.getCompany() || '', formData);
            formDataCopy["faxNumber"]          = this[functionName]("faxNumber",profileObject.getFax() || '', formData);
            formDataCopy["shippingName"]       = this[functionName]("shippingName",profileObject.getShippingName() || '', formData);
            formDataCopy["shippingAddress1"]   = this[functionName]("shippingAddress1",profileObject.getShippingAddr1() || '', formData);
            formDataCopy["shippingAddress2"]   = this[functionName]("shippingAddress2",profileObject.getShippingAddr2() || '', formData);
            formDataCopy["shippingCity"]       = this[functionName]("shippingCity",profileObject.getShippingCity() || '', formData);
            formDataCopy["shippingState"]      = this[functionName]("shippingState",profileObject.getShippingState() || '', formData);
            formDataCopy["shippingPostalCode"] = this[functionName]("shippingPostalCode",profileObject.getShippingPostalCode() || '', formData);
            formDataCopy["shippingCountry"]    = this[functionName]("shippingCountry",profileObject.getShippingCountry() || '', formData);
            formDataCopy["accountCode1"]       = this[functionName]("accountCode1",profileObject.getAccountCode() || '', formData);
            formDataCopy["status"]             = profileObject.getStatus() || '';
        }

        return formDataCopy;
    };

    loadPaymentSource = (paymentSourceObj, formData) => {
        const formDataCopy = {...formData};
        if (paymentSourceObj.hasPaymentSource()) {
            formDataCopy["token"] = paymentSourceObj.getToken() || '';
            if (paymentSourceObj.isACHPayment()) {
                formDataCopy["paymentType"] = 'ach';
                formDataCopy["routingNumber"] = paymentSourceObj.getRoutingNumber() || '';
                formDataCopy["accountNumber"] = paymentSourceObj.getAccountNumber() || '';
                formDataCopy["accountType"]  = paymentSourceObj.getAccountType() || '';
            } else if (paymentSourceObj.isCardPayment()) {
                formDataCopy["paymentType"] = 'card';
                formDataCopy["cardNumber"] = paymentSourceObj.getCardNumber() || '';
                formDataCopy["expirationMonth"] = paymentSourceObj.getExpirationMonth() || '';
                formDataCopy["expirationYear"] = paymentSourceObj.getExpirationYear() || '';
            }
        } else {
            formDataCopy["paymentType"] = 'card';
        }

        return formDataCopy;
    };

    setCustomerProfile = (callbacks) => {
        this.props.profile.setName(this.state.formData.name);
        this.props.profile.setAddr1(this.state.formData.address1);
        this.props.profile.setAddr2(this.state.formData.address2);
        this.props.profile.setCity(this.state.formData.city);
        this.props.profile.setState(this.state.formData.state);
        this.props.profile.setCountry(this.state.formData.country);
        this.props.profile.setPostalCode(this.state.formData.postalCode);
        this.props.profile.setEmail(this.state.formData.emailAddress);
        this.props.profile.setPhone(this.state.formData.phoneNumber);
        this.props.profile.setFax(this.state.formData.faxNumber);
        this.props.profile.setCompany(this.state.formData.company);
        this.props.profile.setShippingName(this.state.formData.shippingName);
        this.props.profile.setShippingAddr1(this.state.formData.shippingAddress1);
        this.props.profile.setShippingAddr2(this.state.formData.shippingAddress2);
        this.props.profile.setShippingCity(this.state.formData.shippingCity);
        this.props.profile.setShippingState(this.state.formData.shippingState);
        this.props.profile.setShippingPostalCode(this.state.formData.shippingPostalCode);
        this.props.profile.setShippingCountry(this.state.formData.shippingCountry);
        this.props.profile.setStatus('ACTIVE');
        this.props.profile.setAccountCode(this.state.formData.accountCode1);
        this.props.profile.save(
            {
                onSuccess: (response) => {
                    if (typeof(callbacks.onSuccess) === "function") {
                        callbacks.onSuccess(response);
                    }
                },
                onError: () => {
                    if (typeof(callbacks.onError) === "function") {
                        callbacks.onError();
                    }
                }
            }
        );
    };

    customerProfileChanged = () => {
        let unchanged = true;

        const tools = getTools();

        let phone = this.state.formData.phoneNumber;
        if (phone) {
            phone = phone.replace(/[^\d]/g, '');
        }

        let fax = this.state.formData.faxNumber;
        if (fax) {
            fax = fax.replace(/[^\d]/g, '');
        }

        // "", null, and undefined will result in change
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.name) === tools.nullOrValue(this.props.profile.getName()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.address1) === tools.nullOrValue(this.props.profile.getAddr1()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.address2) === tools.nullOrValue(this.props.profile.getAddr2()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.city) === tools.nullOrValue(this.props.profile.getCity()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.state) === tools.nullOrValue(this.props.profile.getState()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.country) === tools.nullOrValue(this.props.profile.getCountry()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.postalCode) === tools.nullOrValue(this.props.profile.getPostalCode()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.emailAddress) === tools.nullOrValue(this.props.profile.getEmail()));
        unchanged = unchanged && (tools.nullOrValue(phone) === tools.nullOrValue(this.props.profile.getPhone()));
        unchanged = unchanged && (tools.nullOrValue(fax) === tools.nullOrValue(this.props.profile.getFax()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.company) === tools.nullOrValue(this.props.profile.getCompany()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.shippingName) === tools.nullOrValue(this.props.profile.getShippingName()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.shippingAddress1) === tools.nullOrValue(this.props.profile.getShippingAddr1()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.shippingAddress2) === tools.nullOrValue(this.props.profile.getShippingAddr2()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.shippingCity) === tools.nullOrValue(this.props.profile.getShippingCity()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.shippingState) === tools.nullOrValue(this.props.profile.getShippingState()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.shippingPostalCode) === tools.nullOrValue(this.props.profile.getShippingPostalCode()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.shippingCountry) === tools.nullOrValue(this.props.profile.getShippingCountry()));
        unchanged = unchanged && (tools.nullOrValue(this.state.formData.accountCode1) === tools.nullOrValue(this.props.profile.getAccountCode()));
        return !unchanged; // invert response
    };

    setPaymentSource = (callbacks) => {
        this.props.paymentSource.setPaymentType(this.state.formData.paymentType); // make sure to set payment type or it defaults to ach
        this.props.paymentSource.setAccountNumber(this.state.formData.accountNumber);
        this.props.paymentSource.setRoutingNumber(this.state.formData.routingNumber);
        this.props.paymentSource.setAccountType(this.state.formData.accountType);
        this.props.paymentSource.setCardNumber(this.state.formData.cardNumber);
        this.props.paymentSource.setExpirationMonth(this.state.formData.expirationMonth);
        this.props.paymentSource.setExpirationYear(this.state.formData.expirationYear);
        this.props.paymentSource.setToken(this.state.formData.token);
        this.props.paymentSource.save(
            {
                onSuccess: () => {
                    if (typeof(callbacks.onSuccess) === "function") {
                        callbacks.onSuccess();
                    }
                },
                onError: () => {
                    if (typeof(callbacks.onError) === "function") {
                        callbacks.onError();
                    }
                }
            }
        );
    };

    paymentSourceChanged = () => {
        let changed = true;

        // strip the current cardNumber of its spaces
        const formData = {...this.state.formData};

        let cardNumber = formData['cardNumber'];
        let routingNumber = formData['routingNumber'];
        let accountNumber = formData['accountNumber'];

        let accountType = formData['accountType'];
        if (accountType) {
            accountType = accountType.toLowerCase();
        }

        cardNumber = cardNumber.replace(/\s/g, '');
        routingNumber = routingNumber.replace(/\s/g, '');
        accountNumber = accountNumber.replace(/\s/g, '');

        const tools = getTools();

        // short circuit if type changed
        if (this.state.formData.paymentType !== this.props.paymentSource.getPaymentType()) {
            changed = true;
        } else {
            changed = changed && (tools.nullOrValue(cardNumber)    === tools.nullOrValue(this.props.paymentSource.getCardNumber()));
            changed = changed && (tools.nullOrValue(routingNumber) === tools.nullOrValue(this.props.paymentSource.getRoutingNumber()));
            changed = changed && (tools.nullOrValue(accountNumber) === tools.nullOrValue(this.props.paymentSource.getAccountNumber()));
            changed = changed && (accountType === this.props.paymentSource.getAccountType());
            changed = !changed; // invert as we are checking to see if true is preserved
        }

        return changed;
    };

    getBillMember = () => {
        let { accountCode1, accountCode2, accountCode3 } = this.state.formData;
        const billMember = new BillMember();
        const settings = this.props.session.getAdditionalData();
        if (settings['merchantClassifierID']) {
            billMember.setMerchantClassifierID(settings['merchantClassifierID']);
        }
        billMember.setAmount(this.fieldValue('amount'));
        billMember.setCVV(this.fieldValue('cvv'));
        // get the account code from the profile if it is "" in the form.
        // the only way accountCode1 could be an empty string is if it was null originally when pulled from the responder.
        if (accountCode1 === "") {
            accountCode1 = this.props.profile.getAccountCode();
        }

        if (accountCode1) {
            billMember.setAccountCode(0, accountCode1);
        }

        if (accountCode2) {
            billMember.setAccountCode(1, accountCode2);
        }

        if (accountCode3) {
            billMember.setAccountCode(2, accountCode3);
        }

        return billMember;
    };

    getTransaction = () => {
        // TODO: Add validation here/call the method, and check for paymentSource before sending transaction.

        let transaction = new Transaction();
        let sessionData = this.props.session.getAdditionalData();

        let {
            amount,
            name,
            address1,
            city,
            state,
            postalCode,
            country,
            phoneNumber,
            emailAddress,
            shippingName,
            shippingAddress1,
            shippingCity,
            shippingState,
            shippingPostalCode,
            shippingCountry,
            paymentType,
            accountNumber,
            routingNumber,
            accountType,
            cardNumber,
            expirationMonth,
            expirationYear,
            cvv,
            token,
            accountCode1,
            accountCode2,
            accountCode3
        } = this.state.formData;

        transaction.setAmount(amount);
        transaction.setBillingName(name);
        transaction.setBillingAddress(address1);
        transaction.setBillingCity(city);
        transaction.setBillingState(state);
        transaction.setBillingPostalCode(postalCode);
        transaction.setBillingCountry(country);
        transaction.setBillingPhone(phoneNumber);
        transaction.setBillingEmail(emailAddress);
        transaction.setShippingName(shippingName);
        transaction.setShippingAddress(shippingAddress1);
        transaction.setShippingCity(shippingCity);
        transaction.setShippingState(shippingState);
        transaction.setShippingPostalCode(shippingPostalCode);
        transaction.setShippingCountry(shippingCountry);
        transaction.setShippingPhone(phoneNumber);
        transaction.setShippingEmail(emailAddress);
        transaction.setToken(token);
        transaction.setMerchantClassifierID(sessionData['merchantClassifierID']);

        transaction.setType(paymentType);
        transaction.setMode('authorization');

        transaction.setPaymentType(paymentType);
        if (transaction.getPaymentType() === 'card') {
            const tools = getTools();

            if (tools.validateCreditCard(cardNumber)) { // card is valid, then use it
                transaction.setCardNumber(cardNumber);  // it is possible for the token stored in state not to be the same
                transaction.setToken(undefined);        // that was typed in, so remove the token!
            }

            transaction.setExpirationMonth(expirationMonth);
            transaction.setExpirationYear(expirationYear);
            transaction.setCVV(cvv);
        } else if (transaction.getPaymentType() === 'ach') {
            const tools = getTools();

            if (tools.validateRoutingNumber(routingNumber)) {
                transaction.setRoutingNumber(routingNumber);
                transaction.setAccountNumber(accountNumber);
                transaction.setToken(undefined);
            }

            transaction.setAccountType(accountType);
        }

        if (accountCode1 === "") {
            accountCode1 = this.props.profile.getAccountCode();
        }

        if (accountCode1) {
            transaction.setAccountCode(0, accountCode1);
        }

        if (accountCode2) {
            transaction.setAccountCode(1, accountCode2);
        }

        if (accountCode3) {
            transaction.setAccountCode(2, accountCode3);
        }

        return transaction;
    }

    getAdjustment = (data, usePaymentSource = true) => {
        if (this.props.settings.mode !== 'payment') {
            return;
        }

        let cardNumber;
        if (data['cardNumber'] || this.state.formData.cardNumber) {
            cardNumber = (this.state.formData.cardNumber || data['cardNumber']).replace(/[^0-9*]/g,'');
        }
        let amount = '0.00';
        if (data['amount'] || this.state.formData.amount) { // check for undefined values
            amount = (data['amount'] || this.state.formData.amount).replace(/[^0-9.]/g, '');
        }
        let token = this.state.formData.token || data['token'];
        let adjustmentData;
        if ( (amount && cardNumber) || (amount && data['paymentType'] === 'ach') ) {
            if (this.props.paymentSource.hasPaymentSource()) {
                if (usePaymentSource) {
                    let paymentType = this.props.paymentSource.getPaymentType();
                    if (paymentType) {
                        paymentType = paymentType.toUpperCase();
                    }

                    adjustmentData = {
                        transactionInformation:
                            [{
                                "paymentVehicleType": paymentType,
                                "transactionAmount": amount,
                                "paymentVehicleIdentifier": "tempID",
                                "token": token
                            }],
                        "transactionAmount": amount,
                        "transactionIdentifier": "tempID"
                    };
                } else {
                    if (data['paymentType'] === 'ach') {
                        adjustmentData = {
                            transactionInformation:
                                [{
                                    "paymentVehicleType": 'ACH',
                                    "transactionAmount": amount,
                                    "paymentVehicleIdentifier": "tempID",
                                }],
                            "transactionAmount": amount,
                            "transactionIdentifier": "tempID"
                        }
                    } else {
                        adjustmentData = {
                            transactionInformation:
                                [{
                                    "cardNumber": cardNumber,
                                    "paymentVehicleType": 'CARD',
                                    "transactionAmount": amount,
                                    "paymentVehicleIdentifier": "tempID",
                                }],
                            "transactionAmount": amount,
                            "transactionIdentifier": "tempID"
                        }
                    }
                }
            } else {
                adjustmentData = {
                    transactionInformation:
                        [{
                            "cardNumber": cardNumber,
                            "paymentVehicleType": data['paymentType'],
                            "transactionAmount": amount,
                            "paymentVehicleIdentifier": "tempID",
                        }],
                    "transactionAmount": amount,
                    "transactionIdentifier": "tempID"
                }
            }

            let lengthToCallAdjustment = 16;
            if (data['paymentType'] !== 'ach' && cardNumber.toString()[0] === "3") {
                lengthToCallAdjustment = 15;
            }

            if (data['paymentType'] === 'card' && cardNumber.replace(/[^0-9*]/g,'').length >= lengthToCallAdjustment && amount) {
                if (this.props.paymentSource.getCardNumber() === cardNumber.replace(/ /g, '') || getTools().validateCreditCard(cardNumber)) {
                    let adjustment = new Adjustment(adjustmentData);
                    adjustment.loadAdjustment({
                        'onSuccess': (data) => {
                            let fee = data["content"]["tempID"]['calculatedAdjustment']['adjustment'];
                            let formData = {...this.state.formData};
                            if (formData['amount']) {
                                let amt = parseFloat(formData['amount'].replace(/,/g, ''));
                                formData["totalAmount"] = getTools().formatCurrency(amt + parseFloat(fee));
                                formData["adjustmentAmount"] = getTools().formatCurrency((fee || 0).toFixed(2));
                                this.setState({formData: formData});
                            }
                        },
                        'onError': (data) => {
                            console.log("Error: ", data);
                        }
                    });
                }
            } else if (data['paymentType'] === 'ach' && amount) {
                let adjustment = new Adjustment(adjustmentData);
                adjustment.loadAdjustment({
                    'onSuccess': (data) => {
                        let fee = data["content"]["tempID"]['calculatedAdjustment']['adjustment'];
                        let formData = {...this.state.formData};
                        if (formData['amount']) {
                            let amt = parseFloat(formData['amount'].replace(/,/g, ''));
                            formData["totalAmount"] = getTools().formatCurrency(amt + parseFloat(fee));
                            formData["adjustmentAmount"] = getTools().formatCurrency((fee || 0).toFixed(2));
                            this.setState({formData: formData});
                        }
                    },
                    'onError': (data) => {
                        console.log("Error: ", data);
                    }
                });
            }
        }
    };

    handleSubmit = (event, callback) => {
        const doTransaction = (this.props.settings.mode === "payment");
        const addMember = (this.props.settings.mode === "addMember");

        const previousFormData = {...this.state.formData};
        const formData = this.overrideCustomerProfile(this.props.profile,this.state.formData);

        this.setState({formData: formData},() => {
            // helper function to do bill member with callbacks
            const billMember = () => {
                this.getBillMember().billCustomer({
                    onSuccess: (response) => {
                        if (response.billed()) {
                            this.setState({
                                responseStatus: response.getStatus(),
                                responseMessage: "Transaction Successful.",
                                modalPaymentOrderID: response.getOrderID(),
                                modalPaymentDateTime: response.getDateTime()
                            }, () => {
                                this.toggleModalHandler(callback);
                            });
                        } else {
                            this.setState({
                                responseStatus: response.getStatus(),
                                responseMessage: response.getResponse()
                            }, () => {
                                this.toggleModalHandler(callback);
                            });
                        }
                    },
                    onError: (response) => {
                        this.setState({
                            responseStatus: response.getStatus(),
                            responseMessage: "Transaction Failed."
                        }, () => {
                            this.toggleModalHandler(callback);
                        });
                    }
                });
            };

            // helper function to do transaction with callfacks
            const runTransaction = () => {
                createTransaction(this.getTransaction(), {
                    // supporting only one transaction right now.
                    onSuccess: (transactionResults) => {
                        let transactionResult = transactionResults[0];
                        this.setState({
                            responseStatus: transactionResult.getStatus(),
                            responseMessage: transactionResult.getMessage(),
                            modalPaymentOrderID: transactionResult.getOrderID(),
                            modalPaymentDateTime: transactionResult.getDateTime()
                        }, () => {
                            this.toggleModalHandler(callback);
                        })
                    },
                    onError: (transactionResults) => {
                        let transactionResult = transactionResults[0];
                        this.setState({
                            responseStatus: transactionResult.getStatus(),
                            responseMessage: "Transaction Failed.\n" + transactionResult.getMessage()
                        }, () => {
                            this.toggleModalHandler(callback);
                        })
                    }
                });
            };

            // helper function to handle payment source
            const paymentSourceSaveOrNotChanged = (response = null) => {
                if (this.state.savePayment || this.state.saveProfileAndPayment || addMember) {
                    this.setPaymentSource({
                        onSuccess: () => { // successful payment source save
                            console.warn("Successfully saved payment source.");
                            if (doTransaction) {
                                billMember();
                            } else {
                                this.setState({
                                    responseStatus: response['content']['status'],
                                    responseMessage: response['content']['message'],
                                    btnContent: 'CLOSE'
                                }, () => {
                                    this.toggleModalHandler(callback);
                                });
                            }
                        },
                        onError: () => { // Failed to save payment source.
                            this.setState({
                                responseStatus: 'failure',
                                responseMessage: 'Failed to save payment source.',
                                btnContent: 'CLOSE',
                            }, () => {
                                this.toggleModalHandler(callback);
                            });
                        }
                    });
                } else if (doTransaction) {
                    if (this.props.paymentSource.hasPaymentSource() && !this.paymentSourceChanged()) { // payment source loaded but no info changed
                        billMember();
                    } else {
                        runTransaction();
                    }
                }
            };

            // start of main logic for handleSubmit
            if (this.state.saveProfile || this.state.saveProfileAndPayment || addMember) {
                this.setCustomerProfile({
                    onSuccess: (response) => { // successful profile save
                        paymentSourceSaveOrNotChanged(response);
                    },
                    onError: () => {
                        console.warn("Failed to save customer profile.");
                        this.setState({ formData: previousFormData });
                    }
                });
            } else if (this.props.profile.hasProfile() && !this.customerProfileChanged()) { // customer profile loaded but no info changed
                paymentSourceSaveOrNotChanged();
            } else if (doTransaction) {
                runTransaction();
            }
        });
    };

    fieldValue = (fieldName) => {
        return this.state.formData[fieldName] || ''
    };

    handleFormDataChange = (event) => {
        event.target.classList.remove('error');

        const name = event.target.name;
        let value = event.target.value;

        let formData = {...this.state.formData};

        // this tells the fieldValue function to only use the state value rather than session initial values
        this.field[name] = this.field[name] || {};
        this.field[name].edited = true;

        const cursorIndex = event.target.selectionStart;

        if (name === "country") {
            formData['disabled'] = true; // disable the button while data is being changed.
            formData['state'] = '';
            formData[name] = value;
            this.props.loadStates(value);
        } else if (name === 'cardNumber') {
            if (formData.cardNumber.indexOf('*') >= 0) {
                if (this.lastKey && this.lastKey.match(/\d/)) {
                    formData['cardNumber'] = this.lastKey;
                } else {
                    formData['cardNumber'] = '';
                }
            } else {
                formData['cardNumber'] = getTools().formatCreditCard(value);
            }
        } else if (name === 'phoneNumber') {
            formData['phoneNumber'] = getTools().formatPhoneNumber(value);
        } else if (name === 'amount') {
            formData['amount'] = value;
        } else if (name === "savePayment" || name === "saveProfile") {
            formData[name] = !this.state[name];
        } else if (name === "state") {
            formData[name] = value;
            formData['statesLoaded'] = true;
        } else if (name === 'routingNumber') {
            if (formData.routingNumber.indexOf('*') >= 0) {
                if (this.lastKey && this.lastKey.match(/\d/)) {
                    formData['routingNumber'] = this.lastKey;
                } else {
                    formData['routingNumber'] = '';
                }
            } else {
                formData['routingNumber'] = value;
            }
        } else if (name === 'accountNumber') {
            if (formData.accountNumber.indexOf('*') >= 0) {
                if (this.lastKey && this.lastKey.match(/\d/)) {
                    formData['accountNumber'] = this.lastKey;
                } else {
                    formData['accountNumber'] = '';
                }
            } else {
                formData['accountNumber'] = value;
            }
        } else {
            formData[name] = value;
        }

        formData['cursor'] = cursorIndex;
        this.lastKey = '';

        this.setState({
            formData: formData
        });
    };

    handleCheckboxChange = (event) => {
        /*
        Save profile only if profile is checked.
        Only allow save of payment source if save profile is checked OR they already have a profile.
         */

        if (event.target.name === 'saveProfile') {
            let checkState = {
                saveProfile: event.target.checked
            };

            if (!event.target.checked && this.state.savePayment && !this.props.profile.hasProfile()) {
                checkState['savePayment'] = false;
            }

            this.setState(checkState);
        } else if (event.target.name === 'savePayment' && (this.state.saveProfile || this.props.profile.hasProfile())) {
            this.setState({savePayment: event.target.checked});
        } else if (event.target.name === 'saveProfileAndPayment') {
            this.setState({
                saveProfileAndPayment: event.target.checked,
                savePayment: event.target.checked,
                saveProfile: event.target.checked
            });
        }
    };

    handlePaymentTypeRadioChange = (type) => {
        // the type sent in is the new value of the radio
        var formData = {...this.state.formData};

        var resetCardValues = false;
        var resetACHValues = false;

        // if customer has payment source, set it to the loaded data
        const hasPaymentSource = this.props.paymentSource.hasPaymentSource();
        if (hasPaymentSource) {
            if (type === 'card') {
                if (this.props.paymentSource.isCardPayment()) {
                    formData['cardNumber'] = this.props.paymentSource.getCardNumber();
                    formData['expirationMonth'] = this.props.paymentSource.getExpirationMonth();
                    formData['expirationYear'] = this.props.paymentSource.getExpirationYear();
                    formData['token'] = this.props.paymentSource.getToken() || '';
                } else {
                    resetCardValues = true;
                }

                resetACHValues = true;
            } else if (type === 'ach') {
                if (this.props.paymentSource.isACHPayment()) {
                    formData['routingNumber'] = this.props.paymentSource.getRoutingNumber();
                    formData['accountNumber'] = this.props.paymentSource.getAccountNumber();
                    formData['accountType'] = this.props.paymentSource.getAccountType();
                    formData['token'] = this.props.paymentSource.getToken() || '';
                } else {
                    resetACHValues = true;
                }

                resetCardValues = true;
            }
        } else {
            resetCardValues = resetACHValues = true;
        }

        if (resetACHValues) {
            formData['routingNumber'] = '';
            formData['accountNumber'] = '';
            formData['accountType'] = 'checking';
            formData['token'] = '';
        }

        if (resetCardValues) {
            formData['cardNumber'] = '';

            const date = new Date();
            formData["expirationMonth"] = date.getMonth() + 1;
            formData["expirationYear"] = date.getFullYear();
            formData['cvv'] = '';
            formData['token'] = '';
        }

        formData['paymentType'] = type;
        this.setState({formData});
        this.getAdjustment(formData, false);
    };

    formElementInfo = (fieldObj) => {
        let fieldInfo = {};
        fieldInfo["field"] = fieldObj.field;
        fieldInfo["display"] = true;
        fieldInfo["label"] = fieldObj.label;
        fieldInfo["optional"] = (fieldObj.optional);
        fieldInfo["optionalLabel"] =(fieldObj.optionalLabel);
        fieldInfo["settingsValue"] = fieldObj.value;
        fieldInfo["fieldValueOptions"] = fieldObj.values;
        fieldInfo["type"] = fieldObj.type;
        fieldInfo["prefix"] = fieldObj.prefix;
        fieldInfo["bold"] = (fieldObj.bold);
        fieldInfo["dataType"] = fieldObj.dataType;
        fieldInfo["cvvHidden"] = fieldObj.cvvHidden;
        fieldInfo["formula"] = fieldObj.formula;
        fieldInfo["valueMap"] = fieldObj.valueMap;
        fieldInfo['paymentTypeOptions'] = fieldObj.paymentTypeOptions;
        return fieldInfo;
    };

    createFormElement = (field, index) => {
        const fieldInfo = this.formElementInfo(field);

        let className = "";

        if (!fieldInfo.display) {
            className = "hidden ";
        }

        if (fieldInfo.type === "readOnly") {
            className = className + "narrow";
        }
        if (fieldInfo.field === "savePayment" || fieldInfo.field === "saveProfile" || fieldInfo.field === "saveProfileAndPayment") {
            className = "pushLeft";
        }
        let dataSource;
        if (fieldInfo.label === "State") {
            dataSource = this.props.states;
        }
        if (fieldInfo.label === "Country") {
            dataSource = this.props.countries;
        }

        let changeHandler = this.handleFormDataChange;

        if (fieldInfo.type === "checkbox") {
            changeHandler = this.handleCheckboxChange;
        }

        let paymentTypeChangeHandler;
        let fieldValue = this.fieldValue(fieldInfo.field, fieldInfo.settingsValue);
        if (fieldInfo.type === "payment") {
            paymentTypeChangeHandler = this.handlePaymentTypeRadioChange;
            fieldValue = {
                paymentType: this.state.formData.paymentType,
                token: this.state.formData.token,
                cardNumber: getTools().formatCreditCard(this.state.formData.cardNumber),
                routingNumber: this.state.formData.routingNumber,
                accountNumber: this.state.formData.accountNumber,
                accountType: this.state.formData.accountType,
                expirationYear: this.state.formData.expirationYear,
                expirationMonth: ("0" + (this.state.formData.expirationMonth)).slice(-2),
                cvv: this.state.formData.cvv
            };
        }

        let hiddenLi;
        if (fieldInfo.type === 'hidden') {
            hiddenLi = { display: "none" };
        }

        return (
            <li style={hiddenLi} key={(fieldInfo.type+fieldInfo.field+index)} className={className}>
                <FormElement
                    paymentTypeOptions={fieldInfo.paymentTypeOptions}
                    paymentTypeChangeHandler={paymentTypeChangeHandler}
                    change={changeHandler}
                    fieldName={fieldInfo.field}
                    label={fieldInfo.label}
                    optional={fieldInfo.optional}
                    optionalLabel={fieldInfo.optionalLabel}
                    type={fieldInfo.type}
                    index={index}
                    error={fieldInfo.error}
                    bold={fieldInfo.bold}
                    fieldValue={fieldValue}
                    fieldPrefix={fieldInfo.prefix}
                    dataType={fieldInfo.dataType}
                    fieldValueOptions={fieldInfo.fieldValueOptions}
                    dataSource={dataSource}
                    checked={this.state[fieldInfo.field]}
                    cvvHidden={fieldInfo.cvvHidden}
                    formula={fieldInfo.formula}
                    valueMap={fieldInfo.valueMap}
                    data={this.state.formData}
                    blur={this.handleBlur}
                    onKeyPress={this.onKeyPress}
                    onClickInput={this.onClickInput}
                    cursor={this.state.formData.cursor}
                />
            </li>
        );
    };

    loadCountryData = (formData,selectedCountry) => {
        // Is this used anymore? Countries are also loaded in Attendant.js
        let countryCode = new Country();
        let countries = [];

        countryCode.loadCountries({'success': (data) => {
                let tmpCountries = data.getCountries();
                tmpCountries.map((country) => {
                    countries.push({'value': country.getTwoLetter(), 'displayValue': country.getCommonName()});
                });

                if (selectedCountry) {
                    this.props.loadStates(selectedCountry)
                }

                formData.countries = countries;
            }, 'error': (error) => console.log(error)
        });

    }

    handleBlur = (event) => {
        let field = event.target;

        let dataType = '';
        let usePaymentSource = true;

        //so not efficient but let's get this out the door already
        this.props.settings["elements"].map((settings, i) => {
            if (field.name === settings.field) {
                dataType = settings.dataType;
            }
            return null;
        });

        const name = field.name;
        let value = field.value;
        if (dataType === 'currency') {
            value = getTools().formatCurrency(value);
        }

        let state = {...this.state};
        state.formData[name] = value;

        this.setState(state,() => {
            let formData = {...this.state.formData};
            let cardNumber = formData['cardNumber'];
            cardNumber = cardNumber.replace(/\s/g, '');
            usePaymentSource = this.props.paymentSource.getCardNumber() === cardNumber;

            if ((name === 'amount' || name === 'cardNumber' || name === 'paymentType') && formData['amount']) {
                this.getAdjustment({
                    'cardNumber': formData['cardNumber'].replace(' ',''),
                    'amount': formData['amount'].replace(',',''),
                    'token': formData['token'],
                    'paymentType': formData['paymentType']
                }, usePaymentSource);
            }
            this.validate(field);
        })
    };

    validateSubmit = (event, callback) => {
        let valid = [];
        let field = '';
        let submit = true;

        Object.keys(this.state.formData).map((fieldName, i) => {
            let fieldClass = document.getElementsByClassName('fieldName-' + fieldName);
            field = fieldClass[0];
            if (typeof field !== 'undefined' && field !== null) {
                valid.push(this.validate(field, submit));
            }
            return null;
        });

        if (valid.indexOf(false) < 0) {
            if (typeof(callback) === "function") {
                callback();
            }
            this.handleSubmit(event,callback);
            return true;
        }
    };

    validate = (field, submit) => {
        let dataType = '';
        let optional = '';

        const formData = {...this.state.formData}; // copy form data for validating that states are loaded

        this.props.settings["elements"].map((settings, i) => {
            if (field.name === settings.field) {
                dataType = settings.dataType;
                optional = settings.optional;
            }
            return null;
        });

        if (dataType === '' && optional === '') {
            dataType = getPaymentFormDataSettings(field.name).dataType;
            optional = getPaymentFormDataSettings(field.name).optional;
        }

        let validated = true;

        if (this.props.settings.mode === 'payment' && field.name === 'amount' && parseFloat(field.value) <= 0) {
            validated = false;
        }

        if (field.value !== "") { // removing the && optional === false from here seemed to fix the validation ?.?
            if (dataType === 'emailAddress') {
                validated = getTools().validateEmail(field.value);
            } else if (dataType === 'cardNumber') {
                const cc = field.value.replace(/ /g, '');
                validated = this.props.paymentSource.getCardNumber() === cc;
                if (!validated) {
                    validated = getTools().validateCreditCard(cc);
                }
            } else if (dataType === 'routingNumber') {
                const routingNumber = field.value.replace(/ /g, '');
                validated = this.props.paymentSource.getRoutingNumber() === routingNumber;
                if (!validated) {
                    validated = getTools().validateRoutingNumber(routingNumber);
                }
            } else if (dataType === 'phoneNumber') {
                validated = getTools().validatePhone(field.value);
            } else if (dataType === 'cardExpirationDate') {
                let expMonth = document.getElementsByClassName('fieldName-expirationMonth')[0].value;
                let expYear = document.getElementsByClassName('fieldName-expirationYear')[0].value;
                validated = getTools().validateExpirationDate(expMonth, expYear);
            }
        } else {
            if (optional === "false" || optional === undefined) {
                if (field.value.length === 0) {
                    validated = false;
                }
            }
        }

        if (field.name === 'state') {
           if (!this.hasStates()) {
                validated = true;
           } else {
               if (formData.state === '') {
                   validated = false;
               }
           }
        }

        if (typeof(field.classList) !== 'undefined') {
            if (validated) {
                if (typeof(field.classList.remove) !== 'undefined') {
                    field.classList.remove('error');
                }
            } else {
                if (typeof(field.classList.add) !== 'undefined') {
                    field.classList.add('error');
                    if (submit) {
                        field.focus();
                    }
                }
            }
        }

        return validated;
    };

    getModalSettings = (keypath,defaults,currentPath) => {
        let current = currentPath;
        if (typeof(currentPath) === 'undefined') {
            current = this.props.settings.modals;
        }

        let key = null;
        if (keypath.length >= 1) {
            key = keypath[0];
        }

        let returnValue = null;
        if (typeof(key) === 'undefined' || key === null) {
            returnValue = null
        } else if (keypath.length === 1) {
            returnValue = current[key];
        } else if (keypath.length > 1 && current[key] != null) {
            const newKeypath = keypath.splice(1);
            returnValue = this.getModalSettings(newKeypath,defaults,current[key]);
        }

        // try and load defaults if settings do not exist.
        if (returnValue === null && currentPath === this.props.settings.modals && defaults !== null) {
            returnValue = this.getModalSettings(keypath,null,defaults)
        }

        return returnValue;
    };

    getModal = () => {
        const modalSettings = this.props.settings.modals;

        const modalDefaults = {
            "payment": {
                "success": {
                    "text": "Payment Successful",
                    "payment": "Submit Another Payment",
                    "endSession": "End Session"
                },
                "failure": {
                    "text": "Payment Failure",
                    "payment": "Attempt Another Payment",
                    "endSession": "End Session"
                },
                "badcard": {
                    "text": "Payment Failure",
                    "payment": "Attempt Another Payment",
                    "endSession": "End Session"
                }
            },
            "addMember": {
                "success": {
                    "text": "Update Successful",
                    "payment": "Submit Another Payment",
                    "endSession": "End Session"
                },
                "failure": {
                    "text": "Update Failure",
                    "payment": "Attempt Another Payment",
                    "endSession": "End Session"
                },
                "badcard": {
                    "text": "Update Failure",
                    "payment": "Attempt Another Payment",
                    "endSession": "End Session"
                }
            }
        };


        const responseStatus = this.state.responseStatus;
        let text = this.state.responseMessage;
        let additionalModalContent = null;

        let usDate = null;
        if (this.state.modalPaymentDateTime) {
            let formattedDate = this.state.modalPaymentDateTime;
            let transdate = new Date(formattedDate);
            usDate = ('0' + (transdate.getMonth()+1)).slice(-2) + "/" + ('0' + transdate.getDate()).slice(-2) + "/" + transdate.getFullYear();
        }

        let sign = '';
        let feeOrDiscount = 'Fee';

        if (this.state.formData.adjustmentAmount > 0) {
            sign = '+';
        } else if (this.state.formData.adjustmentAmount < 0) {
            sign = '-';
            feeOrDiscount = 'Discount';
        }

        let currencyPrefix = (typeof(this.props.settings.modals.prefix) !== 'undefined' ? this.props.settings.modals.prefix : "$");
        let feeText = (typeof(this.props.settings.modals.feeText) !== 'undefined' ? this.props.settings.modals.feeText : "Payment " + feeOrDiscount);

        let lastFour = this.state.formData.cardNumber.substr(-4,4);
        let prefix = this.state.formData.cardNumber.substr(0,this.state.formData.cardNumber.length-4).replace(/[\d\*]/g,'X');
        let maskedCard = prefix + lastFour;

        let phoneNumber = (this.state.formData.phoneNumber ? this.state.formData.phoneNumber : '').replace(/- /,'').replace(/ - /,'-');

        let topRight = (this.props.receiptEntityNameTitle ? (
            <td className="td-right purple">
                <p className="modal-label">{this.props.receiptEntityNameTitle}</p>
                <p className="value-bottom purple">{this.props.entityName}</p>
            </td>
        ) : (
            <td className="td-right purple">
                <p className="modal-label">Order ID</p>
                <p className="value-bottom purple">{this.state.modalPaymentOrderID}</p>
            </td>
        ));

        let bottom = (this.props.receiptEntityNameTitle ? (
            <tr>
                <td className="td-left">
                </td>
                <td className="td-right purple">
                    <p className="modal-label">Order ID</p>
                    <p className="value-bottom purple">{this.state.modalPaymentOrderID}</p>
                </td>
            </tr>
        ) : (
            null
        ));

        let transactionInfo = (this.props.settings.mode === "payment" ? (
            <div className="jsx-wrapper">
                <div className="large-break"></div>

                <table className="transaction-info">
                    <tbody>
                    <tr>
                        <td className="td-left">
                            <p className="modal-label">Billing Information</p>
                        </td>
                        <td className="td-right purple">
                            <p className="value-bottom purple">{maskedCard}</p>
                        </td>
                    </tr>
                    <tr>
                        <td className="td-left">
                        </td>
                        <td className="td-right gray">
                            <p className="value-gray-bottom">{this.state.formData.name}</p>
                            <p className="value-gray-bottom">{this.state.formData.address1} {this.state.formData.address2}</p>
                            <p className="value-gray-bottom">{this.state.formData.city}, {this.state.formData.state} {this.state.formData.postalCode}</p>
                        </td>
                    </tr>
                    <tr>
                        <td className="td-left">
                        </td>
                        <td className="td-right gray">
                            <p className="value-gray-bottom">{phoneNumber}</p>
                            <p className="value-gray-bottom">{this.state.formData.emailAddress}</p>
                        </td>
                    </tr>
                    </tbody>
                </table>
            </div>
        ) : null);

        let paymentBreakdown = (
            <div className="payment-breakdown">
                <div className="large-break"></div>

                <table className="transaction-info">
                    <tbody>
                    <tr>
                        <td className="td-left">
                            <p className="modal-label">Date</p>
                            <p className="value-bottom purple">{usDate}</p>
                        </td>
                        {topRight}
                    </tr>
                    {bottom}
                    </tbody>
                </table>

                <div className="large-break"></div>

                <table className="payment-info">
                    <tbody>
                    <tr>
                        <td className="td-left">
                        </td>
                        <td className="td-right gray">
                            <p className="value-gray-top">{currencyPrefix}{this.state.formData.amount}</p>
                        </td>
                    </tr>
                    <tr>
                        <td className="td-left align-right">
                            <span className="plus-minus">{sign}</span>
                        </td>
                        <td className="td-right gray">
                            <p className="value-gray-bottom">{currencyPrefix}{this.state.formData.adjustmentAmount} {feeText}</p>
                        </td>
                    </tr>
                    </tbody>
                </table>

                <div className="small-break"></div>

                <table className="total-info" cellPadding="0">
                    <tbody>
                    <tr>
                        <td className="td-left">
                            <p className="modal-label">Total Amount</p>
                        </td>
                        <td className="td-right purple">
                            <p className="value-bottom purple">{currencyPrefix}{this.state.formData.totalAmount}</p>
                        </td>
                    </tr>
                    </tbody>
                </table>

                {transactionInfo}

                <div className="large-break bottom"></div>
            </div>
        );

        if (this.props.settings.mode === "payment" && this.state.responseStatus === 'success') {
            additionalModalContent = paymentBreakdown;
        }

        let message = null;
        let paymentButtonText;
        let endSessionButtonText;
        if (this.props.settings.mode === "payment" || this.props.settings.mode === "addMember") {
            if (this.state.responseStatus === 'success') {
                text = this.getModalSettings([this.props.settings.mode,responseStatus,'text']);
                paymentButtonText = this.getModalSettings([this.props.settings.mode,responseStatus,'payment']);
                endSessionButtonText = this.getModalSettings([this.props.settings.mode,responseStatus,'endSession']);
                message = this.getModalSettings([this.props.settings.mode, responseStatus,'message']);
            } else {
                additionalModalContent = null;
                endSessionButtonText = this.getModalSettings([this.props.settings.mode,responseStatus,'endSession']);
                paymentButtonText = this.getModalSettings([this.props.settings.mode,responseStatus,'payment']);
                message = this.getModalSettings([this.props.settings.mode, responseStatus,'message']);
            }
        }

        const submitStyle = { color: 'white', display: 'inline-block', margin: '10px' };
        const sessionAdditionalData = this.props.session.getAdditionalData();
        const submitButtonStates = sessionAdditionalData['submitButtonStates'];
        let svgURL;
        for (let i = 0; i < submitButtonStates.length; i++) {
            if (submitButtonStates[i].state === "active" && typeof(submitButtonStates[i].image) !== 'undefined') {
                svgURL = submitButtonStates[i].image.src;
                break;
            }
        }

        let modal = (
            <PNPModal
                id={"modal"}
                title={text}
                visible={this.state.modalVisible}
                message={message}
                additionalModalContent={additionalModalContent}
            >
                <div className="modalButtonContainer">
                    <Button
                        text={paymentButtonText}
                        styling={submitStyle}
                        click={this.clearModalBackground}
                    />
                    <AnimatedButton
                        svgUrl={svgURL}
                        text={endSessionButtonText}
                        styling={submitStyle}
                        click={this.clearSession}
                    />
                </div>
            </PNPModal>
        );

        return modal;
    };

    onDeleteProfileInformationHandler = () => {
        this.dimBackground();
        this.setState({
            deleteProfile: !this.state.deleteProfile
        });
    };

    clearDeleteModalHandler = () => {
        this.clearBackground();
        this.setState({
            deleteProfile: !this.state.deleteProfile,
            profileErrorMsg: null
        });
    };

    setProfileErrorMessage = (message) => {
        this.setState({ profileErrorMsg: message });
    };

    deleteProfile = () => {
        this.props.paymentSource.deletePaymentSource(
            () => {
                this.props.profile.deleteCustomerProfile(
                    () => {
                        this.clearSession();
                    },
                    (error) => {
                        this.setProfileErrorMessage(error);
                    }
                );
            }
        );
    };

    /*
     *
     * Input field methods
     *
     */

    onClickInput = (event) => {
        const cursorIndex = event.target.selectionStart;
        const copiedState = {...this.state.formData};
        copiedState['cursor'] = cursorIndex;
        this.setState({
            formData: copiedState
        })
    };

    onKeyPress = (event) => {
        // prevents non-numeric keys from being entered.
        if (event.target.name === 'cardNumber') {
            if (event.which < 48 || event.which > 57) {
                event.preventDefault();
            }
        }
        this.lastKey = event.key;
        const cursorIndex = event.target.selectionStart;
        const copiedState = {...this.state.formData};
        copiedState['cursor'] = cursorIndex;
        this.setState({
            formData: copiedState
        })
    };

    hasStates = () => {
        return this.props.states.length > 1;
    }

    render() {
        const modal = this.getModal();

        const fields = this.props.settings["elements"].map((field,i) => {
            if (typeof(this.field[field.field]) === 'undefined') {
                this.field[field.field] = {};
            }
            return this.createFormElement(field, i);
        });

        const sessionAdditionalData = this.props.session.getAdditionalData();

        // Custom button settings passed inside the session
        const submitButtonStates = sessionAdditionalData['submitButtonStates'];
        let svgURL;
        for (let i = 0; i < submitButtonStates.length; i++) {
            if (submitButtonStates[i].state === "active" && typeof(submitButtonStates[i].image) !== 'undefined') {
                svgURL = submitButtonStates[i].image.src;
                break;
            }
        }

        let amountText = "";
        let payableBtn = false;
        if ('payable' in this.props.currentSection) {
            if (this.props.currentSection.payable === "true") {
                payableBtn = true;
                amountText = "Pay "     // create the amount text
                    + (typeof(this.props.settings.modals.prefix) !== 'undefined' ? this.props.settings.modals.prefix : "$")
                    + this.state.formData.totalAmount;
            }
        }

        let deleteProfileLink;
        if (this.props.currentSection.path === '/managePaymentInformation') {
            if (this.props.profile.getStatus() === 'DELETED' || !this.props.profile || this.props.currentSection.deleteInfoLink === "false") {
                deleteProfileLink = null;
            } else {
                deleteProfileLink = <a onClick={this.onDeleteProfileInformationHandler} className="deleteProfileLinkBtn" href="#">Delete Information</a>;
            }
        }

        let deleteProfileModal;
        const submitStyle = { color: 'white', display: 'inline-block', margin: '10px' };
        if (this.state.deleteProfile) {
            if (this.state.profileErrorMsg !== null) {
                let additionalModalContent = (
                    <div>
                        <p>Unable to Delete Customer Profile</p>
                        <p>Status: {this.state.profileErrorMsg.content.data.status}</p>
                        <p>Message: {this.state.profileErrorMsg.content.data.message}</p>
                    </div>
                );
                deleteProfileModal = (
                    <PNPModal
                        title="Are you sure you want to delete your profile information?"
                        message="You will be redirected after your profile has been deleted."
                        visible={this.state.deleteProfile}
                        additionalModalContent={additionalModalContent}
                    >
                      <Button
                          text="CANCEL"
                          styling={submitStyle}
                          click={this.clearDeleteModalHandler}
                      />
                      <AnimatedButton
                          svgUrl={svgURL}
                          text="RETRY"
                          styling={submitStyle}
                          click={this.deleteProfile}
                      />
                    </PNPModal>
                )
            } else {
                deleteProfileModal = (
                    <PNPModal
                        title="Are you sure you want to delete your profile information?"
                        message="You will be redirected after your profile has been deleted."
                        visible={this.state.deleteProfile}
                    >
                      <Button
                          text="NO"
                          styling={submitStyle}
                          click={this.clearDeleteModalHandler}
                      />
                      <AnimatedButton
                          svgUrl={svgURL}
                          text="YES"
                          styling={submitStyle}
                          click={this.deleteProfile}
                      />
                    </PNPModal>
                )
            }
        }

        return (
            <div id="makePaymentSection">
                <div className="modalContainer">
                    {modal}
                </div>
                {deleteProfileModal}
                <div className="sectionContent">
                    {fields}
                </div>
                <PNPButton payableButton={payableBtn}
                           amountText={amountText}
                           disabled={this.state.formData.disabled}
                           handleSubmit={this.validateSubmit}
                           states={submitButtonStates} />
                {deleteProfileLink}
            </div>
        )
    }
}

export default withRouter(MakePayment);
