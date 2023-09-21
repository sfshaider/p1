import React, { Component, createRef } from "react";
import ReactDOM from "react-dom";

class CreditCardInput extends Component {

    constructor(props) {
        super(props);

        this.card = createRef();
        this.value = this.props.value;
    }

    componentWillReceiveProps(nextProps) {
        if (nextProps.value !== this.props.value) {
            this.value = nextProps.value;
        }
    }

    componentDidUpdate(prevProps, prevState) {
        let node = this.card.current;
        if (prevProps.value !== this.props.value) {
            if (prevProps.value.length > this.props.value.length) {
                node.selectionStart = this.props.cursor;
                node.selectionEnd = this.props.cursor;
                if (this.props.cursor % 5 === 0) {
                    node.selectionStart = this.props.cursor - 1;
                    node.selectionEnd = this.props.cursor - 1;
                }
            } else {
                node.selectionStart = this.props.cursor;
                node.selectionEnd = this.props.cursor;
                if (this.props.cursor % 5 === 0) {
                    node.selectionStart = this.props.cursor + 1;
                    node.selectionEnd = this.props.cursor + 1;
                }
            }
        }
    }

    onChangeInput = (event) => {
        const value = event.target.value;
        if (value.match(/\d{4}\s\d{2}(\d?)\*(\d?)\*(\d?)\s(\d?)\*(\d?)\*(\d?)\*(\d?)\*(\d?)\s\d*/g)) {
            let char = value.split("").filter((char, idx) => char !== this.value[idx]);
            if (char[0]) {
                this.card.current.value = char[0];
            }
            event.persist();
            this.props.change(event);
        }  else {
            this.props.change(event);
        }
    }

    render() {
        return (
            <div>
                <label className="col-2">Card Number: </label>
                <input
                    ref={this.card}
                    type="text"
                    className={`col-6 PNPInputField fieldName-${this.props.fieldName}`}
                    value={this.value}
                    placeholder="Card Number"
                    name={this.props.fieldName}
                    onChange={this.onChangeInput}
                    onClick={this.props.onClickInput}
                    onKeyPress={this.props.onKeyPress}
                    onBlur={this.props.onBlur}
                    autoComplete="off"
                />
            </div>
        )
    }
}

class PhoneNumberInput extends React.Component {
    constructor(props) {
        super(props);

        this.phone = createRef();
    }

    componentDidUpdate(prevProps, prevState) {
        let node = this.phone.current;
        if (prevProps.value.length > this.props.value.length) {
            node.selectionStart = this.props.cursor;
            node.selectionEnd = this.props.cursor;
        }
        if (prevProps.value.length < this.props.value.length) {
            if (this.props.value.length < 10 && this.props.value.length >= 9) {
                node.selectionStart = this.props.cursor + 6;
                node.selectionEnd = this.props.cursor + 6;
            }
            else if (this.props.value.length < 16 && this.props.value.length >= 15) {
                node.selectionStart = this.props.cursor + 4;
                node.selectionEnd = this.props.cursor + 4;
            } else if (this.props.value.length > 10 && this.props.value.length <= 11) {
                node.selectionStart = this.props.cursor;
                node.selectionEnd = this.props.cursor;
            } else if (this.props.value.length >= 16) {
                node.selectionStart = this.props.cursor;
                node.selectionEnd = this.props.cursor;
            }
        }
    }

    render() {
        return (
            <input
                ref={this.phone}
                type={this.props.type}
                className={`col-6 PNPInputField fieldName-${this.props.fieldName}`}
                value={this.props.value}
                onChange={this.props.change}
                onClick={this.props.onClickInput}
                onKeyPress={this.props.onKeyPress}
                onBlur={this.props.onBlur}
                name={this.props.fieldName}
                placeholder={this.props.placeholder}
                autoComplete="off"
            />
        )
    }
}

class TextInput extends Component {


    onKeyPressHandler = event => {
        event.persist();
        if (event.target.name === 'amount') {
            if (event.which < 43 || event.which > 58 || event.which === 45 || event.which === 43) {
                event.preventDefault();
            }
        }
        this.props.onKeyPress(event);
    }

    render() {
        return (
            <input
                className={`col-6 PNPInputField fieldName-${this.props.fieldName}`}
                type={this.props.type}
                value={this.props.value}
                placeholder={this.props.placeholder}
                name={this.props.fieldName}
                onKeyPress={this.onKeyPressHandler}
                onChange={this.props.onChange}
                onBlur={this.props.onBlur}
                autoComplete="off"
            />
        )
    }
}

/*
    How to create:
    <HiddenInput
        onChange={}
        onBlur={}
        fieldName={}
        value={}
        placeholder={}
    />
 */
class HiddenInput extends React.Component {
    render() {
        return (
            <input
                value={this.props.value}
                type="hidden"
                onChange={this.props.onChange}
                onBlur={this.props.onBlur}
                className={`col-6 PNPInputField fieldName-${this.props.fieldName}`}
                name={this.props.fieldName}
                placeholder={this.props.placeholder}
                autoComplete="off"
            />
        )
    }
}

export { CreditCardInput, TextInput, HiddenInput, PhoneNumberInput }