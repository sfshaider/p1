import React, { Component } from 'react';
import Loader from './Loader';
import classes from './LoginForm.css';

class LoginForm extends Component {
    constructor(props) {
        super(props);

        this.state = {
            // Username, Password
            username: '',
            password: '',
            loaderVisibility: 'hidden'
        }
    }

    // call validateInput
    // set username and password values.
    handleUsernameInputChange = (event) => {
        this.setState({
            username: event.target.value
        });
    };

    handlePasswordInputChange = (event) => {
        this.setState({
            password: event.target.value
        })
    };

    // validate input values here
    validateInput = (event) => {
        if(this.state.username === '' || this.state.password === '') {
            alert('Please enter a username and password');
            return '';
        }
    };

    // handles the button being clicked
    onButtonClickedHandler = (event) => {
        if (this.validateInput() !== '') {
            this.setState({
                loaderVisibility: 'visible'
            });
            this.dimBackgroundOnClickHandler();
        }
        else {
            event.preventDefault();
        }
    };

    dimBackgroundOnClickHandler = () => {
        document.querySelector('form').classList.add('LoginForm-transparent');
    };

    resetPasswordHandler = () => {
        window.location.href = `/lostpass.cgi?loginType=${this.props.loginType}`;
    }

    gatewayStatusHandler = () => {
        window.location.href = 'http://www.gatewaystatus.com';
    }



    render() {
        let action = '/ADMIN';
	let value = '';
        let lowerPrivRegExp = new RegExp('^\/private\/?');
        let upperPrivRegExp = new RegExp('^\/PRIV\/?');
	let salesTeamRegex = new RegExp('^\/salesteam\/?');
        let pathname = window.location.pathname;
        if (lowerPrivRegExp.test(pathname) || upperPrivRegExp.test(pathname)) {
            action = '/PRIV';
        }
        if (action === '/PRIV') {
            value = '/private/';
        }
        if (action === '/ADMIN') {
            value = '/admin/login.cgi';
        }
	if (salesTeamRegex.test(pathname) && action === '/ADMIN') {
	    value = '/salesteam';
        }
        let input = <input type="hidden" name="destination" value={value} />;
        return (
            <div className={classes.LoginForm}>
                <form action={action} name="loginform" method="POST">
                    <span><input type="text" name="credential_0" placeholder="Username" value={this.state.username} autoComplete="off" onChange={this.handleUsernameInputChange}/></span> <br />
                    <span><input type="password" name="credential_1" placeholder="Password" value={this.state.password} autoComplete="off" onChange={this.handlePasswordInputChange}/></span> <br />
                    <button onClick={this.onButtonClickedHandler}>Login</button> <br />
                    {input}
                 </form>
                <div className={classes.LoginFormFooter}>
                    <button onClick={this.resetPasswordHandler}>Reset Password</button>
                    <button onClick={this.gatewayStatusHandler}>Gateway Status</button>
                    <span className={classes.PasswordWarning}>Reminder: Passwords expire and must be changed within 90 days.</span>
                </div>
                <Loader visibility={this.state.loaderVisibility}/>
            </div>
        );
    }
}

export default LoginForm;
