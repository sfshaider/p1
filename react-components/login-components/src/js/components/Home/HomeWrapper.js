import React, { Component } from 'react';
import Home from './Home';

export default class HomeWrapper extends Component {

    constructor(props) {
        super(props);

        this.state = {
            loginType: "merchant"
        };

        this.handleLoginTypeUpdate.bind(this);
    }

    handleLoginTypeUpdate = (loginType) => {
        this.setState({
            loginType: loginType
        })
    }

    render() {
        return (
            <div>
                <Home update={this.handleLoginTypeUpdate} loginType={this.state.loginType}/>
            </div>
        );
    }
}
