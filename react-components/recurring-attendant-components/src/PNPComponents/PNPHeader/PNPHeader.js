import React from 'react';
import PropTypes from 'prop-types';
import '../../Themes/CardX/CardX.css';


class PNPHeader extends React.Component {
    constructor(props) {
        super(props);
        this.state = {
            mobileToggle: false
        };
    };

    componentWillReceiveProps(nextProps) {
        if (nextProps.toggled !== this.props.toggled) {
            this.setState({ mobileToggle: nextProps.toggled });
        }
    }

    mobileNavToggleHandler = () => {
        this.setState(prevState => ({mobileToggle: !prevState.mobileToggle}));
        this.props.mobileNavToggleHandler();
    };



    setClosedState = () => {
        this.setState({mobileToggle: false});
    }

    render() {
        let mobileToggleClassName = "mobiletoggle ";

        if (this.state.mobileToggle) {
            mobileToggleClassName += "open";
            document.getElementById('root').classList.add('noScroll');
        } else {
            document.getElementById('root').classList.remove('noScroll');
        }

        let hamburgerContent = null;

        if (this.props.hamburgerVisible) {
            hamburgerContent = (
                <a className={mobileToggleClassName} onClick={this.mobileNavToggleHandler}>
                    <span className="n">n</span>
                    <span className="a">a</span>
                    <span className="v">v</span>
                </a>
            )
        }

        return (
            <div className="header-bar">
                <div className="header-text">{this.props.title}</div>
                <div className="header-logout">
                    <a id="logout" href="/recurring/logout.cgi">Log Out</a>
                </div>
                {hamburgerContent}
            </div>
        )
    }
}

PNPHeader.propTypes = {
    title: PropTypes.string.isRequired
};

export default PNPHeader;