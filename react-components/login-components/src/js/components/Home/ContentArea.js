import React, { Component } from 'react';
import LoginForm from '../Login/LoginForm';
import classes from './ContentArea.css';

export default class ContentArea extends Component {

    constructor(props) {
        super(props);

        this.state = {
           isBackgroundVisible: props.isBackgroundVisible
        };
    }

    changeBackgroundImage() {
        if (this.state.isBackgroundVisible === false) {
            document.getElementById(classes['content-area']).style.backgroundImage = 'url(\'\')';
        }
    }

    componentDidMount() {
        this.changeBackgroundImage();
    }

    render() {
        return (
            <div id={classes["content-area"]} className={classes.ContentArea}>
                <LoginForm loginType={this.props.loginType}/>
            </div>
        );
    }

};

