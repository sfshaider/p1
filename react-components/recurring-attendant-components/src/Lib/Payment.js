import React, { Component } from 'react';
import FormElement from "./FormElement";
import { CreditCardInput, TextInput } from "./Objects/Input";
import PNPRadio from "../PNPComponents/PNPRadio/PNPRadio";

const settings = {
    routingNumber: {
        fieldName: 'routingNumber',
        label: 'Routing Number',
        dataType: 'routingNumber'
    },
    accountNumber: {
        fieldName: 'accountNumber',
        label: 'Account Number'
    },
    accountType: {
        fieldName: 'accountType',
        label: 'Account Type',
        type: 'selector',
        dataType: 'accountType'
    },
    cardNumber: {
        fieldName: 'cardNumber',
        label: 'Card Number',
        dataType: 'cardNumber'
    },
    token: {
        fieldName: 'token',
        label: 'token',
        optional: "true"
    },
    expirationMonth: {
        fieldName: 'expirationMonth',
        type: 'selector',
        dataType: 'cardExpirationDate'
    },
    expirationYear: {
        fieldName: 'expirationYear',
        type: 'selector',
        dataType: 'cardExpirationDate'
    },
    cvv: {
        fieldName: 'cvv',
        label: 'CVV',
        optionalLabel: '(security code)',
        optional: "true"
    }
};

const Payment = (props) => {
    const handlePaymentTypeChange = (event) => {
        if (typeof(props.paymentTypeChangeHandler) === "function") {
            props.paymentTypeChangeHandler(event.target.value);
        } else {
            window.console.warn("props.paymentTypeChangeHandler is not defined for Payment component.");
        }
    };

    const handleFormDataChange = (event) => {
        if (typeof(props.change) === "function") {
            console.log('change');
            props.change(event);
        } else {
            window.console.warn("props.change is not defined for Payment component.");
        }
    };

    const handleBlur = (event) => {
        if (typeof(props.blur) === "function") {
            console.log('blur');
            props.blur(event);
        } else {
            window.console.warn("props.blur is not defined for Payment component.");
        }
    };

    const achSection = () => {
        const routingNumber = props.value.routingNumber;
        const accountNumber = props.value.accountNumber;
        const accountType = props.value.accountType || 'checking';
        const token = props.value.token;
        const accountTypes = [ 'CHECKING', 'SAVINGS' ];

        return (
            <div className={"achInfo"}>
                <ul>
                    <li>
                        <FormElement change={handleFormDataChange}
                                     visible={true}
                                     fieldName={settings.routingNumber.fieldName}
                                     label={settings.routingNumber.label}
                                     onKeyPress={props.onKeyPress}
                                     fieldValue={routingNumber}
                                     blur={handleBlur}
                        />
                    </li>
                    <li>
                        <FormElement change={handleFormDataChange}
                                     visible={true}
                                     fieldName={settings.accountNumber.fieldName}
                                     label={settings.accountNumber.label}
                                     onKeyPress={props.onKeyPress}
                                     fieldValue={accountNumber}
                                     blur={handleBlur}
                        />
                    </li>
                    <li>
                        <FormElement change={handleFormDataChange}
                                     visible={true}
                                     type={settings.accountType.type}
                                     fieldName={settings.accountType.fieldName}
                                     label={settings.accountType.label}
                                     onKeyPress={props.onKeyPress}
                                     dataType={settings.accountType.dataType}
                                     fieldValue={accountType.toUpperCase()}
                                     dataSource={accountTypes}
                                     fieldStyle={"formField"}
                                     blur={handleBlur}
                        />
                    </li>

                    <FormElement change={handleFormDataChange}
                                 visible={false}
                                 fieldName={settings.token.fieldName}
                                 label={settings.token.label}
                                 dataType={settings.token.dataType}
                                 fieldValue={token}
                                 blur={handleBlur}
                    />
                </ul>
            </div>
        );
    };

    const yearFormatYY = (offset,year) => {
        return (offset + year).toString().substr(2,2);
    };

    const yearFormatYYYY = (offset,year) => {
        return offset + year;
    };

    const cardSection = () => {
        const year = new Date().getFullYear();
        const cardNumber = props.value.cardNumber;
        const token = props.value.token;
        const months = ['01','02','03','04','05','06','07','08','09','10','11','12'];

        let yearFunc = undefined;
        if (props.yearFormat === 'YYYY') {
            yearFunc = yearFormatYYYY;
        } else {
            yearFunc = yearFormatYY; // default format
        }

        const years = Array.from(Array(15)).map((elem,i) => {
            return {displayValue: yearFunc(i,year), value: (i + year - 2000)};
        });
        const cvv = props.value.cvv;

        // cvv may be disabled.
        const cvvSpan = (props.cvvHidden === "true" ? null : (
            <span className={"cvv"}>
            <label style={{"marginTop": "10px"}}>CVV Code:</label>
                <TextInput
                    cursor={props.cursor}
                    fieldName={settings.cvv.fieldName}
                    onKeyPress={props.onKeyPress}
                    onClickInput={props.onClickInput}
                    label={settings.cvv.label}
                    value={cvv}
                    onChange={handleFormDataChange}
                    onBlur={handleBlur}
                    type="text"
                />
            </span>
        ));

        return (
            <div className={"cardInfo"}>
                <ul>
                    <li>
                        <CreditCardInput
                            cursor={props.cursor}
                            change={props.change}
                            onKeyPress={props.onKeyPress}
                            onClickInput={props.onClickInput}
                            value={cardNumber}
                            fieldName={settings.cardNumber.fieldName}
                            onBlur={handleBlur}
                            placeholder="Credit Card Number"
                        />
                        <FormElement change={handleFormDataChange}
                                     visible={false}
                                     fieldName={settings.token.fieldName}
                                     label={settings.token.label}
                                     dataType={settings.token.dataType}
                                     fieldValue={token}
                                     blur={handleBlur}
                        />
                    </li>
                    <li>
                        <div className={"expiration-and-cvv"}>
                            <span className={"expiration"}>
                                <label>Expiration Date:</label>
                                <span className={"expirationFields"}>
                                    <FormElement
                                        fieldName={settings.expirationMonth.fieldName}
                                        type={settings.expirationMonth.type}
                                        fieldValue={props.value.expirationMonth}
                                        change={handleFormDataChange}
                                        dataSource={months}
                                    />
                                    <FormElement
                                        fieldName={settings.expirationYear.fieldName}
                                        type={settings.expirationYear.type}
                                        fieldValue={props.value.expirationYear}
                                        change={handleFormDataChange}
                                        dataSource={years}
                                    />
                                </span>
                            </span>
                            {cvvSpan}
                        </div>
                    </li>
                </ul>
            </div>
        );
    };

    const data = {
        'card': cardSection(),
        'ach': achSection()
    };

    let type = props.value.paymentType;
    if (!type) {
        type = 'card';
    }

    const radios = [
        {
            'name': 'paymentType',
            'value': 'card',
            'text': 'CARD',
            'checked': type === 'card',
            'onChange': handlePaymentTypeChange
        }, {
            'name': 'paymentType',
            'value': 'ach',
            'text': 'ACH',
            'checked': type === 'ach',
            'onChange': handlePaymentTypeChange
    }];

    let radioContent;
    if (typeof(props.paymentTypeOptions) !== 'undefined') {
        if (props.paymentTypeOptions.length > 0 && props.paymentTypeOptions[0] === 'all') {
            radioContent = (
                <div>
                    <label>Payment Type:</label>
                    <PNPRadio radio={radios} />
                </div>
            );
        }
    }

    return (
        <div>
            {radioContent}
            <div className='paymentInformation'>
                {data[(props.value.paymentType === 'ach' ? 'ach' : 'card')]}
            </div>
        </div>

    );
};

export default Payment;

const getPaymentFormDataSettings = (field) => {
    let dataType = '';
    let optional = '';

    if (typeof settings[field] !== 'undefined') {
        dataType = settings[field].dataType;
        optional = settings[field].optional;
    }

    return {dataType: dataType, optional: optional};
};

export {getPaymentFormDataSettings}
