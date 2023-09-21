import React,  { Component } from 'react';
import { connect } from 'react-redux';
import Nav from './Nav';
import InfoBar from './InfoBar';
import ContentArea from './ContentArea';
import ErrorDialog from '../ErrorDialog/ErrorDialog';
import classes from './Home.css';
import { updateWindowDimension } from '../../actions/windowDimActions';

class Home extends Component {

    state = {
        isErrorMsgVisible: false,
        url: window.location.href
    };

    componentDidMount() {
        const { updateWindowDims } = this.props;
        window.addEventListener("resize", updateWindowDims);
    }

    componentWillUnmount() {
        const { updateWindowDims } = this.props;
        window.removeEventListener("resize", updateWindowDims);
    }

    handleErrorMsg = () => {
        this.setState({
            isErrorMsgVisible: true
        })
    };

    render() {
        const urlPattern = new RegExp(/\/ADMIN/);
        const privPattern = new RegExp(/\/PRIV/);
        let errMsg = false;
        if (urlPattern.test(this.state.url)) {
            errMsg = true;
        }
        if (privPattern.test(this.state.url)) {
            errMsg = true;
        }
        const domainPattern = new RegExp(/plugnpay.com/);

        const errorContent =
            <span>
                <p>Invalid Username or Password.</p>
                <p>Your login will be locked after 5 failed attempts.</p>
            </span>

        if (domainPattern.test(this.state.url)) {
            return (
                <div className={classes.Home}>
                    <InfoBar/>
                    <Nav  loginType={this.props.loginType} update={this.props.update}/>
                    {errMsg ? <ErrorDialog showOrHideDialog={this.handleErrorMsg.bind(this)} isVisible={this.state.isErrorMsgVisible} content={errorContent}/> : null}
                    <ContentArea loginType={this.props.loginType}/>
                </div>
            );
        } else {
            return (
                <div className={classes.Home}>
                    <img style={{marginTop: '50px'}} src="/adminlogos/pnp_admin_logo.gif" />
                    {errMsg ? <ErrorDialog showOrHideDialog={this.handleErrorMsg.bind(this)} isVisible={this.state.isErrorMsgVisible} content={errorContent}/> : null}
                    <ContentArea isBackgroundVisible={false} loginType={this.props.loginType}/>
                </div>
            );
        }
    }
}

const mapStateToProps = null;
const mapDispatchToProps = dispatch => ({
    updateWindowDims: () => dispatch(updateWindowDimension())
})

export default connect(mapStateToProps, mapDispatchToProps)(Home);