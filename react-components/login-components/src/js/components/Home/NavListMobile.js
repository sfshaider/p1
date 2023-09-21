import React, { useState } from 'react';
import classes from './NavListMobile.css';
import NAV_LINKS from '../../constants/navLinks';
import NavListMobileItem from './NavListMobileItem';

const NavListMobile = props => {
    const [dropdowns, setDropdowns] = useState({
        features: false,
        support: false,
        aboutus: false,
        contact: false,
        msol: false,
        resellers: false,
        zccMenu: false,
        posMenu: false,
        mcMenu: false,
    });

    const handleSetDropdowns = (header) => {
        setDropdowns({ ...dropdowns, [header]: !dropdowns[header] });
    };

    const setVisitedLink = (id) => {
        if (id === 'merchantLogin') {
            props.update('merchant');
        }
        if (id === 'resellerLogin') {
            props.update('reseller');
        }
    };

    const mobileHiddenClass = (showMenu) => {
        return showMenu ? "" : classes.MobileNavHidden;
    };

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
        <ul className={`${classes.MobileNav} ${!props.show ? classes.MobileNavHidden : ""} ${props.show ? "" : classes.NavContainer}`}>
            <li>
                <NavListMobileItem 
                    link={mainLevel['features']} 
                    text='Features' 
                    handleSubMenu={(e) => { e.preventDefault(); handleSetDropdowns('features') }} 
                    hasSubMenu={true}
                />
                <ul className={`${classes.MobileNavBlock} ${mobileHiddenClass(dropdowns.features)}`}>
                    <li>
                        <NavListMobileItem
                            link={features['msol']}
                            text='Merchant Solutions'
                            handleSubMenu={(e) => { e.preventDefault(); handleSetDropdowns('msol') }}
                            hasSubMenu={true}
                            layer={2}
                        />
                        <ul className={`${classes.MobileNavBlock} ${mobileHiddenClass(dropdowns.msol)}`}>
                            <li><NavListMobileItem link={msol['webxpress']} text='WebXPress Processing Gateway' layer={3} /></li>
                            <li>
                                <NavListMobileItem
                                    link={msol['zcc']}
                                    text='Zero Cost Credit'
                                    handleSubMenu={(e) => { e.preventDefault(); handleSetDropdowns('zccMenu') }}
                                    hasSubMenu={true}
                                    layer={3}
                                />
                                <ul className={`${classes.MobileNavBlock} ${mobileHiddenClass(dropdowns.zccMenu)}`}>
                                    <li><NavListMobileItem link={zccMenu['business']} text='Business' layer={4} /></li>
                                    <li><NavListMobileItem link={zccMenu['government']} text='Government' layer={4} /></li>
                                    <li><NavListMobileItem link={zccMenu['education']} text='Education' layer={4} /></li>
                                    <li><NavListMobileItem link={zccMenu['nfp']} text='Not For Profit' layer={4} /></li>
                                </ul>
                            </li>
                            <li><NavListMobileItem link={msol['ach']} text='ACH e-Check' layer={3} /></li>
                            <li><NavListMobileItem link={msol['mms']} text='Membership Management Services' layer={3} /></li>
                            <li>
                                <NavListMobileItem
                                    link={msol['pos']}
                                    text='POS WebXPress Point-of-Sale Solutions'
                                    handleSubMenu={(e) => { e.preventDefault(); handleSetDropdowns('posMenu') }}
                                    hasSubMenu={true}
                                    layer={3}
                                />
                                <ul className={`${classes.MobileNavBlock} ${mobileHiddenClass(dropdowns.posMenu)}`}>
                                    <li><NavListMobileItem link={posMenu['hardware']} text='POS Hardware' layer={4} /></li>
                                    <li><NavListMobileItem link={posMenu['vendors']} text='POS Vendors' layer={4} /></li>
                                </ul>
                            </li>
                            <li><NavListMobileItem link={msol['fraud']} text='FraudTrak2 Security Tools' layer={3} /></li>
                            <li><NavListMobileItem link={msol['shoppingCart']} text='Shopping Cart Solutions' layer={3} /></li>
                            <li><NavListMobileItem link={msol['billing']} text='Billing Presentment Service' layer={3} /></li>
                            <li>
                                <NavListMobileItem
                                    link={msol['mcp']}
                                    text='Multi-Currency Pricing'
                                    handleSubMenu={(e) => { e.preventDefault(); handleSetDropdowns('mcMenu') }}
                                    hasSubMenu={true}
                                    layer={3}
                                />
                                <ul className={`${classes.MobileNavBlock} ${mobileHiddenClass(dropdowns.mcMenu)}`}>
                                    <li><NavListMobileItem link={mcpMenu['dynamicCurr']} text='Dynamic Currency Conversion' layer={4} /></li>
                                </ul>
                            </li>
                        </ul>
                    </li>
                    <li>
                        <NavListMobileItem
                            link={features['partners']}
                            text='Resellers / Partners'
                            handleSubMenu={(e) => { e.preventDefault(); handleSetDropdowns('resellers') }}
                            hasSubMenu={true}
                            layer={2}
                        />
                        <ul className={`${classes.MobileNavBlock} ${mobileHiddenClass(dropdowns.resellers)}`}>
                            <li><NavListMobileItem link={resellers['pss']} text='Partner Software Solutions' layer={3} /></li>
                            <li><NavListMobileItem link={resellers['map']} text='Merchant Account Providers' layer={3} /></li>
                            <li><NavListMobileItem link={resellers['processors']} text='Processors' layer={3} /></li>
                            <li><NavListMobileItem link={resellers['bap']} text='Become a Partner' layer={3} /></li>
                        </ul>
                    </li>
                    <li><NavListMobileItem link={features['developers']} text='Developers' layer={2} /></li>
                    <li><NavListMobileItem link={features['demos']} text='Demos' layer={2} /></li>
                </ul>
            </li>
            <li>
                <NavListMobileItem 
                    link={mainLevel['support']} 
                    text='Support' 
                    handleSubMenu={(e) => { e.preventDefault(); handleSetDropdowns('support') }}
                    hasSubMenu={true}
                />
                <ul className={`${classes.MobileNavBlock} ${mobileHiddenClass(dropdowns.support)}`}>
                    <li><NavListMobileItem link={support['supportOptions']} text='Support Options' layer={2} /></li>
                    <li><NavListMobileItem link={support['gateway']} text='Gateway System Status' layer={2} /></li>
                    <li><NavListMobileItem link={support['helpdesk']} text='Helpdesk' layer={2} /></li>
                    <li><NavListMobileItem link={support['downloads']} text='Downloads' layer={2} /></li>
                    <li><NavListMobileItem link={support['faqs']} text='FAQs' layer={2} /></li>
                </ul>
            </li>
            <li>
                <NavListMobileItem 
                    link={mainLevel['aboutus']} 
                    text='About Us' 
                    handleSubMenu={(e) => { e.preventDefault(); handleSetDropdowns('aboutus') }}
                    hasSubMenu={true}
                />
                <ul className={`${classes.MobileNavBlock} ${mobileHiddenClass(dropdowns.aboutus)}`}>
                    <li><NavListMobileItem link={aboutus['why']} text='Why Choose Us' layer={2} /></li>
                    <li><NavListMobileItem link={aboutus['clients']} text='Our Satisfied Clients' layer={2} /></li>
                    <li><NavListMobileItem link={aboutus['blog']} text='Our Blog' layer={2} /></li>
                    <li><NavListMobileItem link={aboutus['press']} text='Press Releases' layer={2} /></li>
                    <li><NavListMobileItem link={aboutus['careers']} text='Careers' layer={2} /></li>
                </ul>
            </li>
            <li><NavListMobileItem text='Merchant Login' handleSubMenu={() => setVisitedLink('merchantLogin')} /></li>
            <li><NavListMobileItem text='Reseller Login' handleSubMenu={() => setVisitedLink('resellerLogin')} /></li>
            <li>
                <NavListMobileItem 
                    link={mainLevel['contact']} 
                    text='Contact' 
                    handleSubMenu={(e) => { e.preventDefault(); handleSetDropdowns('contact') }}
                    hasSubMenu={true}
                />
                <ul className={`${classes.MobileNavBlock} ${mobileHiddenClass(dropdowns.contact)}`}>
                    <li><NavListMobileItem link={contact['contactus']} text='Contact Us' layer={2} /></li>
                    <li><NavListMobileItem link={contact['merchant']} text='Merchant Information Request' layer={2} /></li>
                    <li><NavListMobileItem link={contact['reseller']} text='Reseller/Partner Information Request' layer={2} /></li>
                </ul>
            </li>
        </ul>
    );
};

export default NavListMobile;
