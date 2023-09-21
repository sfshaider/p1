import React, {Component} from "react";
import {withRouter} from "react-router-dom";

class External extends Component {
    render() {
        const target = typeof(this.props.settings.target) === 'undefined' ? '_blank' : this.props.settings.target;
        window.open(this.props.settings.externalPath, target);
        return (
            <div>If you have not been redirected, click <a href={this.props.settings.externalPath} target={target}>here</a></div>
        )
    }
}

export default withRouter(External);
