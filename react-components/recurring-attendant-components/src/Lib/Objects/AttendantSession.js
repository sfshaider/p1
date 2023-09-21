import getTools from './Tools'

class AttendantSession {
    constructor(load=false,options) {
        if (load) {
            this.loadSessionInfo((session) => {
                if (typeof(options["success"]) === "function") {
                    options["success"](session);
                }
            });

        }
    }

    self = this;
    _error = false;

    setError = (errorMsg) => {
        this._error = true;
        this.setErrorMessage(errorMsg);
    };

    getError = () => {
        return this._error;
    };

    setErrorMessage = (errorMsg) => {
        this._errorMessage = errorMsg;
    };
    getErrorMessage = () => {
        return this._errorMessage;
    };

    setGatewayAccount = (gatewayAccount) => {
        this._gatewayAccount = gatewayAccount;
    };

    getGatewayAccount = () => {
        return this._gatewayAccount;
    };

    setCustomer = (customer) => {
        this._customer = customer;
    };

    getCustomer = () => {
        return this._customer;
    };

    setSessionID = (sessionID) => {
        this._sessionID = sessionID;
    };

    getSessionID = () => {
        return this._sessionID;
    };

    setAdditionalData = (additionalData) => {
        this._additionalData = additionalData;
    };

    getAdditionalData = () => {
        return this._additionalData;
    };

    isValidPropertyOfObject = (aProperty,anObject) => {
        return (typeof anObject[aProperty] === "object" && anObject.hasOwnProperty(aProperty));
    };

    getSections = () => {
        let sections = [];

        if (this.isValidPropertyOfObject("_additionalData",this)) {
            if (this.isValidPropertyOfObject("sections",this._additionalData)) {
                for (let sectionArrayIndex in this._additionalData["sections"]) {
                    sections.push(this._additionalData["sections"][sectionArrayIndex]["name"]);
                }
            }
        }

        return sections;
    };

    getSectionData = (sectionName) => {
        let sectionData = {};

        if (this.isValidPropertyOfObject("_additionalData",this)) {
            if (this.isValidPropertyOfObject("sections",this._additionalData)) {
                for (let sectionArrayIndex in this._additionalData["sections"]) {
                    if (this._additionalData["sections"][sectionArrayIndex]["name"] === sectionName) {
                        sectionData = this._additionalData["sections"][sectionArrayIndex];
                    }
                }
            }
        }

        return sectionData;
    };

    setMenuHidden = (isHidden) => {
        this._menuHidden = isHidden;
    };

    getMenuHidden = () => {
        return this._menuHidden;
    }

    setTitle = (title) => {
        this._title = title;
    }

    getTitle = (title) => {
        return this._title;
    }

    getSectionLabel = (sectionName) => {
        let sectionData = this.getSectionData(sectionName);
        return sectionData["label"];
    };

    getSectionSettings = (sectionName) => {
        let sectionData = this.getSectionData(sectionName);
        return sectionData["settings"];
    };

    getRelayedProfile = () => {
        let relayedProfile = {};

        if (this.isValidPropertyOfObject("_additionalData",this)) {
            if (this.isValidPropertyOfObject("profile",this._additionalData)) {
                relayedProfile = this._additionalData.profile;
            }
        }

        return relayedProfile;
    }

    setStatus = (status) => {
        this._status = status;
    };

    getStatus = () => {
        return this._status;
    };

    loadSessionInfo = (callback) => {
        const tools = getTools();

        tools.json({
            action: 'read',
            url: '/recurring/attendant/api/merchant/customer/session',
            onSuccess: (data) => {
                this.setStatus(data['content']['status']);
                const sessionData = data["content"]["session"];
                this.setAdditionalData(sessionData['additionalData']);
                this.setMenuHidden(sessionData['additionalData']['menuHidden']);
                this.setTitle(sessionData['additionalData']['title']);
                if (typeof(callback) === 'function') {
                    callback(this);
                }
            },
            onError: (xhr) => {
                if (xhr.status === 403) {
                    this.setError('Unauthorized.');
                } else if (xhr.status === 422) {
                    this.setError('Invalid session.');
                } else {
                    this.setError('Failed to load session information.');
                }

                if (typeof(callback) === 'function') {
                    callback(this);
                }
            }
        });
    }
}

export default AttendantSession;