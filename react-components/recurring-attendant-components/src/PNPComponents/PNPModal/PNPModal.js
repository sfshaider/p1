import React from 'react';

class PNPModalButton {
    buttonText = '';
    buttonName = '';
    buttonClickCallback = () => {};

    constructor(name,text,callback) {
        this.setName(name);
        this.setText(text);
        this.setClickCallback(callback);
    }

    setText = (text) => {
        this.buttonText = text;
    };

    getText = () => {
        return this.buttonText;
    };

    setName = (name) => {
        this.buttonName = name;
    };

    getName = () => {
        return this.buttonName;
    };

    setClickCallback = (callback) => {
        this.buttonClickCallback = callback
    };

    getClickCallback = (callback) => {
        return this.buttonClickCallback;
    };
}

class PNPModalButtons {
    buttonArray = [];
    self = this;

    addButton = (name,text,callback) => {
        this.buttonArray.push(new PNPModalButton(name,text,callback));
    };

    getButtons = () => {
        return this.buttonArray;
    };

    getButton = (index) => {
        if (index < this.buttonArray.length) {
            return this.buttonArray[index];
        } else {
            return null;
        }
    }
}

const PNPModal = (props) => {

    let message = (props.message ? (
        <div className="message">{props.message}</div>
    ) : null);

    return props.visible ? (
        <div id={props.id} className="modal">
            <div><p className="modalTitle">{props.title}</p></div>
            {message}
            <div className="additionalModalContent">{props.additionalModalContent}</div>
            <div className="modalButtonContainer">
                {props.children}
            </div>
        </div>
    ) : null;
};

export default PNPModal;
export {PNPModalButton,PNPModalButtons}