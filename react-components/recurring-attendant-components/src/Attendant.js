import React, {Component} from 'react';

import { BrowserRouter, Route, Switch } from 'react-router-dom';

/* Layout Components */
import PNPHeader from './PNPComponents/PNPHeader/PNPHeader';
import PNPSidebar from './PNPComponents/PNPSidebar/PNPSidebar';
import PNPModal from "./PNPComponents/PNPModal/PNPModal";

/* Objects */
import './Lib/Objects/Tools';
import AttendantSession from "./Lib/Objects/AttendantSession";
import CustomerProfile from "./Lib/Objects/CustomerProfile";
import CustomerPaymentSource from "./Lib/Objects/CustomerPaymentSource";

/* Sections */
import Loading from "./Attendant/Loading";
import Error from "./Attendant/Error";
import MakePayment from './Attendant/MakePayment';
import External from './Attendant/External';
import Content from './PNPComponents/Content';

/* Themes */
import './Attendant.css';
import './Themes/CardX/CardX-Theme.css';
import './Themes/Plugnpay/Plugnpay-Theme.css';
import State from "./Lib/Objects/State";
import Country from "./Lib/Objects/Country";


class Attendant extends Component {
    constructor(props) {
        super(props);

        // create e reference to the nav for the mobileToggleHandler to use
        this.nav = React.createRef();

        this.state = {
            pagesGenerated: false,
            attendantSession: new AttendantSession(),
            // profile: undefined,
            currentSection: {sectionTemplate: "loading", path: "/loading", title: "Loading...", component: Loading},
            menuContent: [],
            sections: [],
            nav: "closed",
            countries: [],
            states: [],
            profile: new CustomerProfile(),
            paymentSource: new CustomerPaymentSource(),
            // modalContent: {},
            // modalButtons: [],
            isLoading: true,
            mobileToggle: false
        };
    }

    loadSelectorData = () => {
        let countryCode = new Country();
        let countries = [];
        countryCode.loadCountries({'success': (data) => {
                let tmpCountries = data.getCountries();
                tmpCountries.map((country) => {
                    countries.push({'value': country.getTwoLetter(), 'displayValue': country.getCommonName()});
                });
                countries.push({'value': '', 'displayValue': ' Select Country'});

                this.setState({
                    countries: countries
                });

            }, 'error': (error) => console.log(error)
        });
    };

    loadStateData = (val, callback = null) => {
        let stateObj = new State();
        let states = [];
        stateObj.loadStates(val, {
            'success': (data) => {
                data.getStates().map((state) => {
                    states.push({'value': state.getAbbreviation(), 'displayValue': state.getCommonName()});
                });
                states.push({'value': '', 'displayValue': ' Select State'});

                this.setState({ states: states }, () => {
                    if (typeof(callback) === "function") {
                        callback();
                    }
                });
            },
            'error': (error) => { console.log(error) }
        })
    };

    handleClick(props) {
        this.setState({content: props.content, rSelected: props.id});
    }

    loadProfileData = () => {
        this.state.profile.load();
    };

    loadPaymentSourceData = () => {
        this.state.paymentSource.load();
    };

    loadSessionData = () => {
        this.state.attendantSession.loadSessionInfo((session) => {
            let sections = session.getSections();
            let isMenuHidden = session.getMenuHidden();
            let pageTitle = session.getTitle();
            let  menuContent = sections.map((sectionName) => {
                const relabel = session.getSectionLabel(sectionName);
                const settings = session.getSectionSettings(sectionName);
                let section = {...this.sectionTemplates[settings.sectionTemplate]};

                if (typeof(relabel === "string") && relabel !== "") {
                    section.title = relabel;
                }

                if (typeof(settings.path) === "string" && settings.path !== "") {
                    section.sectionName = sectionName;
                    if (settings.path.startsWith("http")) {
                        section.path = settings.path;
                    } else {
                        section.path = "/" + settings.path;
                    }
                }

                if (typeof(settings.mode) === "string" && settings.mode !== "") {
                    section.mode = settings.mode;
                }

                if (typeof(settings.payable) === "string" && settings.payable !== "") {
                    section.payable = settings.payable
                } else {
                    section.payable = false;
                }

                if (typeof(settings.deleteInfoLink) === "string" && settings.deleteInfoLink !== "") {
                    section.deleteInfoLink = settings.deleteInfoLink
                } else {
                    section.deleteInfoLink = "true"; //default to true if the deleteInfoLink option was not included
                }

                return section;
            });
            let currentSection = undefined;
            try {
                currentSection = menuContent[0];
            } catch (e) {
                currentSection = {sectionTemplate: "error", sectionName: "Error", path: "/error", title: "An error occurred.", component: Error};
            }
            this.setState({
                attendantSession: session,
                menuContent: menuContent,
                currentSection: currentSection,
                menuHidden: isMenuHidden,
                pageTitle: pageTitle,
                isLoading: false
            });
        });
    };

    componentDidMount() {
        this.loadSelectorData();
        this.loadProfileData();
        this.loadPaymentSourceData();
        this.loadSessionData();
    };

    sectionTemplates = {
        "payment":   {sectionTemplate: "payment", path: "/payment", title: "Make a Payment", component: MakePayment},
        "external":  {sectionTemplate: "external", path: "/external", title: "External link", component: External}
        // "recurring": {sectionTemplate: "recurring", path: "/recurring", title: "Set up a Recurring Payment", component: MakePayment},
    };

    onChangePage = (event, section) => {
        this.setState({ currentSection: section });
        if (this.state.nav === "open") { /* only toggle if open so that menu closes when a section is selected */
            this.mobileNavToggleHandler();
            // this.nav.current.setClosedState(); // commented this out cause it was erroring as not a function.
            if (typeof(this.state.currentSection.component.initSection) === "function") {
                this.state.currentSection.component.initSection();
            } else {
                console.log("you will have to find another way...");
            }
        }
    };

    // navToggled = () => {
    mobileNavToggleHandler = () => {
        if (this.state.nav === "closed") {
            this.setState({nav: "open", mobileToggle: true});
        } else {
            this.setState({nav: "closed", mobileToggle: false });
        }
    };

    render() {
        let first = true;

        document.title = this.state.pageTitle ? this.state.pageTitle : '';

        let settings = undefined;
        if (this.state.currentSection.path !== "/loading") {
            settings = this.state.attendantSession.getSectionSettings(this.state.currentSection.sectionName)
        }

        let relayedProfile = this.state.attendantSession.getRelayedProfile();

        let classes = [];

        if (window.location.hostname.match(/paywithcardx.com/)) {
            classes.push("CardX-Theme");
        } else {
            classes.push("Plugnpay-Theme");
        }

        if (this.state.nav === "open") {
            classes.push("open");
        }
        const classNames = classes.join(" ");

        const additionalData = this.state.attendantSession.getAdditionalData();
        let entityNameText;
        let receiptEntityNameTitle;

        if (additionalData) {
            entityNameText = additionalData['entityName'];
            receiptEntityNameTitle = additionalData['receiptEntityNameTitle'];
        }

        let routes;
        if (settings !== undefined) {
            routes = this.state.menuContent.map((contentItem) => {
                if (first) {
                    contentItem.path = '/';
                    first = false;
                }

                return <Route
                    exact key={contentItem.path}
                    path={contentItem.path}
                    render={(props) => {
                        return (<contentItem.component
                            {...props}
                            settings={settings}
                            relayedProfile={relayedProfile}
                            profile={this.state.profile}
                            paymentSource={this.state.paymentSource}
                            countries={this.state.countries}
                            states={this.state.states}
                            loadStates={this.loadStateData}
                            currentSection={this.state.currentSection}
                            session={this.state.attendantSession}
                            modalMessage={this.state.modalMessage}
                            entityName={entityNameText}
                            receiptEntityNameTitle={receiptEntityNameTitle}
                        />)
                    }}
                />
            });
        }



        let sidebar = this.state.menuHidden === "false" ? <PNPSidebar navState={this.state.nav} content={this.state.menuContent} change={this.onChangePage} /> : null;
        let content = this.state.menuHidden === "true" ? (
            <MakePayment
                settings={settings}
                relayedProfile={this.relayedProfile}
                profile={this.state.profile}
                paymentSource={this.state.paymentSource}
                countries={this.state.countries}
                states={this.state.states}
                loadStates={this.loadStateData}
                currentSection={this.state.currentSection}
                session={this.state.attendantSession}
                toggleModalHandler={this.toggleModalHandler}
                entityName={entityName}
                receiptEntityNameTitle={receiptEntityNameTitle}
            />
        ) : routes;

        let entityName;
        if (additionalData) {
            if (additionalData['entityName']) {
                entityName = (
                    <div id="entityName">
                        <h2>{additionalData['entityName']}</h2>
                    </div>
                )
            }
        }

        return (
            <div id={"attendant"} className={classNames}>
                <BrowserRouter basename="/recurring/attendant">
                    <Content>
                        {sidebar}
                        <PNPHeader hamburgerVisible={true} ref={this.nav} title={this.state.currentSection.title} mobileNavToggleHandler={this.mobileNavToggleHandler} toggled={this.state.mobileToggle}/>
                        <div className={"section"}>
                            {entityName}
                            {content}
                        </div>
                    </Content>
                </BrowserRouter>
            </div>
        );
    }
}


export default Attendant;
