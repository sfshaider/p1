import React from 'react'
import Payment from "./Payment";
import getTools from '../Lib/Objects/Tools';
import {FormGroup, Label} from 'reactstrap';
import { TextInput, PhoneNumberInput, HiddenInput } from './Objects/Input';


const buildTextInput = (props,fieldClass) => {
    let fieldValue = formatFieldValue(props);

    let labelClassName = "col-2 "; //"col-2 " ;
    let optionalLabel = null;

    let hiddenStyle = ((typeof(props.visible) === "undefined" || props.visible === true) ? {} : {display: "none"});

    if (props.optionalLabel) {
        labelClassName += "two-line-label";
        optionalLabel = <div className={"optional"}>{props.optionalLabel}</div>
    }

    let classNameValue = `formField formField-${props.fieldName}-container`;

    let input;
    if (props.fieldName === "phoneNumber") {
        input = (
            <PhoneNumberInput
                change={props.change}
                onBlur={props.blur}
                onKeyPress={props.onKeyPress}
                onClickInput={props.onClickInput}
                fieldName={props.fieldName}
                value={fieldValue}
                placeholder={props.label}
                cursor={props.cursor}
                type={props.type}
            />
        )
    } else {
        input = (
            <TextInput
                onChange={props.change}
                onBlur={props.blur}
                onKeyPress={props.onKeyPress}
                onClickInput={props.onClickInput}
                fieldName={props.fieldName}
                value={fieldValue}
                placeholder={props.label}
                cursor={props.cursor}
                type={props.type}
            />
        )
    }

    return (
        <div className={classNameValue} style={hiddenStyle}>
            <label className={labelClassName}>
                {props.label}: {optionalLabel}
            </label>
            {input}
        </div>
    );
};

const buildReadOnly = (props) => {
    let valueClassName = "readonly-input ";

    if (props.bold) {
        valueClassName += "bold "
    }

    let value = formatFieldValue(props);

    if (value === "--") {
        valueClassName += "empty ";
    }

    return (
        <div className={"readonly"}>
                <span className={"label-span"}>
                    <label className={""}>{props.label}: </label>
                </span>
            <span className={valueClassName + " prefix"}>{props.fieldPrefix}</span><span
            className={valueClassName + " value"}>{value}</span>
            <input type={"hidden"} name={props.fieldName} value={props.fieldValue} readOnly={true}/>
        </div>
    );
};


function buildSelector(props,fieldClass) {
    let options = undefined;
    options = props.dataSource.sort((a, b) => {
        if (typeof(a) === 'object' && typeof(b) === 'object') {
            return ((a.displayValue > b.displayValue) ? 1 : ((b.displayValue > a.displayValue) ? -1 : 0));
        } else {
            return a - b;
        }
    });

    let label = null;
    if (typeof(props.label) !== "undefined") {
        label = <label className='CardXLabel'>{props.label}</label>;
    }

    return (
        <div className={`select-carat formField-${props.fieldName}-container ${props.fieldStyle}`}>
            {label}
            <select
                className={`select ${fieldClass}`}
                name={props.fieldName}
                value={props.fieldValue}
                onChange={props.change}
                onBlur={props.blur}
            >
                {options.map((data, idx) => {
                    let selected = ((props.selected === data.value) ? "selected" : "");
                    let disabled = (data.value ? false : true);
                    if (typeof(data) === 'object') {
                        return <option key={idx} value={data.value} disabled={disabled}>{data.displayValue}</option>
                    } else {
                        return <option key={idx} value={data}>{data}</option>
                    }
                })}
            </select>
        </div>
    )
}

const buildCheckBox = (props) => {
    let selectedStyle = props.checked ? 'selectedCheckbox' : null;
    return (
        <FormGroup check inline>
            <Label>
                <input id="hidden-checkbox" type="checkbox" checked={props.checked} onChange={props.change}
                       name={props.fieldName}/>
                <span className={selectedStyle} id="custom-checkbox"></span>
                <label className="adjustLeft">{props.label}</label>
            </Label>
        </FormGroup>
    );
};

const formatFieldValue = (props) => {
    let fieldValue = props.fieldValue;
    if (props.dataType === "phoneNumber") {
        fieldValue = getTools().formatPhoneNumber(fieldValue);
    }

    return fieldValue;
};

const calculatedValue = (props) => {
    const data = props.data;
    const formula = props.formula;
    const valueMap = props.valueMap;
    const rpnResult = rpn(formula,data);
    const value = valueMap[rpnResult];

    let valueClassName = "";

    if (props.bold) {
        valueClassName += "bold "
    }

    if (value) {
        return (<span className={valueClassName}>{value}</span>);
    } else {
        return null;
    }
};

const rpn = (formula,data) => {
    // preprocess formula, replacing variables with values from data
    const processedFormula = [];
    for (const element in formula) {
        if (typeof(formula[element]) === 'string' && formula[element].indexOf(':') === 0) {
            const dataKey = formula[element].substr(1);
            processedFormula.push(data[dataKey] || '');
        } else {
            processedFormula.push(formula[element]);
        }
    }

    return rpnRec(processedFormula);
};

const rpnRec = (formula) => {
    const stack = [];
    if (!formula) {
        return;
    } else if (formula.length === 1) {
        return formula.shift();
    } else if (formula.length >= 3) {
        while (formula.length >= 4 && rpnOperate({ 'op': formula[2] }) === '__NOT_OP__') {
            stack.push(formula.shift());
        }
        const arg1 = formula.shift();
        const arg2 = formula.shift();
        const op = formula.shift();
        const retval = rpnOperate({ 'arg1': arg1, 'arg2': arg2, 'op': op });
        formula.unshift(retval);
        let stackItem = stack.pop();
        while (stackItem  !== undefined) {
            formula.unshift(stackItem);
            stackItem = stack.pop();
        }
        return rpnRec(formula);
    }
}

const rpnOperate = (args) => {
    const arg1 = args.arg1;
    const arg2 = args.arg2;
    const op   = args.op;

    const argsDefined = (typeof(arg1) !== 'undefined' && typeof(arg2) !== 'undefined');

    if (op === "_EQUALS_") {
        return (arg1 === arg2);
    } else if (op === '_CONTAINS_') {
        if (argsDefined) {
            return (arg1.indexOf(arg2) >= 0);
        }
    } else if (op === '+') {
        if (argsDefined) {
            return (arg1 + arg2);
        }
    } else if (op === '_AND_') {
        return (arg1 && arg2);
    } else {
        return "__NOT_OP__";
    }
};


const FormElement = (props) => {
    let optionalLabel = null;

    if (props.optional) {
        let optionalText = props.optionalText || "(optional)";
        optionalLabel = <label className={"optional"}>{optionalText}</label>
    }

    let index = props.index;
    if (typeof(index) === undefined) {
        index = "";
    }

    let output = null;

    const fieldID = `fieldName-${props.fieldName}`;

    if (props.type === "input" || typeof(props.type) === "undefined") {
        output = buildTextInput(props,fieldID);
    } else if (props.type === "readOnly" || props.type === "dynamic") {
        output = buildReadOnly(props);
    } else if (props.type === "disclaimer") {
        let lines = props.fieldValueOptions.map((line) => {
            return (<span key={line}>{line}</span>)
        });
        output = (
            <div className="disclaimer">{lines}</div>
        );
    } else if (props.type === "hr") {
        output = <hr/>;
    } else if (props.type === "blanks") {
        output = null;
    } else if (props.type === "payment") {
        output = (
            <div className={`formField`}>
                <Payment
                    paymentTypeChangeHandler={props.paymentTypeChangeHandler}
                    paymentTypeOptions={props.paymentTypeOptions}
                    onKeyPress={props.onKeyPress}
                    onClickInput={props.onClickInput}
                    cursor={props.cursor}
                    value={props.fieldValue}
                    change={props.change}
                    blur={props.blur}
                    cvvHidden={props.cvvHidden}
                    type={props.type}
                />
            </div>
        );
    } else if (props.type === "selector") {
        output = buildSelector(props,fieldID);
    } else if (props.type === "checkbox") {
        output = buildCheckBox(props,fieldID);
    } else if (props.type === "text") {
        output = buildTextInput(props, fieldID);
    } else if (props.type === "calculated") {
        output = calculatedValue(props, fieldID);
    } else if (props.type === "hidden") {
        output = (
            <HiddenInput
                onChange={props.change}
                onBlur={props.blur}
                fieldName={props.fieldName}
                value={props.fieldValue}
                placeholder={props.label}
            />
        )
    }

    return output;
};

export default FormElement;