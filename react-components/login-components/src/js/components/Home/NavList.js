import React, { Component } from 'react';
import classes from './NavList.css';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faSearch, faBars } from '@fortawesome/free-solid-svg-icons';
import SearchBar from './SearchBar';
import { connect } from 'react-redux';
import WINDOW_DIMENSIONS from '../../constants/windowDims';
import NAV_LINKS from '../../constants/navLinks';

class NavList extends Component {

    constructor(props) {
        super(props);
        this.state = {
            displaySearch: false,
        };
        this.hideSubMenu = this.hideSubMenu.bind(this);
        this.hideSubMenuFromLeft.bind(this);
        this.handleDisplaySearch = this.handleDisplaySearch.bind(this);
    }

    setVisitedLink = (id) => {
        const visitedLinks = document.getElementsByClassName(classes.visited);
        if (id === 'merchantLogin') {
            this.props.update('merchant');
        }
        if (id === 'resellerLogin') {
            this.props.update('reseller');
        }
        if (visitedLinks.length !== 0) {
            for(var i = 0; i < visitedLinks.length; i++) {
                visitedLinks[i].classList.remove(classes.visited);
            }
        }
        document.getElementById(id).classList.add(classes.visited);
    }

    hidePreviousMenu = (id) => {
        const prevMenus = {
            'msolutions': 'partnerReseller',
            'partnerReseller': 'msolutions',
            'developers': 'partnerReseller',
            'aboutus': 'contactus',
            'contactus': 'aboutus',
            'webXpressProcessing': 'zccMenu',
            'achECheck': 'zccMenu',
            'memberManagement': 'posMenu',
            'fraudtrak': 'posMenu',
            'billingPresentment': 'mcMenu',
        };

        const subMenus = {
            zccMenu: true,
            posMenu: true,
            mcMenu: true,
        };

        if (!prevMenus[id]) return;

        if (subMenus[prevMenus[id]]) {
            document.getElementById(classes[prevMenus[id]]).classList.remove(classes.active);
        } else {
            document.getElementById(prevMenus[id]).classList.remove(classes.active);
        }
    };

    hideAllMenus = () => {
       const activeMenus = document.getElementsByClassName(classes.active);
       for(var i = 0; i < activeMenus.length; i++) {
           activeMenus[i].classList.remove(classes.active);
       }
    };

    hideSubMenu = (id) => {
        document.getElementById(classes[id]).classList.remove(classes.active);
    };

    showMenu = (id) => {
        this.hidePreviousMenu(id);
        const selectedMenu = document.getElementById(id);
        selectedMenu.classList.add(classes.active);
    };

    hideMenu = (id) => {
        const selectedMenu = document.getElementById(id);
        selectedMenu.classList.remove(classes.active);
    };

    hideSubMenuFromLeft = (event, id) => {
        let eles = document.getElementsByClassName(classes.subMenu);
        let ele = null;
        for (let i = 0; i < eles.length; i++) {
            if (eles[i].offsetParent) {
                ele = eles[i];
                break;
            }
        }

        let rect = ele.getBoundingClientRect();
        let scrollLeft = window.pageXOffset || ele.scrollLeft;
        let oldX = rect.left + scrollLeft - 2;
        if (event.pageX < oldX) {
            this.hideSubMenu(id);
        }
    };

    handleDisplaySearch = (e) => {
        e.preventDefault();
        this.setState({ displaySearch: !this.state.displaySearch });
    };

    render() {
        const { displaySearch } = this.state;
        const { dimensions: { isTablet }, handleSetMobileNav, handleSetSearchMobile } = this.props;
        const { 
            mainLevel,
            features,
            support,
            aboutus,
            contact,
            msol,
            resellers,
            zccMenu,
            posMenu,
            mcpMenu
        } = NAV_LINKS;

        return (
            <div id="navigationList" className={classes.NavList}>
                <nav>
                    {isTablet && <div className={classes.tabletNavList}>
                        <FontAwesomeIcon icon={faSearch} onClick={handleSetSearchMobile}/>
                        <FontAwesomeIcon icon={faBars} onClick={handleSetMobileNav} />
                    </div>}
                    {(!isTablet) && <ul>
                        <div className={classes.dropdown}>
                            <li><a id="features" onClick={this.setVisitedLink.bind(this, 'features')} className={classes["section-header"]} href={mainLevel['features']}>Features</a></li>
                            <ul id="feature-menu" className={[classes["dropdown-content"], classes.hidden].join(' ')}>
                                <li onMouseOver={this.showMenu.bind(this, 'msolutions')}>
                                    <a href={features['msol']}>Merchant Solutions</a>
                                </li>
                                <ul id="msolutions" className={[classes["sub-menu"], classes.hidden].join(' ')}>
                                    <li onMouseOver={this.hidePreviousMenu.bind(this, 'webXpressProcessing')}><a href={msol['webxpress']}>WebXPress Processing Gateway</a></li>
                                    <li 
                                        onMouseOver={this.showMenu.bind(this, classes.zccMenu)} 
                                        onMouseLeave={(e) => this.hideSubMenuFromLeft(e, 'zccMenu')}
                                        id="zeroCost"
                                    >
                                        <a href={msol['zcc']}>Zero Cost Credit</a>
                                    </li>
                                    <li onMouseOver={this.hidePreviousMenu.bind(this, 'achECheck')}><a href={msol['ach']}>ACH e-Check</a></li>
                                    <li onMouseOver={this.hidePreviousMenu.bind(this, 'memberManagement')} id="memberManagement"><a href={msol['mms']}>Membership Management Services</a></li>
                                    <li 
                                        onMouseOver={this.showMenu.bind(this, classes.posMenu)}
                                        onMouseLeave={(e) => this.hideSubMenuFromLeft(e, 'posMenu')}
                                        id="webXpress"
                                    >
                                        <a href={msol['pos']}>POS WebXPress Point-of-Sale Solutions</a>
                                    </li>
                                    <li onMouseOver={this.hidePreviousMenu.bind(this, 'fraudtrak')} id="fraudtrak"><a href={msol['fraud']}>FraudTrak2 Security Tools</a></li>
                                    <li><a href={msol['shoppingCart']}>Shopping Cart Solutions</a></li>
                                    <li onMouseOver={this.hidePreviousMenu.bind(this, 'billingPresentment')} id="billingPresentment"><a href={msol['billing']}>Billing Presentment Service</a></li>
                                    <li 
                                        onMouseOver={this.showMenu.bind(this, classes.mcMenu)} 
                                        onMouseLeave={(e) => this.hideSubMenuFromLeft(e, 'mcMenu')}
                                        id="multiCurrency"
                                    >
                                        <a href={msol['mcp']}>Multi-Currency Pricing</a>
                                    </li>
                                </ul>
                                <li onMouseOver={this.showMenu.bind(this, 'partnerReseller')}><a href={features['partners']}>Resellers / Partners</a></li>
                                <ul id="partnerReseller" className={[classes["sub-menu"], classes.hidden].join(' ')}>
                                    <li><a href={resellers['pss']}>Partner Software Solutions</a></li>
                                    <li><a href={resellers['map']}>Merchant Account Providers</a></li>
                                    <li><a href={resellers['processors']}>Processors</a></li>
                                    <li><a href={resellers['bap']}>Become a Partner</a></li>
                                </ul>
                                <li onMouseOver={this.hidePreviousMenu.bind(this, 'developers')} id="developers"><a href={features['developers']}>Developers</a></li>
                                <li id="demos"><a href={features['demos']}>Demos</a></li>
                            </ul>
                            <ul onMouseLeave={(e) => { e.preventDefault(); e.stopPropagation(); this.hideSubMenu('zccMenu') }} className={`${classes.subMenu} ${classes.hiddenSubMenu}`} id={classes.zccMenu}>
                                <li><a href={zccMenu['business']}>Business</a></li>
                                <li><a href={zccMenu['government']}>Government</a></li>
                                <li><a href={zccMenu['education']}>Education</a></li>
                                <li><a href={zccMenu['nfp']}>Not For Profit</a></li>
                            </ul>
                            <ul onMouseLeave={(e) => { e.preventDefault(); e.stopPropagation(); this.hideSubMenu('posMenu') }} className={`${classes.subMenu} ${classes.hiddenSubMenu}`} id={classes.posMenu}>
                                <li><a href={posMenu['hardware']}>POS Hardware</a></li>
                                <li><a href={posMenu['vendors']}>POS Vendors</a></li>
                            </ul>
                            <ul onMouseLeave={(e) => { e.preventDefault(); e.stopPropagation(); this.hideSubMenu('mcMenu') }} className={`${classes.subMenu} ${classes.hiddenSubMenu}`} id={classes.mcMenu}>
                                <li><a href={mcpMenu['dynamicCurr']}>Dynamic Currency Conversion</a></li>
                            </ul>
                        </div>
                        <div className={classes.dropdown}>
                            <li ><a className={classes["section-header"]} href={mainLevel['support']}>Support</a></li>
                            <ul id="support" className={classes["dropdown-content"]}>
                                <li><a href={support['supportOptions']}>Support Options</a></li>
                                <li><a href={support['gateway']}>Gateway System Status</a></li>
                                <li><a href={support['helpdesk']}>Helpdesk</a></li>
                                <li><a href={support['downloads']}>Downloads</a></li>
                                <li><a href={support['faqs']}>FAQs</a></li>
                            </ul>
                        </div>
                        <div className={classes.dropdown}>
                            <li><a className={classes["section-header"]} href={mainLevel['aboutus']}>About Us</a></li>
                            <ul id="aboutus" className={classes["dropdown-content"]}>
                                <li><a href={aboutus['why']}>Why Choose Us</a></li>
                                <li><a href={aboutus['clients']}>Our Satisfied Clients</a></li>
                                <li><a href={aboutus['blog']}>Our Blog</a></li>
                                <li><a href={aboutus['press']}>Press Releases</a></li>
                                <li><a href={aboutus['careers']}>Careers</a></li>
                            </ul>
                        </div>
                        <div className={classes.dropdown}>
                            <li><a onClick={this.setVisitedLink.bind(this, 'merchantLogin')} id="merchantLogin" className={[classes["section-header"], classes.visited].join(' ')} href="#">Merchant Login</a></li>
                        </div>
                        <div className={classes.dropdown}>
                            <li><a onClick={this.setVisitedLink.bind(this, 'resellerLogin')} id="resellerLogin" className={classes["section-header"]} href="#">Reseller Login</a></li>
                        </div>
                        <div className={classes.dropdown}>
                            <li><a className={classes["section-header"]} href={mainLevel['contact']}>Contact</a></li>
                            <ul id="contact-header" className={`${classes["dropdown-content"]} ${classes["contact-dropdown"]}`}>
                                <li><a href={contact['contactus']}>Contact Us</a></li>
                                <li><a href={contact['merchant']}>Merchant Information Request</a></li>
                                <li><a href={contact['reseller']}>Reseller/Partner Information Request</a></li>
                            </ul>
                        </div>
                        <div className={`${classes.dropdown} ${classes["search-dropdown"]}`}>
                            <li><div className={classes["search-icon"]}><FontAwesomeIcon icon={faSearch} onClick={this.handleDisplaySearch} /></div></li>
                            {displaySearch && <SearchBar />}
                        </div>
                    </ul>}
                </nav>
            </div>
        );
    }
}

export default NavList;